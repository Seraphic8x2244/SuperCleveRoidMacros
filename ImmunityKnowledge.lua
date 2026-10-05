local _G = _G or getfenv(0)
local CleveRoids = _G.CleveRoids or {}
_G.CleveRoids = CleveRoids

-- Slice 4 durable knowledge reducer.
--
-- This module consumes normalized observations and persists only:
--   * authoritative per-dimension vulnerability facts; and
--   * unresolved ambiguous immunity hypotheses with linked candidates.
--
-- Permanent immunity confirmation/revocation, dynamic suspicion, production
-- query cutover and UI/SCT are deliberately deferred to later slices.
local Pipeline = CleveRoids.ImmunityObservations
local Storage = CleveRoids.ImmunityStorage
local Transient = CleveRoids.ImmunityTransient

local Knowledge = CleveRoids.ImmunityKnowledge or {}
CleveRoids.ImmunityKnowledge = Knowledge

local CANDIDATE_DIMENSIONS = {
    physical = true,
    holy = true,
    fire = true,
    nature = true,
    frost = true,
    shadow = true,
    arcane = true,

    stun = true,
    freeze = true,
    knockout = true,
    fear = true,
    root = true,
    silence = true,
    sleep = true,
    charm = true,
    polymorph = true,
    banish = true,
    shackle = true,
    horror = true,
    disorient = true,
    daze = true,
    snare = true,

    bleed = true,
    dispel_magic = true,
    curse = true,
    disease = true,
    poison = true,
}

-- Broad facts are reserved by the schema and later slices, but Slice 4 never
-- manufactures broad-immunity candidates or promotes them.
local FACT_DIMENSIONS = {}
for dimension in pairs(CANDIDATE_DIMENSIONS) do
    FACT_DIMENSIONS[dimension] = true
end
FACT_DIMENSIONS.spell = true
FACT_DIMENSIONS.cc = true
FACT_DIMENSIONS.all = true

local NONPHYSICAL_SCHOOLS = {
    holy = true,
    fire = true,
    nature = true,
    frost = true,
    shadow = true,
    arcane = true,
}

local diagnostics = {
    observationsSeen = 0,
    successesSeen = 0,
    vulnerabilitiesRecorded = 0,
    vulnerableCandidatesEliminated = 0,
    hypothesesCreated = 0,
    hypothesesDeduped = 0,
    hypothesesDiscardedKnownVulnerable = 0,
    hypothesesBlockedTransient = 0,
    ambiguousUnsupported = 0,
    missingIdentity = 0,
    storageUnavailable = 0,
    storageErrors = 0,
    deferredImmuneContradictions = 0,
    last = nil,
}

local function incrementLast(kind, observation, detail)
    diagnostics.last = {
        kind = kind,
        sequence = observation and observation.sequence or nil,
        event = observation and observation.event or nil,
        mobID = observation and observation.targetMobID or nil,
        spellID = observation and observation.spellID or nil,
        detail = detail,
    }
end

local function validMobID(value)
    local number = tonumber(value)
    if not number or number <= 0 or number ~= math.floor(number) then
        return nil
    end
    return number
end

local function validSpellID(value)
    local number = tonumber(value)
    if not number or number <= 0 or number ~= math.floor(number) then
        return nil
    end
    return number
end

local function addDimension(list, seen, dimension)
    if not dimension or not CANDIDATE_DIMENSIONS[dimension] or seen[dimension] then
        return
    end
    seen[dimension] = true
    table.insert(list, dimension)
end

local function sortedCopy(list)
    local result = {}
    local i
    for i = 1, table.getn(list or {}) do
        result[i] = list[i]
    end
    table.sort(result)
    return result
end

local function candidateSignature(list)
    return table.concat(sortedCopy(list), "|")
end

local function quoteText(value, allowNil)
    local result, err = Storage.SQLText(value, allowNil)
    if not result then
        return nil, err
    end
    return result
end

local function quoteInteger(value, minimum, allowNil)
    local result, err = Storage.SQLInteger(value, minimum, allowNil)
    if not result then
        return nil, err
    end
    return result
end

local function storageReady()
    return Storage and Storage.IsReady and Storage.IsReady()
end

local function executeTransaction(statements)
    if table.getn(statements) == 0 then
        return true
    end

    local sql = "BEGIN;\n" .. table.concat(statements, "\n") .. "\nCOMMIT;"
    local ok, err = Storage.Execute(sql)
    if not ok then
        pcall(Storage.Execute, "ROLLBACK;")
        return false, err
    end
    return true
end

local function mobStatements(mobID, name)
    local mobSQL = quoteInteger(mobID, 1, false)
    if not mobSQL then return nil end

    local statements = {}
    if type(name) == "string" and name ~= "" then
        local nameSQL = quoteText(name, false)
        if not nameSQL then return nil end
        table.insert(statements,
            "INSERT OR IGNORE INTO mobs (mob_id, last_name) VALUES (" ..
            mobSQL .. ", " .. nameSQL .. ");")
        table.insert(statements,
            "UPDATE mobs SET last_name = " .. nameSQL ..
            " WHERE mob_id = " .. mobSQL .. ";")
    else
        table.insert(statements,
            "INSERT OR IGNORE INTO mobs (mob_id, last_name) VALUES (" ..
            mobSQL .. ", NULL);")
    end
    return statements
end

local function appendStatements(target, source)
    local i
    for i = 1, table.getn(source or {}) do
        table.insert(target, source[i])
    end
end

local function loadFactMap(mobID)
    local mobSQL = quoteInteger(mobID, 1, false)
    if not mobSQL then return false, "invalid mob ID" end

    local ok, rows = Storage.Query(
        "SELECT dimension, verdict, dynamic_suspected, proof_source, " ..
        "proof_spell_id, proof_event FROM facts WHERE mob_id = " .. mobSQL
    )
    if not ok then return false, rows end

    local result = {}
    local i
    for i = 1, table.getn(rows) do
        local row = rows[i]
        if row and row.dimension then
            result[tostring(row.dimension)] = row
        end
    end
    return true, result
end

local function queryCandidateCount(mobID, dimensions)
    if table.getn(dimensions or {}) == 0 then return 0 end

    local mobSQL = quoteInteger(mobID, 1, false)
    if not mobSQL then return 0 end

    local quoted = {}
    local i
    for i = 1, table.getn(dimensions) do
        local value = quoteText(dimensions[i], false)
        if value then table.insert(quoted, value) end
    end
    if table.getn(quoted) == 0 then return 0 end

    local ok, rows = Storage.Query(
        "SELECT COUNT(*) AS candidate_count " ..
        "FROM hypothesis_candidates c " ..
        "JOIN hypotheses h ON h.hypothesis_id = c.hypothesis_id " ..
        "WHERE h.mob_id = " .. mobSQL ..
        " AND c.dimension IN (" .. table.concat(quoted, ",") .. ")"
    )
    if not ok or table.getn(rows) == 0 then return 0 end
    return tonumber(rows[1].candidate_count) or 0
end

local function successDimensions(observation)
    local result = {}
    local seen = {}
    local profile = observation and observation.spell or nil

    if not observation or not profile then return result end

    if observation.kind == "damage" and observation.outcome == "damage_landed" then
        local school = observation.runtimeSchool or profile.school
        addDimension(result, seen, school)
        return result
    end

    if observation.kind ~= "aura"
        or observation.outcome ~= "aura_present"
        or observation.auraKind ~= "debuff" then
        return result
    end

    -- A real hostile aura proves the spell/action school did not block the
    -- application, independently from any exact mechanic/effect-family proof.
    addDimension(result, seen, profile.school)
    addDimension(result, seen, profile.dispelDimension)

    if profile.spellMechanicDimension then
        addDimension(result, seen, profile.spellMechanicDimension)
        return result
    end

    -- Nampower aura presence has no effect index. If exactly one recognized
    -- aura-effect dimension exists, that dimension is authoritative; if several
    -- differ, do not guess which effect the observed aura slot represents.
    local auraDimensions = {}
    local auraSeen = {}
    local i
    for i = 1, 3 do
        local effect = profile.effects and profile.effects[i] or nil
        if effect and effect.auraName and effect.auraName > 0
            and effect.mechanicDimension then
            addDimension(auraDimensions, auraSeen, effect.mechanicDimension)
        end
    end
    if table.getn(auraDimensions) == 1 then
        addDimension(result, seen, auraDimensions[1])
    end

    return result
end

local function hypothesisCandidates(observation)
    local result = {}
    local seen = {}
    local profile = observation and observation.spell or nil

    if not observation or not profile then return result end

    if observation.failurePath == "whole_spell" then
        -- A static target-creature restriction is an alternate non-permanent
        -- vMaNGOS IMMUNE path. Because it is not a durable immunity dimension,
        -- do not create a hypothesis that Slice 5 could later over-confirm.
        if profile.targetCreatureType and profile.targetCreatureType > 0 then
            return result
        end

        -- vMaNGOS generic IMMUNE: only whole-spell causes belong here. Per-effect
        -- mechanics are intentionally excluded because those failures are silent.
        addDimension(result, seen, profile.school)
        addDimension(result, seen, profile.spellMechanicDimension)
        addDimension(result, seen, profile.dispelDimension)
        return result
    end

    if observation.failurePath == "effect_mask_zero" then
        -- vMaNGOS IMMUNE2 can represent per-effect mechanic, aura-state,
        -- effect-type, or other effect-mask elimination. Slice 4 does not model
        -- every one of those as a durable dimension, so storing only the known
        -- subset would make a later single-candidate confirmation unsafe.
        return result
    end

    -- Portable/Octo raw IMMUNE semantics remain deliberately unverified. The
    -- adapter must normalize a proven failure path before durable hypotheses are
    -- allowed; the common reducer never branches on a core name.
    return result
end

local function hasApplicableTransientExplanation(observation, candidates)
    if not Transient or not Transient.GetExplanations then
        return false
    end

    local explanations = Transient.GetExplanations(observation)
    local candidateSet = {}
    local i
    for i = 1, table.getn(candidates or {}) do
        candidateSet[candidates[i]] = true
    end

    for i = 1, table.getn(explanations or {}) do
        local explanation = explanations[i]
        local source = explanation and explanation.source or nil
        local dimension = explanation and explanation.dimension or nil

        if source == "reflection"
            or source == "death"
            or source == "dr"
            or source == "dr_category_uncertain"
            or source == "target_identity_unresolved" then
            return true, explanation
        end

        if dimension == "all" then
            return true, explanation
        end

        if dimension == "spell" then
            local school = observation.spell and observation.spell.school or nil
            if NONPHYSICAL_SCHOOLS[school] then
                return true, explanation
            end
        elseif dimension and candidateSet[dimension] then
            return true, explanation
        end
    end

    return false
end

function Knowledge.GetFact(mobID, dimension)
    mobID = validMobID(mobID)
    if not mobID or not FACT_DIMENSIONS[dimension] or not storageReady() then
        return nil
    end

    local mobSQL = quoteInteger(mobID, 1, false)
    local dimensionSQL = quoteText(dimension, false)
    if not mobSQL or not dimensionSQL then return nil end

    local ok, rows = Storage.Query(
        "SELECT verdict, dynamic_suspected, proof_source, proof_spell_id, proof_event " ..
        "FROM facts WHERE mob_id = " .. mobSQL ..
        " AND dimension = " .. dimensionSQL .. " LIMIT 1"
    )
    if not ok or table.getn(rows) == 0 then return nil end

    local row = rows[1]
    return {
        mobID = mobID,
        dimension = dimension,
        verdict = row.verdict and tostring(row.verdict) or nil,
        dynamicSuspected = tonumber(row.dynamic_suspected) == 1,
        proofSource = row.proof_source,
        proofSpellID = tonumber(row.proof_spell_id),
        proofEvent = row.proof_event,
    }
end

function Knowledge.GetHypotheses(mobID)
    mobID = validMobID(mobID)
    if not mobID or not storageReady() then return {} end

    local mobSQL = quoteInteger(mobID, 1, false)
    if not mobSQL then return {} end

    local ok, rows = Storage.Query(
        "SELECT h.hypothesis_id, h.proof_source, h.proof_spell_id, h.proof_event, " ..
        "c.dimension FROM hypotheses h " ..
        "JOIN hypothesis_candidates c ON c.hypothesis_id = h.hypothesis_id " ..
        "WHERE h.mob_id = " .. mobSQL ..
        " ORDER BY h.hypothesis_id, c.dimension"
    )
    if not ok then return {} end

    local ordered = {}
    local byID = {}
    local i
    for i = 1, table.getn(rows) do
        local row = rows[i]
        local id = tonumber(row.hypothesis_id)
        if id then
            local item = byID[id]
            if not item then
                item = {
                    hypothesisID = id,
                    mobID = mobID,
                    proofSource = row.proof_source,
                    proofSpellID = tonumber(row.proof_spell_id),
                    proofEvent = row.proof_event,
                    candidates = {},
                }
                byID[id] = item
                table.insert(ordered, item)
            end
            if row.dimension then
                table.insert(item.candidates, tostring(row.dimension))
            end
        end
    end

    for i = 1, table.getn(ordered) do
        ordered[i].readyForConfirmation = table.getn(ordered[i].candidates) == 1
    end
    return ordered
end

function Knowledge.GetDimensionState(mobID, dimension)
    if not FACT_DIMENSIONS[dimension] then return "unknown" end

    local fact = Knowledge.GetFact(mobID, dimension)
    if fact and fact.verdict then
        return fact.verdict, fact
    end

    mobID = validMobID(mobID)
    if not mobID or not storageReady() then return "unknown" end

    local mobSQL = quoteInteger(mobID, 1, false)
    local dimensionSQL = quoteText(dimension, false)
    if not mobSQL or not dimensionSQL then return "unknown" end

    local ok, rows = Storage.Query(
        "SELECT h.hypothesis_id FROM hypotheses h " ..
        "JOIN hypothesis_candidates c ON c.hypothesis_id = h.hypothesis_id " ..
        "WHERE h.mob_id = " .. mobSQL ..
        " AND c.dimension = " .. dimensionSQL .. " LIMIT 1"
    )
    if ok and table.getn(rows) > 0 then
        return "suspected", { hypothesisID = tonumber(rows[1].hypothesis_id) }
    end
    return "unknown"
end

function Knowledge.GetSuspectedDimensions(mobID)
    mobID = validMobID(mobID)
    if not mobID or not storageReady() then return {} end

    local mobSQL = quoteInteger(mobID, 1, false)
    if not mobSQL then return {} end

    local ok, rows = Storage.Query(
        "SELECT DISTINCT c.dimension FROM hypothesis_candidates c " ..
        "JOIN hypotheses h ON h.hypothesis_id = c.hypothesis_id " ..
        "LEFT JOIN facts f ON f.mob_id = h.mob_id AND f.dimension = c.dimension " ..
        "WHERE h.mob_id = " .. mobSQL .. " AND f.mob_id IS NULL " ..
        "ORDER BY c.dimension"
    )
    if not ok then return {} end

    local result = {}
    local i
    for i = 1, table.getn(rows) do
        if rows[i].dimension then
            table.insert(result, tostring(rows[i].dimension))
        end
    end
    return result
end

local function recordVulnerability(observation)
    local mobID = validMobID(observation.targetMobID)
    if not mobID then
        diagnostics.missingIdentity = diagnostics.missingIdentity + 1
        incrementLast("success_skipped", observation, "missing_mob_id")
        return
    end

    local dimensions = successDimensions(observation)
    if table.getn(dimensions) == 0 then
        incrementLast("success_skipped", observation, "no_authoritative_dimension")
        return
    end

    diagnostics.successesSeen = diagnostics.successesSeen + 1

    local factsOK, facts = loadFactMap(mobID)
    if not factsOK then
        diagnostics.storageErrors = diagnostics.storageErrors + 1
        incrementLast("storage_error", observation, facts)
        return
    end

    local writable = {}
    local i
    for i = 1, table.getn(dimensions) do
        local dimension = dimensions[i]
        local fact = facts[dimension]
        if fact and tostring(fact.verdict) == "immune" then
            -- Revocation/dynamic-suspicion semantics are Slice 5. Preserve the
            -- contradiction for that reducer rather than mutating it here.
            diagnostics.deferredImmuneContradictions =
                diagnostics.deferredImmuneContradictions + 1
        else
            table.insert(writable, dimension)
        end
    end

    if table.getn(writable) == 0 then
        incrementLast("success_deferred", observation, "immune_fact_contradiction")
        return
    end

    local eliminated = queryCandidateCount(mobID, writable)
    local statements = mobStatements(mobID, observation.targetName)
    if not statements then
        diagnostics.storageErrors = diagnostics.storageErrors + 1
        incrementLast("storage_error", observation, "invalid_mob_metadata")
        return
    end

    local mobSQL = quoteInteger(mobID, 1, false)
    local spellSQL = quoteInteger(validSpellID(observation.spellID), 1, true)
    local sourceSQL = quoteText("authoritative_" .. tostring(observation.successKind or "success"), false)
    local eventSQL = quoteText(tostring(observation.event or observation.outcome or "success"), false)

    for i = 1, table.getn(writable) do
        local dimensionSQL = quoteText(writable[i], false)
        table.insert(statements,
            "INSERT OR IGNORE INTO facts " ..
            "(mob_id, dimension, verdict, dynamic_suspected, proof_source, proof_spell_id, proof_event) " ..
            "VALUES (" .. mobSQL .. ", " .. dimensionSQL ..
            ", 'vulnerable', 0, " .. sourceSQL .. ", " .. spellSQL .. ", " .. eventSQL .. ");")
        table.insert(statements,
            "UPDATE facts SET proof_source = " .. sourceSQL ..
            ", proof_spell_id = " .. spellSQL ..
            ", proof_event = " .. eventSQL ..
            " WHERE mob_id = " .. mobSQL ..
            " AND dimension = " .. dimensionSQL ..
            " AND verdict = 'vulnerable';")
        table.insert(statements,
            "DELETE FROM hypothesis_candidates WHERE dimension = " .. dimensionSQL ..
            " AND hypothesis_id IN (SELECT hypothesis_id FROM hypotheses WHERE mob_id = " ..
            mobSQL .. ");")
    end

    table.insert(statements,
        "DELETE FROM hypotheses WHERE mob_id = " .. mobSQL ..
        " AND NOT EXISTS (SELECT 1 FROM hypothesis_candidates c " ..
        "WHERE c.hypothesis_id = hypotheses.hypothesis_id);")

    local ok, err = executeTransaction(statements)
    if not ok then
        diagnostics.storageErrors = diagnostics.storageErrors + 1
        incrementLast("storage_error", observation, err)
        return
    end

    diagnostics.vulnerabilitiesRecorded =
        diagnostics.vulnerabilitiesRecorded + table.getn(writable)
    diagnostics.vulnerableCandidatesEliminated =
        diagnostics.vulnerableCandidatesEliminated + eliminated
    incrementLast("vulnerable", observation, table.concat(sortedCopy(writable), ","))
end

local function createHypothesis(observation)
    local mobID = validMobID(observation.targetMobID)
    if not mobID then
        diagnostics.missingIdentity = diagnostics.missingIdentity + 1
        incrementLast("hypothesis_skipped", observation, "missing_mob_id")
        return
    end

    local candidates = hypothesisCandidates(observation)
    if table.getn(candidates) == 0 then
        diagnostics.ambiguousUnsupported = diagnostics.ambiguousUnsupported + 1
        incrementLast("hypothesis_skipped", observation, "unverified_or_unclassified_failure_path")
        return
    end

    local blocked, explanation = hasApplicableTransientExplanation(observation, candidates)
    if blocked then
        diagnostics.hypothesesBlockedTransient =
            diagnostics.hypothesesBlockedTransient + 1
        incrementLast(
            "hypothesis_blocked",
            observation,
            explanation and explanation.source or "transient"
        )
        return
    end

    local factsOK, facts = loadFactMap(mobID)
    if not factsOK then
        diagnostics.storageErrors = diagnostics.storageErrors + 1
        incrementLast("storage_error", observation, facts)
        return
    end

    local remaining = {}
    local i
    for i = 1, table.getn(candidates) do
        local dimension = candidates[i]
        local fact = facts[dimension]
        if not fact or tostring(fact.verdict) ~= "vulnerable" then
            table.insert(remaining, dimension)
        end
    end

    if table.getn(remaining) == 0 then
        diagnostics.hypothesesDiscardedKnownVulnerable =
            diagnostics.hypothesesDiscardedKnownVulnerable + 1
        incrementLast("hypothesis_discarded", observation, "all_candidates_vulnerable")
        return
    end

    local signature = candidateSignature(remaining)
    local existing = Knowledge.GetHypotheses(mobID)
    for i = 1, table.getn(existing) do
        if candidateSignature(existing[i].candidates) == signature then
            diagnostics.hypothesesDeduped = diagnostics.hypothesesDeduped + 1
            incrementLast("hypothesis_deduped", observation, signature)
            return
        end
    end

    local statements = mobStatements(mobID, observation.targetName)
    if not statements then
        diagnostics.storageErrors = diagnostics.storageErrors + 1
        incrementLast("storage_error", observation, "invalid_mob_metadata")
        return
    end

    local mobSQL = quoteInteger(mobID, 1, false)
    local spellSQL = quoteInteger(validSpellID(observation.spellID), 1, true)
    local sourceSQL = quoteText(
        "ambiguous_" .. tostring(observation.failurePath or "unknown"),
        false
    )
    local proofEvent = tostring(observation.event or "immune")
    if observation.immuneVariant then
        proofEvent = proofEvent .. ":" .. tostring(observation.immuneVariant)
    end
    local eventSQL = quoteText(proofEvent, false)

    table.insert(statements,
        "INSERT INTO hypotheses (mob_id, proof_source, proof_spell_id, proof_event) " ..
        "VALUES (" .. mobSQL .. ", " .. sourceSQL .. ", " .. spellSQL .. ", " ..
        eventSQL .. ");")

    for i = 1, table.getn(remaining) do
        local dimensionSQL = quoteText(remaining[i], false)
        table.insert(statements,
            "INSERT INTO hypothesis_candidates (hypothesis_id, dimension) " ..
            "SELECT MAX(hypothesis_id), " .. dimensionSQL .. " FROM hypotheses;")
    end

    local ok, err = executeTransaction(statements)
    if not ok then
        diagnostics.storageErrors = diagnostics.storageErrors + 1
        incrementLast("storage_error", observation, err)
        return
    end

    diagnostics.hypothesesCreated = diagnostics.hypothesesCreated + 1
    incrementLast("hypothesis_created", observation, signature)
end

function Knowledge.ProcessObservation(observation)
    if type(observation) ~= "table" then return end
    diagnostics.observationsSeen = diagnostics.observationsSeen + 1

    if not storageReady() then
        diagnostics.storageUnavailable = diagnostics.storageUnavailable + 1
        incrementLast("storage_unavailable", observation, "not_ready")
        return
    end

    if observation.evidence == Pipeline.EVIDENCE.AUTHORITATIVE_SUCCESS
        and observation.authoritative then
        recordVulnerability(observation)
        return
    end

    if observation.evidence == Pipeline.EVIDENCE.AMBIGUOUS_IMMUNE then
        createHypothesis(observation)
    end
end

function Knowledge.GetDiagnostics()
    return {
        observationsSeen = diagnostics.observationsSeen,
        successesSeen = diagnostics.successesSeen,
        vulnerabilitiesRecorded = diagnostics.vulnerabilitiesRecorded,
        vulnerableCandidatesEliminated = diagnostics.vulnerableCandidatesEliminated,
        hypothesesCreated = diagnostics.hypothesesCreated,
        hypothesesDeduped = diagnostics.hypothesesDeduped,
        hypothesesDiscardedKnownVulnerable = diagnostics.hypothesesDiscardedKnownVulnerable,
        hypothesesBlockedTransient = diagnostics.hypothesesBlockedTransient,
        ambiguousUnsupported = diagnostics.ambiguousUnsupported,
        missingIdentity = diagnostics.missingIdentity,
        storageUnavailable = diagnostics.storageUnavailable,
        storageErrors = diagnostics.storageErrors,
        deferredImmuneContradictions = diagnostics.deferredImmuneContradictions,
        last = diagnostics.last,
    }
end

function Knowledge.GetCandidatesForObservation(observation)
    return sortedCopy(hypothesisCandidates(observation))
end

function Knowledge.GetSuccessDimensions(observation)
    return sortedCopy(successDimensions(observation))
end

if Pipeline and Pipeline.RegisterListener then
    Pipeline.RegisterListener(Knowledge.ProcessObservation)
end

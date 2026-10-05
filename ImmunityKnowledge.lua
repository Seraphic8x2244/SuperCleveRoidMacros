local _G = _G or getfenv(0)
local CleveRoids = _G.CleveRoids or {}
_G.CleveRoids = CleveRoids

-- Slice 7 production knowledge backend with centralized learning diagnostics.
--
-- This module consumes normalized observations and persists:
--   * authoritative per-dimension vulnerability facts;
--   * unresolved ambiguous immunity hypotheses with linked candidates;
--   * confirmed permanent immunity when exactly one valid permanent cause remains;
--   * revocation of a confirmed permanent fact on authoritative success; and
--   * an independent dynamic/conditional-immunity suspicion flag after revocation.
--
-- Production queries now consume these facts. Broad-immunity promotion and
-- Slice 7 UI/SCT diagnostics remain deferred.
local Pipeline = CleveRoids.ImmunityObservations
local Storage = CleveRoids.ImmunityStorage
local Transient = CleveRoids.ImmunityTransient

local Knowledge = CleveRoids.ImmunityKnowledge or {}
CleveRoids.ImmunityKnowledge = Knowledge

-- Presence of this module is the production cutover gate. It deliberately does
-- not depend on storage readiness: HearthDB is required, and an unavailable
-- database must not silently reactivate the legacy SavedVariables learner.
Knowledge.ACTIVE = true

function Knowledge.IsActive()
    return Knowledge.ACTIVE == true
end

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

-- Broad facts are reserved/queryable by the production model, but the bounded
-- Slice 6 learner still never manufactures broad-immunity candidates or promotes them.
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
    permanentConfirmations = 0,
    permanentRevocations = 0,
    dynamicSuspicionsSet = 0,
    hypothesesBlockedDynamic = 0,
    hypothesesResolvedKnownImmune = 0,
    hypothesesDiscardedDynamic = 0,
    knownVulnerableFastPaths = 0,
    last = nil,
}

local transitionListeners = {}

local function notifyKnowledgeChanged()
    if CleveRoids.NotifyImmunityDataChanged then
        CleveRoids.NotifyImmunityDataChanged()
    end
end

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

function Knowledge.RegisterTransitionListener(listener)
    if type(listener) ~= "function" then return false end
    local i
    for i = 1, table.getn(transitionListeners) do
        if transitionListeners[i] == listener then
            return true
        end
    end
    table.insert(transitionListeners, listener)
    return true
end

function Knowledge.UnregisterTransitionListener(listener)
    local i
    for i = table.getn(transitionListeners), 1, -1 do
        if transitionListeners[i] == listener then
            table.remove(transitionListeners, i)
        end
    end
end

local function emitTransition(state, observation, dimensions, detail)
    if table.getn(transitionListeners) == 0 then return end

    local transition = {
        state = state,
        sequence = observation and observation.sequence or nil,
        event = observation and observation.event or nil,
        mobID = validMobID(observation and observation.targetMobID or nil),
        targetName = observation and observation.targetName or nil,
        spellID = validSpellID(observation and observation.spellID or nil),
        dimensions = sortedCopy(dimensions or {}),
        reason = detail and detail.reason or nil,
        hypothesisID = detail and detail.hypothesisID or nil,
        proofSource = detail and detail.proofSource or nil,
        proofSpellID = detail and validSpellID(detail.proofSpellID) or nil,
        proofEvent = detail and detail.proofEvent or nil,
    }

    local i
    for i = 1, table.getn(transitionListeners) do
        pcall(transitionListeners[i], transition)
    end
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

        -- An unrecognized spell-level mechanic or Dispel family is still a real
        -- whole-spell alternative even though Slice 4 has no durable dimension
        -- for it. Abstain instead of silently dropping that cause.
        if profile.spellMechanic and profile.spellMechanic > 0
            and not profile.spellMechanicDimension then
            return result
        end
        if profile.dispelType and profile.dispelType > 0
            and not profile.dispelDimension then
            return result
        end
        if not profile.school or not CANDIDATE_DIMENSIONS[profile.school] then
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

-- Diagnostic read seam for the immunity screen. This exposes compact durable
-- conclusions only; raw observations remain deliberately unpersisted.
function Knowledge.GetFacts(mobID)
    mobID = validMobID(mobID)
    if not mobID or not storageReady() then return {} end

    local mobSQL = quoteInteger(mobID, 1, false)
    if not mobSQL then return {} end

    local ok, rows = Storage.Query(
        "SELECT dimension, verdict, dynamic_suspected, proof_source, " ..
        "proof_spell_id, proof_event FROM facts WHERE mob_id = " .. mobSQL ..
        " ORDER BY dimension"
    )
    if not ok then return {} end

    local result = {}
    local i
    for i = 1, table.getn(rows) do
        local row = rows[i]
        table.insert(result, {
            mobID = mobID,
            dimension = row.dimension and tostring(row.dimension) or nil,
            verdict = row.verdict and tostring(row.verdict) or nil,
            dynamicSuspected = tonumber(row.dynamic_suspected) == 1,
            proofSource = row.proof_source,
            proofSpellID = tonumber(row.proof_spell_id),
            proofEvent = row.proof_event,
        })
    end
    return result
end

-- Production/UI read seam for confirmed permanent facts. Optional dimension
-- narrows the result without changing the inference model.
function Knowledge.GetConfirmedImmunities(dimension)
    if not storageReady() then return {} end
    if dimension ~= nil and not FACT_DIMENSIONS[dimension] then return {} end

    local where = " WHERE f.verdict = 'immune'"
    if dimension ~= nil then
        local dimensionSQL = quoteText(dimension, false)
        if not dimensionSQL then return {} end
        where = where .. " AND f.dimension = " .. dimensionSQL
    end

    local ok, rows = Storage.Query(
        "SELECT f.mob_id, m.last_name AS name, f.dimension, f.dynamic_suspected, " ..
        "f.proof_source, f.proof_spell_id, f.proof_event " ..
        "FROM facts f LEFT JOIN mobs m ON m.mob_id = f.mob_id" ..
        where ..
        " ORDER BY f.dimension, m.last_name, f.mob_id"
    )
    if not ok then return {} end

    local result = {}
    local i
    for i = 1, table.getn(rows) do
        local row = rows[i]
        table.insert(result, {
            mobID = tonumber(row.mob_id),
            name = row.name and tostring(row.name) or nil,
            dimension = row.dimension and tostring(row.dimension) or nil,
            verdict = "immune",
            dynamicSuspected = tonumber(row.dynamic_suspected) == 1,
            proofSource = row.proof_source,
            proofSpellID = tonumber(row.proof_spell_id),
            proofEvent = row.proof_event,
        })
    end
    return result
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


local function factVerdict(fact)
    if not fact or fact.verdict == nil then return nil end
    return tostring(fact.verdict)
end

local function factDynamicSuspected(fact)
    return fact and tonumber(fact.dynamic_suspected) == 1
end

local function listSet(list)
    local result = {}
    local i
    for i = 1, table.getn(list or {}) do
        result[list[i]] = true
    end
    return result
end

local function sortedIntegerList(set)
    local result = {}
    for value, present in pairs(set or {}) do
        local number = tonumber(value)
        if present and number and number > 0 and number == math.floor(number) then
            table.insert(result, number)
        end
    end
    table.sort(result)
    return result
end

local function sqlIntegerList(values)
    local result = {}
    local i
    for i = 1, table.getn(values or {}) do
        local value = quoteInteger(values[i], 1, false)
        if value then table.insert(result, value) end
    end
    if table.getn(result) == 0 then return nil end
    return table.concat(result, ",")
end

local function firstDynamicCandidate(facts, candidates)
    local i
    for i = 1, table.getn(candidates or {}) do
        local dimension = candidates[i]
        if factDynamicSuspected(facts[dimension]) then
            return dimension
        end
    end
    return nil
end

local function firstImmuneCandidate(facts, candidates)
    local i
    for i = 1, table.getn(candidates or {}) do
        local dimension = candidates[i]
        if factVerdict(facts[dimension]) == "immune" then
            return dimension
        end
    end
    return nil
end

local function hypothesisIDsContaining(hypotheses, dimension)
    local ids = {}
    local i, j
    for i = 1, table.getn(hypotheses or {}) do
        local hypothesis = hypotheses[i]
        for j = 1, table.getn(hypothesis.candidates or {}) do
            if hypothesis.candidates[j] == dimension then
                ids[hypothesis.hypothesisID] = true
                break
            end
        end
    end
    return sortedIntegerList(ids)
end

local function appendHypothesisDeletes(statements, ids)
    local idSQL = sqlIntegerList(ids)
    if not idSQL then return end
    table.insert(statements,
        "DELETE FROM hypothesis_candidates WHERE hypothesis_id IN (" ..
        idSQL .. ");")
    table.insert(statements,
        "DELETE FROM hypotheses WHERE hypothesis_id IN (" .. idSQL .. ");")
end

local function hypothesisProofSQL(hypothesis)
    local sourceSQL = quoteText(hypothesis and hypothesis.proofSource or nil, true)
    local spellSQL = quoteInteger(
        validSpellID(hypothesis and hypothesis.proofSpellID or nil),
        1,
        true
    )
    local eventSQL = quoteText(hypothesis and hypothesis.proofEvent or nil, true)
    return sourceSQL, spellSQL, eventSQL
end

local function appendImmuneFact(statements, mobSQL, dimension, hypothesis)
    local dimensionSQL = quoteText(dimension, false)
    local sourceSQL, spellSQL, eventSQL = hypothesisProofSQL(hypothesis)
    if not dimensionSQL or not sourceSQL or not spellSQL or not eventSQL then
        return false
    end

    table.insert(statements,
        "INSERT OR IGNORE INTO facts " ..
        "(mob_id, dimension, verdict, dynamic_suspected, proof_source, proof_spell_id, proof_event) " ..
        "VALUES (" .. mobSQL .. ", " .. dimensionSQL ..
        ", 'immune', 0, " .. sourceSQL .. ", " .. spellSQL .. ", " ..
        eventSQL .. ");")
    return true
end

local function planAfterAuthoritativeSuccess(hypotheses, facts, successSet, revokedSet)
    local survivors = {}
    local deleteIDs = {}
    local confirmations = {}
    local confirmationByDimension = {}
    local dynamicDiscardCount = 0
    local i, j

    for i = 1, table.getn(hypotheses or {}) do
        local hypothesis = hypotheses[i]
        local remaining = {}
        local blockedDynamic = false
        local explainedKnownImmune = false

        for j = 1, table.getn(hypothesis.candidates or {}) do
            local dimension = hypothesis.candidates[j]
            local fact = facts[dimension]

            if revokedSet[dimension] or factDynamicSuspected(fact) then
                blockedDynamic = true
            elseif factVerdict(fact) == "immune" and not successSet[dimension] then
                explainedKnownImmune = true
            elseif not successSet[dimension] and factVerdict(fact) ~= "vulnerable" then
                table.insert(remaining, dimension)
            end
        end

        if blockedDynamic then
            if not deleteIDs[hypothesis.hypothesisID] then
                dynamicDiscardCount = dynamicDiscardCount + 1
            end
            deleteIDs[hypothesis.hypothesisID] = true
        elseif explainedKnownImmune or table.getn(remaining) == 0 then
            deleteIDs[hypothesis.hypothesisID] = true
        else
            survivors[hypothesis.hypothesisID] = {
                hypothesis = hypothesis,
                remaining = remaining,
            }
        end
    end

    for i = 1, table.getn(hypotheses or {}) do
        local hypothesis = hypotheses[i]
        local survivor = survivors[hypothesis.hypothesisID]
        if survivor and table.getn(survivor.remaining) == 1 then
            local dimension = survivor.remaining[1]
            if not confirmationByDimension[dimension] then
                confirmationByDimension[dimension] = hypothesis
                table.insert(confirmations, {
                    dimension = dimension,
                    hypothesis = hypothesis,
                })
            end
        end
    end

    for id, survivor in pairs(survivors) do
        for j = 1, table.getn(survivor.remaining) do
            if confirmationByDimension[survivor.remaining[j]] then
                deleteIDs[id] = true
                break
            end
        end
    end

    table.sort(confirmations, function(a, b)
        return a.dimension < b.dimension
    end)

    return confirmations, sortedIntegerList(deleteIDs), dynamicDiscardCount
end

local function confirmSingleCandidate(observation, mobID, dimension, existing)
    local statements = mobStatements(mobID, observation.targetName)
    if not statements then
        return false, "invalid_mob_metadata"
    end

    local mobSQL = quoteInteger(mobID, 1, false)
    local sourceSQL = quoteText(
        "ambiguous_" .. tostring(observation.failurePath or "unknown"),
        false
    )
    local spellSQL = quoteInteger(validSpellID(observation.spellID), 1, true)
    local proofEvent = tostring(observation.event or "immune")
    if observation.immuneVariant then
        proofEvent = proofEvent .. ":" .. tostring(observation.immuneVariant)
    end
    local eventSQL = quoteText(proofEvent, false)
    local dimensionSQL = quoteText(dimension, false)
    if not mobSQL or not sourceSQL or not spellSQL or not eventSQL or not dimensionSQL then
        return false, "invalid_confirmation_provenance"
    end

    table.insert(statements,
        "INSERT OR IGNORE INTO facts " ..
        "(mob_id, dimension, verdict, dynamic_suspected, proof_source, proof_spell_id, proof_event) " ..
        "VALUES (" .. mobSQL .. ", " .. dimensionSQL ..
        ", 'immune', 0, " .. sourceSQL .. ", " .. spellSQL .. ", " ..
        eventSQL .. ");")

    appendHypothesisDeletes(statements, hypothesisIDsContaining(existing, dimension))
    table.insert(statements,
        "DELETE FROM hypotheses WHERE mob_id = " .. mobSQL ..
        " AND NOT EXISTS (SELECT 1 FROM hypothesis_candidates c " ..
        "WHERE c.hypothesis_id = hypotheses.hypothesis_id);")

    local ok, err = executeTransaction(statements)
    if ok then
        notifyKnowledgeChanged()
    end
    return ok, err
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

    -- A repeated authoritative success for dimensions already known
    -- vulnerable cannot change any durable conclusion. The first success that
    -- established vulnerability already removed those candidates from every
    -- hypothesis, so skip the hypothesis query and write transaction entirely.
    local allKnownVulnerable = true
    local fastIndex
    for fastIndex = 1, table.getn(dimensions) do
        if factVerdict(facts[dimensions[fastIndex]]) ~= "vulnerable" then
            allKnownVulnerable = false
            break
        end
    end
    if allKnownVulnerable then
        diagnostics.knownVulnerableFastPaths =
            diagnostics.knownVulnerableFastPaths + 1
        incrementLast(
            "success_known_vulnerable",
            observation,
            table.concat(sortedCopy(dimensions), ",")
        )
        return
    end

    local hypotheses = Knowledge.GetHypotheses(mobID)
    local successSet = listSet(dimensions)
    local revokedSet = {}
    local revocationCount = 0
    local dynamicSetCount = 0
    local i

    for i = 1, table.getn(dimensions) do
        local dimension = dimensions[i]
        local fact = facts[dimension]
        if factVerdict(fact) == "immune" then
            revokedSet[dimension] = true
            revocationCount = revocationCount + 1
            if not factDynamicSuspected(fact) then
                dynamicSetCount = dynamicSetCount + 1
            end
        end
    end

    local eliminatedDimensions = {}
    local eliminatedSet = {}
    local revokedDimensions = {}
    local hypothesisIndex, candidateIndex
    for hypothesisIndex = 1, table.getn(hypotheses) do
        local hypothesis = hypotheses[hypothesisIndex]
        for candidateIndex = 1, table.getn(hypothesis.candidates or {}) do
            local candidate = hypothesis.candidates[candidateIndex]
            if successSet[candidate] and not revokedSet[candidate] then
                eliminatedSet[candidate] = true
            end
        end
    end
    for candidate in pairs(eliminatedSet) do
        table.insert(eliminatedDimensions, candidate)
    end
    for dimension in pairs(revokedSet) do
        table.insert(revokedDimensions, dimension)
    end
    table.sort(eliminatedDimensions)
    table.sort(revokedDimensions)

    local confirmations, deleteIDs, dynamicDiscardCount =
        planAfterAuthoritativeSuccess(hypotheses, facts, successSet, revokedSet)

    local eliminated = queryCandidateCount(mobID, dimensions)
    local statements = mobStatements(mobID, observation.targetName)
    if not statements then
        diagnostics.storageErrors = diagnostics.storageErrors + 1
        incrementLast("storage_error", observation, "invalid_mob_metadata")
        return
    end

    local mobSQL = quoteInteger(mobID, 1, false)
    local spellSQL = quoteInteger(validSpellID(observation.spellID), 1, true)
    local sourceSQL = quoteText(
        "authoritative_" .. tostring(observation.successKind or "success"),
        false
    )
    local eventSQL = quoteText(
        tostring(observation.event or observation.outcome or "success"),
        false
    )
    if not mobSQL or not spellSQL or not sourceSQL or not eventSQL then
        diagnostics.storageErrors = diagnostics.storageErrors + 1
        incrementLast("storage_error", observation, "invalid_success_provenance")
        return
    end

    for i = 1, table.getn(dimensions) do
        local dimensionSQL = quoteText(dimensions[i], false)
        if not dimensionSQL then
            diagnostics.storageErrors = diagnostics.storageErrors + 1
            incrementLast("storage_error", observation, "invalid_success_dimension")
            return
        end

        table.insert(statements,
            "INSERT OR IGNORE INTO facts " ..
            "(mob_id, dimension, verdict, dynamic_suspected, proof_source, proof_spell_id, proof_event) " ..
            "VALUES (" .. mobSQL .. ", " .. dimensionSQL ..
            ", 'vulnerable', 0, " .. sourceSQL .. ", " .. spellSQL .. ", " ..
            eventSQL .. ");")
        table.insert(statements,
            "UPDATE facts SET " ..
            "dynamic_suspected = CASE WHEN verdict = 'immune' THEN 1 " ..
            "ELSE dynamic_suspected END, " ..
            "verdict = 'vulnerable', proof_source = " .. sourceSQL ..
            ", proof_spell_id = " .. spellSQL ..
            ", proof_event = " .. eventSQL ..
            " WHERE mob_id = " .. mobSQL ..
            " AND dimension = " .. dimensionSQL .. ";")
        table.insert(statements,
            "DELETE FROM hypothesis_candidates WHERE dimension = " .. dimensionSQL ..
            " AND hypothesis_id IN (SELECT hypothesis_id FROM hypotheses WHERE mob_id = " ..
            mobSQL .. ");")
    end

    -- Clean up any pre-existing ordinary vulnerable candidates before applying
    -- the same deterministic confirmation plan. Dynamic vulnerability is not a
    -- permanent candidate, but it remains a credible conditional explanation;
    -- hypotheses containing it are discarded whole below rather than narrowed.
    table.insert(statements,
        "DELETE FROM hypothesis_candidates WHERE hypothesis_id IN " ..
        "(SELECT hypothesis_id FROM hypotheses WHERE mob_id = " .. mobSQL .. ") " ..
        "AND dimension IN (SELECT dimension FROM facts WHERE mob_id = " .. mobSQL ..
        " AND verdict = 'vulnerable' AND dynamic_suspected = 0);")

    for i = 1, table.getn(confirmations) do
        if not appendImmuneFact(
            statements,
            mobSQL,
            confirmations[i].dimension,
            confirmations[i].hypothesis
        ) then
            diagnostics.storageErrors = diagnostics.storageErrors + 1
            incrementLast("storage_error", observation, "invalid_confirmation_provenance")
            return
        end
    end

    appendHypothesisDeletes(statements, deleteIDs)
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

    notifyKnowledgeChanged()

    diagnostics.vulnerabilitiesRecorded =
        diagnostics.vulnerabilitiesRecorded + table.getn(dimensions)
    diagnostics.vulnerableCandidatesEliminated =
        diagnostics.vulnerableCandidatesEliminated + eliminated
    diagnostics.permanentRevocations =
        diagnostics.permanentRevocations + revocationCount
    diagnostics.dynamicSuspicionsSet =
        diagnostics.dynamicSuspicionsSet + dynamicSetCount
    diagnostics.permanentConfirmations =
        diagnostics.permanentConfirmations + table.getn(confirmations)
    diagnostics.hypothesesDiscardedDynamic =
        diagnostics.hypothesesDiscardedDynamic + dynamicDiscardCount

    -- Learning SCT consumes only meaningful state transitions. A routine
    -- vulnerability fact with no active candidate is intentionally silent.
    if table.getn(eliminatedDimensions) > 0 then
        emitTransition("disproved", observation, eliminatedDimensions, {
            reason = "candidate_eliminated",
        })
    end
    for i = 1, table.getn(confirmations) do
        local confirmation = confirmations[i]
        local proof = confirmation.hypothesis
        emitTransition("confirmed", observation, { confirmation.dimension }, {
            reason = "permanent_confirmed",
            hypothesisID = proof and proof.hypothesisID or nil,
            proofSource = proof and proof.proofSource or nil,
            proofSpellID = proof and proof.proofSpellID or nil,
            proofEvent = proof and proof.proofEvent or nil,
        })
    end
    if table.getn(revokedDimensions) > 0 then
        emitTransition("conditional", observation, revokedDimensions, {
            reason = "confirmed_immunity_revoked",
        })
    end

    local detail = "vulnerable=" .. table.concat(sortedCopy(dimensions), ",")
    if revocationCount > 0 then
        detail = detail .. ";revoked=" .. tostring(revocationCount)
    end
    if table.getn(confirmations) > 0 then
        local confirmed = {}
        for i = 1, table.getn(confirmations) do
            table.insert(confirmed, confirmations[i].dimension)
        end
        detail = detail .. ";confirmed=" .. table.concat(sortedCopy(confirmed), ",")
    end
    incrementLast("vulnerable", observation, detail)
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

    -- A previously confirmed immunity that was later disproved is no longer a
    -- valid permanent candidate, but its dynamic flag is positive evidence that
    -- this dimension can still explain an IMMUNE conditionally. Do not use that
    -- event to over-confirm a different permanent dimension.
    local dynamicDimension = firstDynamicCandidate(facts, candidates)
    if dynamicDimension then
        diagnostics.hypothesesBlockedDynamic =
            diagnostics.hypothesesBlockedDynamic + 1
        incrementLast("hypothesis_blocked", observation, "dynamic:" .. dynamicDimension)
        return
    end

    -- If a permanent candidate is already confirmed immune, the observation is
    -- already explained. It contributes no new ambiguity about the other
    -- dimensions.
    local immuneDimension = firstImmuneCandidate(facts, candidates)
    if immuneDimension then
        diagnostics.hypothesesResolvedKnownImmune =
            diagnostics.hypothesesResolvedKnownImmune + 1
        incrementLast("hypothesis_resolved", observation, "known_immune:" .. immuneDimension)
        return
    end

    local remaining = {}
    local i
    for i = 1, table.getn(candidates) do
        local dimension = candidates[i]
        if factVerdict(facts[dimension]) ~= "vulnerable" then
            table.insert(remaining, dimension)
        end
    end

    if table.getn(remaining) == 0 then
        diagnostics.hypothesesDiscardedKnownVulnerable =
            diagnostics.hypothesesDiscardedKnownVulnerable + 1
        incrementLast("hypothesis_discarded", observation, "all_candidates_vulnerable")
        return
    end

    local existing = Knowledge.GetHypotheses(mobID)

    if table.getn(remaining) == 1 then
        local ok, err = confirmSingleCandidate(
            observation,
            mobID,
            remaining[1],
            existing
        )
        if not ok then
            diagnostics.storageErrors = diagnostics.storageErrors + 1
            incrementLast("storage_error", observation, err)
            return
        end

        diagnostics.permanentConfirmations =
            diagnostics.permanentConfirmations + 1
        incrementLast("immune_confirmed", observation, remaining[1])
        emitTransition("confirmed", observation, { remaining[1] }, {
            reason = "permanent_confirmed",
            proofSource = "ambiguous_" .. tostring(observation.failurePath or "unknown"),
            proofSpellID = observation.spellID,
            proofEvent = observation.event,
        })
        return
    end

    local signature = candidateSignature(remaining)
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

    notifyKnowledgeChanged()
    diagnostics.hypothesesCreated = diagnostics.hypothesesCreated + 1
    incrementLast("hypothesis_created", observation, signature)
    emitTransition("candidate", observation, remaining, {
        reason = "hypothesis_created",
        proofSource = "ambiguous_" .. tostring(observation.failurePath or "unknown"),
        proofSpellID = observation.spellID,
        proofEvent = observation.event,
    })
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
        permanentConfirmations = diagnostics.permanentConfirmations,
        permanentRevocations = diagnostics.permanentRevocations,
        dynamicSuspicionsSet = diagnostics.dynamicSuspicionsSet,
        hypothesesBlockedDynamic = diagnostics.hypothesesBlockedDynamic,
        hypothesesResolvedKnownImmune = diagnostics.hypothesesResolvedKnownImmune,
        hypothesesDiscardedDynamic = diagnostics.hypothesesDiscardedDynamic,
        knownVulnerableFastPaths = diagnostics.knownVulnerableFastPaths,
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

local _G = _G or getfenv(0)
local CleveRoids = _G.CleveRoids or {}
_G.CleveRoids = CleveRoids

-- Normalized immunity evidence input seam.
--
-- This module observes and normalizes combat evidence, caches static spell
-- classification and exposes diagnostics/listener hooks. Later bounded slices
-- may consume this seam, but it does not write HearthDB, mutate the legacy
-- immunity learner, infer permanent facts, or drive UI/SCT.
local Pipeline = CleveRoids.ImmunityObservations or {}
CleveRoids.ImmunityObservations = Pipeline

Pipeline.SCHEMA_VERSION = 1

Pipeline.EVIDENCE = {
    AUTHORITATIVE_SUCCESS = "authoritative_success",
    AMBIGUOUS_IMMUNE = "ambiguous_immune",
    NEUTRAL = "neutral",
    LIFECYCLE = "lifecycle",
}

local MISS_INFO = {
    NONE = 0,
    MISS = 1,
    RESIST = 2,
    DODGE = 3,
    PARRY = 4,
    BLOCK = 5,
    EVADE = 6,
    IMMUNE = 7,
    IMMUNE2 = 8,
    DEFLECT = 9,
    ABSORB = 10,
    REFLECT = 11,
}

local MISS_NAMES = {
    [0] = "none",
    [1] = "miss",
    [2] = "resist",
    [3] = "dodge",
    [4] = "parry",
    [5] = "block",
    [6] = "evade",
    [7] = "immune",
    [8] = "immune2",
    [9] = "deflect",
    [10] = "absorb",
    [11] = "reflect",
}

local SCHOOL_NAMES = {
    [0] = "physical",
    [1] = "holy",
    [2] = "fire",
    [3] = "nature",
    [4] = "frost",
    [5] = "shadow",
    [6] = "arcane",
}

-- Mechanic names are the existing SCRM permanent-immunity vocabulary. Static
-- classification may expose several dimensions; selecting/eliminating candidates
-- belongs to later slices.
local MECHANIC_TO_DIMENSION = {
    [1] = "charm",
    [2] = "disorient",
    [5] = "fear",
    [7] = "root",
    [9] = "silence",
    [10] = "sleep",
    [11] = "snare",
    [12] = "stun",
    [13] = "freeze",
    [14] = "knockout",
    [15] = "bleed",
    [17] = "polymorph",
    [18] = "banish",
    [20] = "shackle",
    [24] = "horror",
    [27] = "daze",
}

-- Aura-name fallback is only used when no recognized explicit spell/effect
-- mechanic exists. This prevents a generic MOD_STUN aura from misclassifying a
-- spell whose explicit mechanic says Sleep/Knockout/Banish.
local AURA_NAME_TO_DIMENSION = {
    [1] = "charm",
    [2] = "charm",
    [5] = "polymorph",
    [7] = "fear",
    [11] = "root",
    [12] = "stun",
    [27] = "silence",
    [31] = "charm",
    [33] = "snare",
}

-- Dispel-family immunity is independent from spell school. "dispel_magic" is
-- an internal learning dimension; it is intentionally not the broad "spell"
-- immunity dimension used by production queries.
local DISPEL_TO_DIMENSION = {
    [1] = "dispel_magic",
    [2] = "curse",
    [3] = "disease",
    [4] = "poison",
}

local spellCache = {}
local listeners = {}
local sequence = 0

local diagnostics = {
    eventsSeen = 0,
    observationsEmitted = 0,
    listenerErrors = 0,
    spellCacheHits = 0,
    spellCacheMisses = 0,
    liveMobResolved = 0,
    unresolvedTargetIdentity = 0,
    nonCreatureTargets = 0,
    byEvent = {},
    byKind = {},
    byEvidence = {},
    last = nil,
}

local function normalizeGUID(guid)
    if guid == nil then return nil end
    if CleveRoids.NormalizeGUID then
        return CleveRoids.NormalizeGUID(guid)
    end
    return tostring(guid)
end

local function increment(map, key)
    if not key then return end
    map[key] = (map[key] or 0) + 1
end

local function copyCounts(source)
    local result = {}
    for key, value in pairs(source) do
        result[key] = value
    end
    return result
end

local function countKeys(source)
    local count = 0
    for _ in pairs(source) do
        count = count + 1
    end
    return count
end

local function addUnique(list, seen, value)
    if value and not seen[value] then
        seen[value] = true
        table.insert(list, value)
    end
end

local function copyEffect(raw, mechanic)
    if not raw and mechanic == nil then return nil end
    raw = raw or {}
    return {
        effect = raw.effect or 0,
        auraName = raw.auraName or 0,
        mechanic = mechanic or 0,
        basePoints = raw.basePoints,
        baseDice = raw.baseDice,
        dieSides = raw.dieSides,
        pointsPerLevel = raw.pointsPerLevel,
        dicePerLevel = raw.dicePerLevel,
        miscValue = raw.miscValue,
    }
end

function Pipeline.ClearSpellCache()
    spellCache = {}
end

-- Cached, read-only-by-convention static decomposition for arbitrary spell IDs.
-- Runtime success/failure is never inferred from this table; it only describes
-- dimensions a later reducer may need to reason about.
function Pipeline.GetSpellProfile(spellID)
    spellID = tonumber(spellID)
    if not spellID or spellID <= 0 then return nil end

    local cached = spellCache[spellID]
    if cached then
        diagnostics.spellCacheHits = diagnostics.spellCacheHits + 1
        return cached
    end

    diagnostics.spellCacheMisses = diagnostics.spellCacheMisses + 1

    local API = CleveRoids.ClassicAPI
    if not API then return nil end

    local schoolID, schoolName = API.GetSpellSchoolByID(spellID)
    local spellMechanic, spellMechanicName = API.GetSpellMechanicByID(spellID)
    local effectMechanics = API.GetSpellEffectMechanics(spellID)
    local rawEffects = API.GetSpellEffectInfo(spellID)
    local dispelType = API.GetSpellDispelType(spellID)

    if schoolName then
        schoolName = string.lower(tostring(schoolName))
    elseif schoolID ~= nil then
        schoolName = SCHOOL_NAMES[schoolID]
    end

    local profile = {
        spellID = spellID,
        name = C_Spell.GetSpellName(spellID),
        schoolID = schoolID,
        school = schoolName,
        spellMechanic = spellMechanic or 0,
        spellMechanicName = spellMechanicName,
        spellMechanicDimension = nil,
        dispelType = dispelType or 0,
        dispelDimension = DISPEL_TO_DIMENSION[dispelType],
        effects = {},
        auraTypes = {},
        mechanicDimensions = {},
        hasAura = false,
    }

    local auraSeen = {}
    local dimensionSeen = {}
    local explicitMechanicDimension = false

    local spellDimension = spellMechanic and MECHANIC_TO_DIMENSION[spellMechanic] or nil
    profile.spellMechanicDimension = spellDimension
    if spellDimension then
        addUnique(profile.mechanicDimensions, dimensionSeen, spellDimension)
        explicitMechanicDimension = true
    end

    for i = 1, 3 do
        local raw = rawEffects and rawEffects[i] or nil
        local effectMechanic = effectMechanics and effectMechanics[i] or 0
        local effect = copyEffect(raw, effectMechanic)
        if effect then
            profile.effects[i] = effect
            if effect.auraName and effect.auraName > 0 then
                profile.hasAura = true
                addUnique(profile.auraTypes, auraSeen, effect.auraName)
            end
        end

        local dimension = effectMechanic and MECHANIC_TO_DIMENSION[effectMechanic] or nil
        if effect then
            effect.mechanicDimension = dimension
        end
        if dimension then
            addUnique(profile.mechanicDimensions, dimensionSeen, dimension)
            explicitMechanicDimension = true
        end
    end

    -- Preserve the existing combined-profile fallback rule while also exposing
    -- a per-effect dimension for the Slice 4 failure-path reducer.
    for i = 1, 3 do
        local effect = profile.effects[i]
        if effect and not effect.mechanicDimension then
            effect.mechanicDimension = AURA_NAME_TO_DIMENSION[effect.auraName]
        end
        if not explicitMechanicDimension and effect and effect.mechanicDimension then
            addUnique(profile.mechanicDimensions, dimensionSeen, effect.mechanicDimension)
        end
    end

    spellCache[spellID] = profile
    return profile
end

local CORE_ADAPTERS = {}

-- Portable is deliberately the default. It preserves raw Nampower meaning
-- without claiming server-side semantics that have not been verified for the
-- active core.
CORE_ADAPTERS.portable = {
    interpretImmune = function(variant)
        if variant == "immune2" then
            return "raw_immune2", nil
        end
        return "raw_immune", nil
    end,
}

-- vMaNGOS-specific descriptions belong here, not in the evidence reducer.
-- They are diagnostic semantics only in Slice 2.
CORE_ADAPTERS.vmangos = {
    interpretImmune = function(variant)
        if variant == "immune2" then
            return "effect_mask_zero", "effect_mask_zero"
        end
        return "generic_whole_spell_immune", "whole_spell"
    end,
}

-- Octo/Turtle raw semantics remain deliberately unclaimed until the Slice 8
-- runtime matrix. The adapter exists now so later verification does not leak
-- core checks into the common pipeline.
CORE_ADAPTERS.octowow = {
    interpretImmune = function(variant)
        if variant == "immune2" then
            return "raw_immune2_unverified", nil
        end
        return "raw_immune_unverified", nil
    end,
}

Pipeline.coreAdapterName = Pipeline.coreAdapterName or "portable"

function Pipeline.SetCoreAdapter(name)
    if not CORE_ADAPTERS[name] then
        return false
    end
    Pipeline.coreAdapterName = name
    return true
end

function Pipeline.GetCoreAdapter()
    return Pipeline.coreAdapterName
end

local function interpretMiss(missInfo)
    local result = {
        outcome = MISS_NAMES[missInfo] or "unknown",
        evidence = Pipeline.EVIDENCE.NEUTRAL,
        authoritative = false,
        immuneVariant = nil,
        coreMeaning = nil,
        failurePath = nil,
    }

    if missInfo == MISS_INFO.IMMUNE or missInfo == MISS_INFO.IMMUNE2 then
        local variant = missInfo == MISS_INFO.IMMUNE2 and "immune2" or "immune"
        local adapter = CORE_ADAPTERS[Pipeline.coreAdapterName] or CORE_ADAPTERS.portable
        result.outcome = "immune"
        result.evidence = Pipeline.EVIDENCE.AMBIGUOUS_IMMUNE
        result.immuneVariant = variant
        result.coreMeaning, result.failurePath = adapter.interpretImmune(variant)
    end

    return result
end

local function resolveTarget(observation, guid)
    guid = normalizeGUID(guid)
    observation.targetGUID = guid
    if not guid then
        observation.targetIdentity = "missing_guid"
        diagnostics.unresolvedTargetIdentity = diagnostics.unresolvedTargetIdentity + 1
        return
    end

    local API = CleveRoids.ClassicAPI
    local mobID, unit, status = API.ResolveLiveCreatureID(guid)
    observation.targetMobID = mobID
    observation.targetUnit = unit
    observation.targetIdentity = status

    if unit then
        observation.targetName = UnitName(unit)
    end

    if mobID then
        diagnostics.liveMobResolved = diagnostics.liveMobResolved + 1
    elseif status == "not_creature" then
        diagnostics.nonCreatureTargets = diagnostics.nonCreatureTargets + 1
    else
        diagnostics.unresolvedTargetIdentity = diagnostics.unresolvedTargetIdentity + 1
    end
end

local function newObservation(eventName, scope, kind)
    sequence = sequence + 1
    return {
        schemaVersion = Pipeline.SCHEMA_VERSION,
        sequence = sequence,
        timestamp = GetTime(),
        source = "nampower",
        event = eventName,
        scope = scope,
        kind = kind,
        coreAdapter = Pipeline.coreAdapterName,
    }
end

local function rememberDiagnosticSummary(observation)
    diagnostics.last = {
        sequence = observation.sequence,
        event = observation.event,
        kind = observation.kind,
        evidence = observation.evidence,
        outcome = observation.outcome,
        targetGUID = observation.targetGUID,
        targetMobID = observation.targetMobID,
        targetIdentity = observation.targetIdentity,
        spellID = observation.spellID,
        coreAdapter = observation.coreAdapter,
    }
end

local function emit(observation)
    diagnostics.observationsEmitted = diagnostics.observationsEmitted + 1
    increment(diagnostics.byKind, observation.kind)
    increment(diagnostics.byEvidence, observation.evidence)
    rememberDiagnosticSummary(observation)

    for i = 1, table.getn(listeners) do
        local callback = listeners[i]
        local ok = pcall(callback, observation)
        if not ok then
            diagnostics.listenerErrors = diagnostics.listenerErrors + 1
        end
    end

    return observation
end

function Pipeline.RegisterListener(callback)
    if type(callback) ~= "function" then return false end
    for i = 1, table.getn(listeners) do
        if listeners[i] == callback then return true end
    end
    table.insert(listeners, callback)
    return true
end

function Pipeline.UnregisterListener(callback)
    for i = table.getn(listeners), 1, -1 do
        if listeners[i] == callback then
            table.remove(listeners, i)
            return true
        end
    end
    return false
end

local function scopeForEvent(eventName)
    if string.find(eventName, "_SELF$") then return "self" end
    if string.find(eventName, "_OTHER$") then return "other" end
    return "unit"
end

local function normalizeMiss(eventName, casterGUID, targetGUID, spellID, missInfo)
    spellID = tonumber(spellID)
    missInfo = tonumber(missInfo)
    if not targetGUID or not spellID or missInfo == nil then return nil end

    local interpretation = interpretMiss(missInfo)
    local observation = newObservation(eventName, scopeForEvent(eventName), "miss")
    observation.casterGUID = normalizeGUID(casterGUID)
    observation.spellID = spellID
    observation.spell = Pipeline.GetSpellProfile(spellID)
    observation.missInfo = missInfo
    observation.missReason = MISS_NAMES[missInfo] or "unknown"
    observation.outcome = interpretation.outcome
    observation.evidence = interpretation.evidence
    observation.authoritative = interpretation.authoritative
    observation.immuneVariant = interpretation.immuneVariant
    observation.coreMeaning = interpretation.coreMeaning
    observation.failurePath = interpretation.failurePath
    resolveTarget(observation, targetGUID)
    return emit(observation)
end

local function normalizeDamage(eventName, targetGUID, casterGUID, spellID, amount,
                               mitigation, hitInfo, runtimeSchoolID, effectAura)
    spellID = tonumber(spellID)
    runtimeSchoolID = tonumber(runtimeSchoolID)
    if not targetGUID or not spellID then return nil end

    local observation = newObservation(eventName, scopeForEvent(eventName), "damage")
    observation.casterGUID = normalizeGUID(casterGUID)
    observation.spellID = spellID
    observation.spell = Pipeline.GetSpellProfile(spellID)
    observation.outcome = "damage_landed"
    observation.evidence = Pipeline.EVIDENCE.AUTHORITATIVE_SUCCESS
    observation.authoritative = true
    observation.successKind = "damage"
    observation.runtimeSchoolID = runtimeSchoolID
    observation.runtimeSchool = runtimeSchoolID ~= nil and SCHOOL_NAMES[runtimeSchoolID] or nil
    observation.amount = tonumber(amount)
    observation.mitigation = mitigation
    observation.hitInfo = tonumber(hitInfo)
    observation.effectAura = effectAura
    resolveTarget(observation, targetGUID)
    return emit(observation)
end

local function auraOperation(eventName, state)
    state = tonumber(state)
    if state == 0 then return "added" end
    if state == 1 then return "removed" end
    if state == 2 then return "modified" end
    if string.find(eventName, "_ADDED_") then return "added" end
    return "removed"
end

local function normalizeAura(eventName, targetGUID, slot, spellID, stackCount,
                            auraLevel, auraSlot, state)
    spellID = tonumber(spellID)
    if not targetGUID or not spellID then return nil end

    local kind = string.find(eventName, "^BUFF_") and "buff" or "debuff"
    local operation = auraOperation(eventName, state)
    local stacks = tonumber(stackCount)
    local present = operation == "added" or
        (operation == "modified" and (stacks == nil or stacks > 0))

    local observation = newObservation(eventName, scopeForEvent(eventName), "aura")
    observation.spellID = spellID
    observation.spell = Pipeline.GetSpellProfile(spellID)
    observation.auraKind = kind
    observation.auraOperation = operation
    observation.stackCount = stacks
    observation.auraLevel = tonumber(auraLevel)
    observation.luaSlot = tonumber(slot)
    observation.auraSlot = tonumber(auraSlot)
    observation.state = tonumber(state)
    observation.outcome = present and "aura_present" or "aura_removed"
    observation.evidence = present and Pipeline.EVIDENCE.AUTHORITATIVE_SUCCESS
        or Pipeline.EVIDENCE.NEUTRAL
    observation.authoritative = present and true or false
    observation.successKind = present and "aura" or nil

    resolveTarget(observation, targetGUID)

    -- Nampower add/modify is already authoritative presence evidence. When the
    -- live unit is available, ClassicAPI actual aura state can add source
    -- attribution and a second diagnostic confirmation. AURA_CAST_ON_* is
    -- intentionally not registered or consumed.
    if present and observation.targetUnit then
        local filter = kind == "buff" and "HELPFUL" or "HARMFUL"
        local auraData = CleveRoids.ClassicAPI.GetUnitAuraBySpellID(
            observation.targetUnit, spellID, filter
        )
        observation.classicAuraVerified = auraData and true or false
        if auraData and auraData.sourceGUID then
            observation.casterGUID = normalizeGUID(auraData.sourceGUID)
            observation.casterSource = "classicapi_aura"
        end
    end

    return emit(observation)
end

local function normalizeDeath(eventName, targetGUID)
    if not targetGUID then return nil end
    local observation = newObservation(eventName, "unit", "death")
    observation.outcome = "died"
    observation.evidence = Pipeline.EVIDENCE.LIFECYCLE
    observation.authoritative = true
    resolveTarget(observation, targetGUID)
    return emit(observation)
end

-- Explicit lifecycle seam for transient-only state. Current live producers use
-- UNIT_DIED and PLAYER_ENTERING_WORLD; adapters may also normalize a proven
-- despawn without bypassing the observation pipeline.
function Pipeline.EmitLifecycle(outcome, targetGUID, eventName, detail)
    if not outcome then return nil end
    local observation = newObservation(eventName or "IMMUNITY_LIFECYCLE", "unit", "lifecycle")
    observation.outcome = tostring(outcome)
    observation.evidence = Pipeline.EVIDENCE.LIFECYCLE
    observation.authoritative = true
    observation.lifecycleDetail = detail
    if targetGUID then
        resolveTarget(observation, targetGUID)
    end
    return emit(observation)
end

-- Public adapter seam. Live registration below is the only current producer.
-- No persistence or inference happens here.
function Pipeline.HandleNampowerEvent(eventName, a1, a2, a3, a4, a5, a6, a7, a8)
    if not eventName then return nil end

    diagnostics.eventsSeen = diagnostics.eventsSeen + 1
    increment(diagnostics.byEvent, eventName)

    if eventName == "SPELL_MISS_SELF" or eventName == "SPELL_MISS_OTHER" then
        -- casterGuid, targetGuid, spellId, missInfo
        return normalizeMiss(eventName, a1, a2, a3, a4)
    end

    if eventName == "SPELL_DAMAGE_EVENT_SELF" or eventName == "SPELL_DAMAGE_EVENT_OTHER" then
        -- targetGuid, casterGuid, spellId, amount, mitigationStr, hitInfo,
        -- runtimeSchool, effectAuraStr
        return normalizeDamage(eventName, a1, a2, a3, a4, a5, a6, a7, a8)
    end

    if string.find(eventName, "^BUFF_ADDED_") or
       string.find(eventName, "^BUFF_REMOVED_") or
       string.find(eventName, "^DEBUFF_ADDED_") or
       string.find(eventName, "^DEBUFF_REMOVED_") then
        -- guid, luaSlot, spellId, stackCount, auraLevel, rawAuraSlot, state
        return normalizeAura(eventName, a1, a2, a3, a4, a5, a6, a7)
    end

    if eventName == "UNIT_DIED" then
        return normalizeDeath(eventName, a1)
    end

    if eventName == "PLAYER_ENTERING_WORLD" then
        return Pipeline.EmitLifecycle("world_reset", nil, eventName)
    end

    return nil
end

function Pipeline.GetDiagnostics()
    return {
        schemaVersion = Pipeline.SCHEMA_VERSION,
        coreAdapter = Pipeline.coreAdapterName,
        listenerCount = table.getn(listeners),
        spellCacheEntries = countKeys(spellCache),
        eventsSeen = diagnostics.eventsSeen,
        observationsEmitted = diagnostics.observationsEmitted,
        listenerErrors = diagnostics.listenerErrors,
        spellCacheHits = diagnostics.spellCacheHits,
        spellCacheMisses = diagnostics.spellCacheMisses,
        liveMobResolved = diagnostics.liveMobResolved,
        unresolvedTargetIdentity = diagnostics.unresolvedTargetIdentity,
        nonCreatureTargets = diagnostics.nonCreatureTargets,
        byEvent = copyCounts(diagnostics.byEvent),
        byKind = copyCounts(diagnostics.byKind),
        byEvidence = copyCounts(diagnostics.byEvidence),
        last = diagnostics.last,
    }
end

function Pipeline.ResetDiagnostics()
    diagnostics.eventsSeen = 0
    diagnostics.observationsEmitted = 0
    diagnostics.listenerErrors = 0
    diagnostics.spellCacheHits = 0
    diagnostics.spellCacheMisses = 0
    diagnostics.liveMobResolved = 0
    diagnostics.unresolvedTargetIdentity = 0
    diagnostics.nonCreatureTargets = 0
    diagnostics.byEvent = {}
    diagnostics.byKind = {}
    diagnostics.byEvidence = {}
    diagnostics.last = nil
end

local EVENT_NAMES = {
    "SPELL_MISS_SELF",
    "SPELL_MISS_OTHER",
    "SPELL_DAMAGE_EVENT_SELF",
    "SPELL_DAMAGE_EVENT_OTHER",
    "BUFF_ADDED_SELF",
    "BUFF_REMOVED_SELF",
    "BUFF_ADDED_OTHER",
    "BUFF_REMOVED_OTHER",
    "DEBUFF_ADDED_SELF",
    "DEBUFF_REMOVED_SELF",
    "DEBUFF_ADDED_OTHER",
    "DEBUFF_REMOVED_OTHER",
    "UNIT_DIED",
    "PLAYER_ENTERING_WORLD",
}

local frame = CreateFrame("Frame", "CleveRoidsImmunityObservationFrame")
Pipeline.frame = frame

if CleveRoids.hasNampower then
    for i = 1, table.getn(EVENT_NAMES) do
        frame:RegisterEvent(EVENT_NAMES[i])
    end
end

frame:SetScript("OnEvent", function()
    Pipeline.HandleNampowerEvent(event, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8)
end)

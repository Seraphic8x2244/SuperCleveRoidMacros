local _G = _G or getfenv(0)
local CleveRoids = _G.CleveRoids or {}
_G.CleveRoids = CleveRoids

-- Slice 3 transient-only immunity safety reducer.
--
-- This module consumes only normalized ImmunityObservations. It maintains
-- target-centric NPC stun DR state plus temporary explanations that later
-- inference slices may query. Nothing here writes HearthDB, SavedVariables,
-- permanent immunity facts, or the production learner.
local Pipeline = CleveRoids.ImmunityObservations
local Context = CleveRoids.ImmunityTransient or {}
CleveRoids.ImmunityTransient = Context

Context.DR_RESET_WINDOW = 20
Context.DEATH_GUARD_WINDOW = 3
Context.STUN_EVENT_DEDUPE_WINDOW = 0.10

local VALID_DR_BUCKETS = {
    stun_control = true,
    stun_trigger = true,
    stun_kidneyshot = true,
}

local targets = Context.targets or {}
Context.targets = targets

local diagnostics = {
    observationsSeen = 0,
    auraTransitions = 0,
    stunLanded = 0,
    stunDeduped = 0,
    drCertain = 0,
    drUncertain = 0,
    deaths = 0,
    despawns = 0,
    worldResets = 0,
    last = nil,
}

local function normalizeGUID(guid)
    if guid == nil then return nil end
    if CleveRoids.NormalizeGUID then
        return CleveRoids.NormalizeGUID(guid)
    end
    return tostring(guid)
end

local function containsDimension(profile, dimension)
    if not profile or not profile.mechanicDimensions then return false end
    for i = 1, table.getn(profile.mechanicDimensions) do
        if profile.mechanicDimensions[i] == dimension then
            return true
        end
    end
    return false
end

local function getTargetState(guid, mobID, create)
    guid = normalizeGUID(guid)
    if not guid then return nil end

    local state = targets[guid]
    if state and mobID and state.mobID and state.mobID ~= mobID then
        -- A reused/re-resolved GUID must never inherit transient state from a
        -- different creature-template entry.
        targets[guid] = nil
        state = nil
    end

    if not state and create then
        state = {
            guid = guid,
            mobID = mobID,
            dr = {},
            auras = {},
            lastStunAt = {},
        }
        targets[guid] = state
    elseif state and mobID and not state.mobID then
        state.mobID = mobID
    end

    return state
end

local function resetTargetState(state, mobID)
    state.mobID = mobID
    state.dr = {}
    state.drCategoryUncertainUntil = nil
    state.drCategoryUncertain = nil
    state.auras = {}
    state.lastStunAt = {}
    state.deadUntil = nil
    state.lifecycle = nil
    state.lifecycleAt = nil
end

local function pruneState(state, now)
    if not state then return end

    for bucket, entry in pairs(state.dr) do
        if not entry.lastHitTime or (now - entry.lastHitTime) >= Context.DR_RESET_WINDOW then
            state.dr[bucket] = nil
        end
    end

    if state.drCategoryUncertainUntil and now >= state.drCategoryUncertainUntil then
        state.drCategoryUncertainUntil = nil
        state.drCategoryUncertain = nil
    end

    if state.deadUntil and now >= state.deadUntil then
        state.deadUntil = nil
        if state.lifecycle == "died" then
            state.lifecycle = nil
            state.lifecycleAt = nil
        end
    end
end

local function copyEffects(effects)
    local result = {}
    for i = 1, table.getn(effects or {}) do
        local effect = effects[i]
        table.insert(result, {
            source = effect.source,
            dimension = effect.dimension,
            auraType = effect.auraType,
            auraID = effect.auraID,
        })
    end
    return result
end

local function classifyAuraEffects(observation)
    if not CleveRoids.GetTransientImmunityAuraEffects then
        return {}
    end
    return CleveRoids.GetTransientImmunityAuraEffects(
        observation.spellID,
        observation.targetMobID
    )
end

local function rememberAura(observation, now)
    local state = getTargetState(
        observation.targetGUID,
        observation.targetMobID,
        false
    )

    if observation.auraOperation == "removed" then
        if state and state.auras[observation.spellID] then
            state.auras[observation.spellID] = nil
            diagnostics.auraTransitions = diagnostics.auraTransitions + 1
        end
        return
    end

    if observation.outcome ~= "aura_present" then return end

    local effects = classifyAuraEffects(observation)
    if table.getn(effects) == 0 then return end

    if not state then
        state = getTargetState(
            observation.targetGUID,
            observation.targetMobID,
            true
        )
    end
    if not state then return end

    state.auras[observation.spellID] = {
        spellID = observation.spellID,
        since = now,
        effects = copyEffects(effects),
    }
    diagnostics.auraTransitions = diagnostics.auraTransitions + 1
end

local function stunDedupeKey(observation)
    return tostring(observation.spellID or 0)
        .. ":" .. tostring(observation.casterGUID or "?")
        .. ":" .. tostring(observation.auraSlot or observation.luaSlot or "?")
end

local function recordLandedStun(observation, now)
    if observation.kind ~= "aura"
        or observation.auraKind ~= "debuff"
        or observation.outcome ~= "aura_present"
        or not containsDimension(observation.spell, "stun") then
        return
    end

    local existing = getTargetState(
        observation.targetGUID,
        observation.targetMobID,
        false
    )
    local mobID = observation.targetMobID or (existing and existing.mobID)
    if not mobID then
        -- We only advance NPC DR after the GUID has been proven to be a creature.
        return
    end

    local state = getTargetState(observation.targetGUID, mobID, true)
    if not state then return end
    pruneState(state, now)

    local key = stunDedupeKey(observation)
    local last = state.lastStunAt[key]
    if last and (now - last) < Context.STUN_EVENT_DEDUPE_WINDOW then
        diagnostics.stunDeduped = diagnostics.stunDeduped + 1
        return
    end
    state.lastStunAt[key] = now
    diagnostics.stunLanded = diagnostics.stunLanded + 1

    local bucket, certain, reason = nil, false, "classifier_unavailable"
    if CleveRoids.ClassifyNPCStunDR then
        bucket, certain, reason = CleveRoids.ClassifyNPCStunDR(
            observation.spellID,
            observation.casterGUID
        )
    end

    if certain and VALID_DR_BUCKETS[bucket] then
        local entry = state.dr[bucket]
        local count = 1
        if entry and entry.lastHitTime
            and (now - entry.lastHitTime) < Context.DR_RESET_WINDOW then
            count = (entry.count or 0) + 1
        end
        state.dr[bucket] = {
            count = count,
            lastHitTime = now,
            spellID = observation.spellID,
            casterGUID = observation.casterGUID,
            reason = reason,
        }
        diagnostics.drCertain = diagnostics.drCertain + 1
    else
        -- Nampower OTHER/aura evidence does not expose vMaNGOS's runtime
        -- triggered flag. Never guess controlled vs triggered: retain a
        -- temporary blocker until any plausible DR category has reset.
        state.drCategoryUncertainUntil = now + Context.DR_RESET_WINDOW
        state.drCategoryUncertain = {
            time = now,
            spellID = observation.spellID,
            casterGUID = observation.casterGUID,
            reason = reason or "controlled_vs_triggered_unknown",
        }
        diagnostics.drUncertain = diagnostics.drUncertain + 1
    end
end

local function clearTargetForLifecycle(observation, now)
    local guid = normalizeGUID(observation.targetGUID)
    if not guid then return end

    if observation.outcome == "died" then
        local state = getTargetState(guid, observation.targetMobID, true)
        if not state then return end
        local mobID = state.mobID
        resetTargetState(state, mobID)
        state.deadUntil = now + Context.DEATH_GUARD_WINDOW
        state.lifecycle = "died"
        state.lifecycleAt = now
        diagnostics.deaths = diagnostics.deaths + 1
    elseif observation.outcome == "despawned" then
        targets[guid] = nil
        diagnostics.despawns = diagnostics.despawns + 1
    end
end

local function onObservation(observation)
    if type(observation) ~= "table" then return end
    diagnostics.observationsSeen = diagnostics.observationsSeen + 1

    local now = tonumber(observation.timestamp) or GetTime()

    if observation.kind == "lifecycle" and observation.outcome == "world_reset" then
        for guid in pairs(targets) do
            targets[guid] = nil
        end
        diagnostics.worldResets = diagnostics.worldResets + 1
        diagnostics.last = {
            sequence = observation.sequence,
            outcome = observation.outcome,
        }
        return
    end

    if observation.kind == "death"
        or (observation.kind == "lifecycle"
            and (observation.outcome == "died" or observation.outcome == "despawned")) then
        clearTargetForLifecycle(observation, now)
    elseif observation.kind == "aura" then
        rememberAura(observation, now)
        recordLandedStun(observation, now)
    end

    diagnostics.last = {
        sequence = observation.sequence,
        kind = observation.kind,
        outcome = observation.outcome,
        targetGUID = observation.targetGUID,
        targetMobID = observation.targetMobID,
        spellID = observation.spellID,
    }
end

local function addExplanation(result, seen, source, dimension, detail, auraID)
    local key = tostring(source) .. ":" .. tostring(dimension or "")
        .. ":" .. tostring(auraID or detail or "")
    if seen[key] then return end
    seen[key] = true
    table.insert(result, {
        source = source,
        dimension = dimension,
        detail = detail,
        auraID = auraID,
    })
end

local function addLiveAuraFallbacks(result, seen, observation)
    local unit = observation.targetUnit
    if not unit then return end

    if CleveRoids.HasImmunityGuardAura then
        local _, auraType, auraID = CleveRoids.HasImmunityGuardAura(unit)
        if auraID then
            if auraType == "reflect" then
                addExplanation(result, seen, "reflection", nil, "active_aura", auraID)
            else
                addExplanation(result, seen, "temporary_aura", auraType, "active_aura", auraID)
            end
        end
    end

    if CleveRoids.IsTemporarilyCCImmune
        and observation.spell
        and observation.spell.mechanicDimensions then
        for i = 1, table.getn(observation.spell.mechanicDimensions) do
            local dimension = observation.spell.mechanicDimensions[i]
            local immune, auraID = CleveRoids.IsTemporarilyCCImmune(unit, dimension)
            if immune and auraID then
                addExplanation(
                    result,
                    seen,
                    "temporary_cc",
                    dimension,
                    "active_aura",
                    auraID
                )
            end
        end
    end
end

local function activeDRImmunityPossible(state, now)
    local buckets = { "stun_control", "stun_trigger" }
    for i = 1, table.getn(buckets) do
        local bucket = buckets[i]
        local entry = state.dr[bucket]
        if entry and entry.count and entry.count >= 3
            and entry.lastHitTime
            and (now - entry.lastHitTime) < Context.DR_RESET_WINDOW then
            return true, bucket, entry
        end
    end
    return false
end

function Context.GetDRGuard(targetGUID, spellID, casterGUID)
    local state = getTargetState(targetGUID, nil, false)
    if not state then return false end

    local now = GetTime()
    pruneState(state, now)

    if state.drCategoryUncertainUntil and now < state.drCategoryUncertainUntil then
        return true, "dr_category_uncertain", nil, nil, state.drCategoryUncertain
    end

    local bucket, certain, reason = nil, false, "classifier_unavailable"
    if CleveRoids.ClassifyNPCStunDR then
        bucket, certain, reason = CleveRoids.ClassifyNPCStunDR(spellID, casterGUID)
    end

    if not certain or not VALID_DR_BUCKETS[bucket] then
        -- The current OTHER-caster stun may itself be control or trigger. If
        -- either plausible bucket has already reached immune-stage DR, permanent
        -- inference must remain blocked rather than choosing one.
        local possible, possibleBucket, entry = activeDRImmunityPossible(state, now)
        if possible then
            return true, "dr_category_uncertain", nil, entry.count, {
                reason = reason or "controlled_vs_triggered_unknown",
                possibleBucket = possibleBucket,
                entry = entry,
            }
        end
        return false, nil, bucket
    end

    local entry = state.dr[bucket]
    if entry and entry.count and entry.count >= 3
        and entry.lastHitTime
        and (now - entry.lastHitTime) < Context.DR_RESET_WINDOW then
        return true, "dr", bucket, entry.count, entry
    end

    return false, nil, bucket, entry and entry.count or 0, entry
end

local function identityIsUnresolved(status)
    return status == "missing_guid"
        or status == "not_live"
        or status == "stale_token"
end

function Context.GetExplanations(observation)
    local result = {}
    local seen = {}
    if type(observation) ~= "table" then return result end

    if observation.missReason == "reflect" then
        addExplanation(result, seen, "reflection", nil, "direct_miss")
    end

    local state = getTargetState(
        observation.targetGUID,
        observation.targetMobID,
        false
    )
    local now = GetTime()
    if state then
        pruneState(state, now)

        if state.deadUntil and now < state.deadUntil then
            addExplanation(result, seen, "death", nil, "recent_death")
        end

        for _, aura in pairs(state.auras) do
            for i = 1, table.getn(aura.effects or {}) do
                local effect = aura.effects[i]
                addExplanation(
                    result,
                    seen,
                    effect.source,
                    effect.dimension,
                    "normalized_aura",
                    effect.auraID
                )
            end
        end

        if containsDimension(observation.spell, "stun") then
            local guarded, source, bucket, count, detail = Context.GetDRGuard(
                observation.targetGUID,
                observation.spellID,
                observation.casterGUID
            )
            if guarded then
                addExplanation(
                    result,
                    seen,
                    source,
                    bucket,
                    count or detail
                )
            end
        end
    end

    if identityIsUnresolved(observation.targetIdentity) then
        addExplanation(
            result,
            seen,
            "target_identity_unresolved",
            nil,
            observation.targetIdentity
        )
    end

    addLiveAuraFallbacks(result, seen, observation)
    return result
end

function Context.GetTargetState(targetGUID)
    local state = getTargetState(targetGUID, nil, false)
    if not state then return nil end
    pruneState(state, GetTime())

    local snapshot = {
        guid = state.guid,
        mobID = state.mobID,
        deadUntil = state.deadUntil,
        lifecycle = state.lifecycle,
        drCategoryUncertainUntil = state.drCategoryUncertainUntil,
        drCategoryUncertain = state.drCategoryUncertain,
        dr = {},
        auras = {},
    }

    for bucket, entry in pairs(state.dr) do
        snapshot.dr[bucket] = {
            count = entry.count,
            lastHitTime = entry.lastHitTime,
            spellID = entry.spellID,
            casterGUID = entry.casterGUID,
            reason = entry.reason,
        }
    end
    for spellID, aura in pairs(state.auras) do
        snapshot.auras[spellID] = {
            spellID = aura.spellID,
            since = aura.since,
            effects = copyEffects(aura.effects),
        }
    end

    return snapshot
end

function Context.GetDiagnostics()
    local targetCount = 0
    for _ in pairs(targets) do
        targetCount = targetCount + 1
    end
    return {
        observationsSeen = diagnostics.observationsSeen,
        auraTransitions = diagnostics.auraTransitions,
        stunLanded = diagnostics.stunLanded,
        stunDeduped = diagnostics.stunDeduped,
        drCertain = diagnostics.drCertain,
        drUncertain = diagnostics.drUncertain,
        deaths = diagnostics.deaths,
        despawns = diagnostics.despawns,
        worldResets = diagnostics.worldResets,
        targetCount = targetCount,
        last = diagnostics.last,
    }
end

function Context.Reset()
    for guid in pairs(targets) do
        targets[guid] = nil
    end
end

if Pipeline and Pipeline.RegisterListener then
    Pipeline.RegisterListener(onObservation)
end

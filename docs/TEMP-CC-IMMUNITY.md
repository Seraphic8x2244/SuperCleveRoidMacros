# Temporary CC Immunity Microsystem

## Status

Implemented on branch `design/temp-cc-immunity`.

Runtime implementation is intentionally confined to `Utility.lua`; this
document remains the contract for adding future curated rules.

This design extends the CC/immunity model documented in
`docs/CC-IMMUNITY-DR.md` with one deliberately small exception mechanism:
known NPC encounter auras that make a creature temporarily immune to one or
more CC mechanics.

The subsystem is intentionally curated. It does not attempt to infer temporary
CC immunity from arbitrary DBC aura effects.

## Problem

SCRM learns permanent NPC CC immunity after a CC spell returns `IMMUNE`, with
guards for DR and broad temporary invulnerability effects.

That assumption is wrong for a small class of encounter mechanics where a
specific NPC becomes immune to a specific CC mechanic only while a specific
aura is active.

Confirmed regression case:

```text
Battleguard Sartura
creature entry: 15516
aura/spell:     26083 Whirlwind
temporary CC:  stun
```

vMaNGOS' Sartura script explicitly describes her as stun immune during
Whirlwind and casts spell 26083 for that phase. Historical vMaNGOS data also
removes Sartura's static creature-template stun immunity, matching the intended
behaviour that she is not permanently stun immune.

Current SCRM can observe a stun returning `IMMUNE` during Whirlwind and record:

```text
Battleguard Sartura -> cc_stun -> permanent
```

That poisons later `[immune:stun]` / `[noimmune:stun]` decisions after the
Whirlwind has ended.

## Design goal

Add a clinical, read-only `TempCCImmune` microsystem which answers exactly one
question:

```text
Is this creature temporarily immune to this CC mechanic because a curated
encounter aura is active right now?
```

It must:

- key rules by creature entry ID, never NPC name;
- key the temporary state by exact aura spell ID;
- specify the exact CC mechanic(s) suppressed by that aura;
- affect only matching CC mechanics;
- be usable by both macro immunity checks and immunity-learning guards;
- write nothing to `CleveRoids_ImmunityData`;
- remain small, explicit and easy to audit;
- live in the existing immunity utility code unless it grows enough to justify
  extraction later.

It must not:

- disable all immunity learning while any listed aura is active;
- infer encounter behaviour from arbitrary DBC aura fields;
- treat a listed aura as generic invulnerability;
- special-case NPC names;
- silently add or remove learned permanent immunity records.

## Curated data model

Conceptual shape:

```lua
local TEMP_CC_IMMUNITIES = {
    [15516] = { -- Battleguard Sartura
        [26083] = { stun = true }, -- Whirlwind
    },
}
```

The nesting is intentional:

```text
creature entry -> active aura spell ID -> CC mechanic
```

A rule is therefore only true when all three identities match.

For Sartura:

```text
15516 + 26083 + stun -> true
15516 + 26083 + fear -> false
15516 + any other aura + stun -> false
another creature + 26083 + stun -> false
```

This is stricter than a global `auraID -> mechanic` table and prevents an aura
ID from becoming an unintended cross-encounter rule.

## Creature entry identity

The subsystem needs a stable creature entry ID and uses ClassicAPI's
`UnitCreatureID(unit)` for it.

`UnitCreatureID` resolves normal and extended unit tokens (including raw GUID
tokens) and returns the creature-template/NPC entry directly. This keeps GUID
layout and client/server GUID-prefix details out of SCRM.

Implementation hides that dependency behind one small helper, conceptually:

```lua
GetCreatureEntry(unit) -> UnitCreatureID(unit)
```

The rest of TempCCImmune does not parse GUID strings or depend on localized NPC
names. `UnitCreatureID` was added to ClassicAPI before the v1.15.8 minimum
already required by SCRM.

## Aura lookup

Once the creature entry has matched a curated rule, only the aura IDs listed
for that creature need to be queried.

Do not scan or classify every aura through DBC mechanics.

Conceptually:

```lua
IsTemporarilyCCImmune(unit, ccType)
    -> resolve creature entry
    -> find TEMP_CC_IMMUNITIES[entry]
    -> check only the listed aura IDs on that unit
    -> return true only when an active listed aura contains ccType
```

Use the existing aura-query abstraction already used by SCRM so hidden/overflow
aura handling remains consistent with the rest of the addon.

## Interaction with `CheckCCImmunity`

Temporary immunity is a current-state fact, so the query belongs alongside the
existing learned-immunity check.

Conceptually:

```text
CheckCCImmunity(unit, ccType)

1. IsTemporarilyCCImmune(unit, ccType)?
      yes -> true
2. existing learned permanent / conditional immunity logic
3. otherwise false
```

This means Sartura behaves correctly without learning anything:

```text
outside Whirlwind: [immune:stun] = false
during Whirlwind:  [immune:stun] = true
after Whirlwind:   [immune:stun] = false
```

A stale permanent SavedVariables entry from an older build can still override
the post-Whirlwind state through the existing learned-immunity path. The
TempCCImmune subsystem must not automatically delete user data. Existing bad
test data should be removed explicitly before validation.

## Interaction with immunity learning

TempCCImmune is an explanation for a matching `IMMUNE` result. When it
matches, permanent learning for that mechanic must stop immediately.

It must guard both automatic CC-learning routes:

1. explicit Nampower `SPELL_MISS -> IMMUNE`;
2. delayed CC verification where the expected debuff never appeared.

Conceptually:

```text
attempt to learn CC immunity

resolve attempted immunityType
IsTemporarilyCCImmune(target, immunityType)?
    yes -> result is explained; do not RecordCCImmunity
    no  -> continue existing death / DR / other immunity safeguards
```

The guard is mechanic-specific.

While Sartura is Whirlwinding:

```text
stun IMMUNE    -> TempCCImmune matches -> do not learn stun
fear IMMUNE    -> no TempCCImmune match -> normal fear logic continues
root IMMUNE    -> no TempCCImmune match -> normal root logic continues
school IMMUNE  -> unaffected; normal school-immunity logic continues
```

Do not implement a broad `IsAnyTempCCImmune()` switch that disables immunity
learning for the whole target.

## Relationship to the general immunity guard

TempCCImmune is separate from the existing curated protection/reflection guard.

The concepts mean different things:

```text
general immunity-guard aura
    makes a failed spell/debuff observation inconclusive while a known
    protection or reflection effect is active

TempCCImmune rule
    explains only the explicitly listed CC mechanic for one creature while
    one explicitly listed aura is active
```

Sartura's Whirlwind must not be added to the general immunity-guard table.
Doing so could incorrectly suppress learning of unrelated real immunities
observed during Whirlwind.

The September 2026 audit removed stale entries that had been incorrectly
treated as generic immunity guards (including Sap and unrelated 25-second
effects) and added Ice Block as an actual full-immunity aura. The guard list is
now curated rather than derived from a DBC mechanic number.

## Implemented integration points

The current implementation contains:

- `TEMP_CC_IMMUNITIES` in `Utility.lua`;
- a creature-entry resolver backed by ClassicAPI `UnitCreatureID(unit)`;
- `IsTemporarilyCCImmune(unit, ccType)`, using
  `C_UnitAuras.GetUnitAuraBySpellID` so only curated aura IDs are queried;
- a live-state check in `CheckCCImmunity`;
- a matching-mechanic guard in delayed missing-debuff immunity learning;
- a matching-mechanic guard in Nampower `SPELL_MISS -> IMMUNE` learning.

No SavedVariables format changes are introduced.

## First curated rule

```lua
[15516] = { -- Battleguard Sartura
    [26083] = { stun = true }, -- Whirlwind: temporary stun immunity
},
```

Evidence:

- `vmangos/core/src/scripts/kalimdor/silithus/temple_of_ahnqiraj/boss_sartura.cpp`
  defines `SPELL_WHIRLWIND = 26083` and documents that Sartura is stun immune
  during Whirlwind.
- vMaNGOS migration `20231216221145_world.sql` removes the permanent stun bit
  from creature entry 15516 and annotates the case as Sartura having Whirlwind.

The rule is encounter knowledge, not DBC inference.

## Adding future rules

Only add a rule when all of these are known:

- exact creature entry ID;
- exact active aura spell ID;
- exact CC mechanic(s) made temporarily immune;
- evidence that the immunity is temporary and tied to that aura.

Every entry should include comments naming the NPC and aura.

Preferred style:

```lua
[creatureEntry] = { -- NPC Name
    [auraSpellID] = {
        stun = true, -- Aura Name: why this mechanic is temporarily immune
    },
},
```

Do not add an entry merely because an `IMMUNE` event was observed. First
exclude permanent creature immunity, DR, death, generic invulnerability and
other existing safeguards.

## Locale and portability audit

TempCCImmune makes no decisions from localized game text:

- creature identity is numeric via ClassicAPI `UnitCreatureID(unit)`;
- aura identity is numeric via `C_UnitAuras.GetUnitAuraBySpellID`;
- the table stores SCRM's canonical mechanic token (for example `stun`);
- NPC/aura names in the table are comments only;
- `C_Spell.GetSpellName` is used only for debug/display output.

The subsystem therefore does not require English NPC names, English spell
names, or English combat-log messages.

A separate legacy combat-log fallback elsewhere in `Utility.lua` still parses
the English phrase `"is afflicted by"` for hidden-Pounce/bleed confirmation.
That path predates TempCCImmune and is not used to identify Sartura, her
Whirlwind aura, or the requested CC mechanic. It remains a separate
localization cleanup item rather than being folded into this microsystem.

## Validation plan

Before testing Sartura, remove any previously learned false permanent stun
entry for her:

```text
/cleveroid removeccimmune Battleguard Sartura stun
```

Then validate:

1. Before Whirlwind, `[immune:stun]` is false.
2. During Whirlwind, `[immune:stun]` is true.
3. A stun returning `IMMUNE` during Whirlwind does not create a permanent
   `cc_stun` SavedVariables entry.
4. After Whirlwind ends, `[immune:stun]` returns false again.
5. A later successful stun remains able to land normally.
6. An unrelated CC `IMMUNE` during Whirlwind is not suppressed unless that
   mechanic is explicitly listed for the aura.
7. The explicit Nampower miss path and delayed missing-debuff path both obey the
   same TempCCImmune rule.
8. Existing DR safeguards continue unchanged.
9. Existing generic invulnerability handling continues unchanged.
10. No TempCCImmune state is persisted to SavedVariables.

## Implementation footprint

The intended implementation is deliberately small and should remain in the
existing immunity utility file:

- one curated `TEMP_CC_IMMUNITIES` table;
- one creature-entry resolver helper;
- one `IsTemporarilyCCImmune(unit, ccType)` helper;
- one call from `CheckCCImmunity`;
- one guard in each automatic CC-immunity learning route.

No new Lua module is required for the initial implementation.

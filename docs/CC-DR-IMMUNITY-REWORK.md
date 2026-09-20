# CC, DR, Immunities and Temporary Immunities Rework

## Journey

This branch grew from several separate bugs that turned out to be one model problem:

- CC mechanics were collapsed too broadly: Gouge/Sap-style immunity could become
  stun immunity.
- Nampower `SPELL_MISS` arguments were read in the wrong order.
- DR protection used the wrong grouping and did not reset correctly.
- Sartura proved that a real `IMMUNE` can be temporary and encounter-specific.
- The general protection guard was too broad and was replaced with curated IDs.
- Anti-Magic Shield showed that magic immunity is not CC immunity.
- Blackwing Spellbinder showed that HoJ can be immune while physical stuns still
  land, so exact CC, school immunity, spell immunity, broad CC immunity and
  absolute immunity must be separate.

The rework now covers CC classification, DR, permanent immunity learning,
temporary immunity, and broad immunity inference.

---

## 1. Core model

### 1.1 Separate identities

| Identity | Meaning |
|---|---|
| `ccType` | Exact DBC mechanic used by `[cc:*]` and landing checks |
| `immunityType` | Exact DBC mechanic stored for learned NPC CC immunity |
| DR type | Vanilla DR pool; internal only |
| school | fire/frost/nature/shadow/arcane/holy, plus physical/bleed |
| `spellimmune` | broad magical/spell immunity |
| `ccimmune` | broad immunity to CC mechanics |
| `immune` | absolute/broad immunity |
| temporary explanation | live aura/DR/death/reflection/etc. that explains an `IMMUNE` now |

These axes can overlap.

Examples:

```text
Blackwing Spellbinder: spellimmune=true, stunimmune=false
Sartura Whirlwind:     temporary stunimmune=true
Fire-immune NPC:       fireimmune=true, spellimmune=false
```

### 1.2 Exact CC taxonomy

`[cc:*]` follows the Vanilla client DBC mechanic exactly.

| DBC mechanic | ID | Canonical key |
|---|---:|---|
| Charm | 1 | `charm` |
| Disoriented | 2 | `disorient` |
| Disarm | 3 | `disarm` |
| Distract | 4 | `distract` |
| Fear | 5 | `fear` |
| Fumble | 6 | `fumble` |
| Root | 7 | `root` |
| Pacify | 8 | `pacify` |
| Silence | 9 | `silence` |
| Sleep | 10 | `sleep` |
| Snare | 11 | `snare` |
| Stun | 12 | `stun` |
| Freeze | 13 | `freeze` |
| Knockout | 14 | `knockout` |
| Bleed | 15 | `bleed` |
| Polymorph | 17 | `polymorph` |
| Banish | 18 | `banish` |
| Shackle | 20 | `shackle` |
| Turn | 23 | `turn` |
| Horror | 24 | `horror` |
| Interrupt | 26 | `interrupt` |
| Daze | 27 | `daze` |

Aliases:

```text
slow -> snare
disoriented -> disorient
grip -> fumble
sap -> knockout
incap / incapacitate / incapacitated -> knockout (immunity input)
```

Vanilla Sap is mechanic 14. The server enum `MECHANIC_SAPPED = 30` is not a
1.12 client DBC row.

Mechanics 16, 19, 21, 22 and 25 are not exposed as CC.

Bare `[cc]` / `[cc:any]` remain aggregate loss-of-control checks via
`CCTypesLossOfControl`.

### 1.3 DR is only a learning safeguard

DR matters here because DR level 4 can return `IMMUNE`, which must not become
permanent NPC immunity.

For NPCs, only these vMaNGOS `DRTYPE_ALL` pools matter:

```text
DIMINISHING_CONTROL_STUN
DIMINISHING_TRIGGER_STUN
DIMINISHING_KIDNEYSHOT
```

Everything else is player-only DR.

Current mapping:

```text
Kidney Shot                   -> stun_kidneyshot
Charge / Intercept stun       -> stun_control
other mechanic-12 client cast -> stun_control
other mechanic-12 proc        -> stun_trigger
```

Details retained from the audit:

- Kidney Shot uses rogue family bit 21 (`0x00200000`).
- Charge 7922 and Intercept 20253/20614/20615 are triggered exceptions that
  belong to controlled stun.
- client-cast vs proc is reconstructed from Nampower `SPELL_CAST_EVENT`.
- `recentCCHits[targetGUID][drType]` resets after 20s.
- `IMMUNE` is discarded as DR only after 3+ landed hits in that pool/window.

Sources:
`SpellEntry.h:52-79`, `SpellEntry.cpp:281-432`,
`Unit.cpp:7881`, `SpellClassMask.h:228`.

### 1.4 Nampower miss payload

```text
arg1 = casterGuid
arg2 = targetGuid
arg3 = spellId
arg4 = missInfo
```

Source: `nampower/spellevents.cpp:888-917`.

### 1.5 Current learned data

`CleveRoids_ImmunityData` already stores:

```text
fire frost nature shadow arcane holy physical bleed unknown
cc_<canonical mechanic>
```

Manual and buff-conditional records remain supported. This branch does not
silently rewrite user data.

---

## 2. Temporary immunity

### 2.1 TempCCImmune

Purpose:

```text
creature entry + active aura ID + exact CC mechanic -> temporary immunity
```

Current rule:

```lua
[15516] = { -- Battleguard Sartura
    [26083] = { stun = true }, -- Whirlwind
},
```

Only add a rule when creature ID, aura ID, affected mechanic and temporary
relationship are all verified.

Implementation:

- creature identity: `UnitCreatureID(unit)`
- aura lookup: `C_UnitAuras.GetUnitAuraBySpellID(unit, auraID)`
- no NPC-name matching
- no full aura scan
- no SavedVariables writes

`CheckCCImmunity` checks TempCCImmune before learned immunity.

Expected Sartura state:

```text
outside Whirlwind -> [immune:stun] false
during Whirlwind  -> [immune:stun] true
after Whirlwind   -> [immune:stun] false
```

Both automatic CC-learning paths use the same guard:

1. Nampower `SPELL_MISS -> IMMUNE`
2. delayed missing-debuff verification

Only the matching mechanic is suppressed.

### 2.2 General temporary guard

`IMMUNITY_GUARD_AURA_IDS` prevents temporary protection/reflection from
becoming permanent learned immunity.

Current verified groups:

| Type | IDs |
|---|---|
| Divine Protection | 498, 5573 |
| Divine Shield | 642, 1020 |
| Ice Block | 11958, 27619 |
| Anti-Magic Shield | 7121, 19645, 24021 |
| Blessing of Protection | 1022, 5599, 10278 |
| Reflection | curated spell-reflection / reflector IDs already in `Utility.lua` |

The table is a learning guard, not yet a typed live immunity source.

Same-name effects are not sufficient evidence. Absorbs and damage reduction are
excluded; TBC Spell Shield 33054 is not treated as Vanilla immunity.

### 2.3 Precedence

Before permanent inference, explain `IMMUNE` through current state first:

```text
TempCCImmune
typed/full protection
magic/physical protection
reflection
DR
recent death
debuff-cap ambiguity
```

If explained, do not reinforce permanent immunity.

---

## 3. Generalized immunity learner

### 3.1 Vocabulary

Proposed independent categories:

```text
fireimmune
frostimmune
natureimmune
shadowimmune
arcaneimmune
holyimmune
spellimmune
ccimmune
<exact mechanic>immune
immune
```

`physical` and `bleed` remain existing dimensions.

Whether these become macro tokens is still open.

### 3.2 Observation before conclusion

One `IMMUNE` can have several causes.

```text
HoJ -> IMMUNE
candidates: holyimmune, spellimmune, stunimmune, ccimmune, immune

Charge Stun -> LANDS
remove: stunimmune, ccimmune, immune

Fireball -> IMMUNE
candidate overlap with HoJ: spellimmune
```

That still does not prove `spellimmune`: `holyimmune + fireimmune` could
produce the same two observations.

Use three conceptual states:

```text
unknown -> candidate -> confirmed
```

### 3.3 Successful hits are eliminators

```text
Frostbolt lands -> not frostimmune / spellimmune / immune
Cheap Shot lands -> not stunimmune / ccimmune / immune
Fear lands -> not fearimmune / ccimmune / immune
```

Do not use inferred negative evidence to silently remove explicit/manual records.

### 3.4 Blackwing Spellbinder regression case

vMaNGOS migration `20231216221145_world.sql` annotates creature 12457:

```text
Blackwing Spellbinder (HAS AURAS: Spell Immunity)
```

It also records the useful stun split: physical/melee stuns can work while HoJ
and grenade-style magical stuns can return `IMMUNE`.

Required model:

```text
spellimmune = true
stunimmune  = false
```

An HoJ `IMMUNE` must therefore not create permanent `cc_stun`.

The exact Vanilla Spell Immunity aura/effect still needs identifying.

### 3.5 Spell Shield / Anti-Magic cases

The discussed ZG and Stratholme Spell Shield mobs may be temporary
`spellimmune` examples. Before adding them, verify creature IDs, aura IDs and
actual effect semantics.

Anti-Magic Shield 7121/19645/24021 is already verified as broad magic immunity
for learning-guard purposes.

### 3.6 `spellimmune` classification

Do not define `spellimmune` as "ability has a Spell.dbc row"; physical melee
abilities also do.

The classifier must allow:

```text
HoJ -> blocked
Cheap Shot -> not blocked
Charge Stun -> not blocked
```

Verify whether the correct primitive is school mask, aura type, attributes, or
another server/DBC property before coding.

### 3.7 Event footprint

Reuse existing events/data:

- Nampower `SPELL_MISS -> IMMUNE`
- successful `SPELL_GO`
- confirmed CC/debuff application
- spell ID / DBC school / exact mechanic
- target GUID/name
- DR pool
- temporary guard state

Preferred shape:

```lua
ObserveImmunity(target, spellID, result)
```

No new aura-scanning frame, target polling loop, high-frequency `OnUpdate`,
duplicate combat-log parser, or whole-aura DBC classification pass.

### 3.8 Typed temporary guards

Eventually replace the boolean general guard with typed cause information, e.g.:

```text
FULL_IMMUNITY_AURAS
SPELL_IMMUNITY_AURAS
PHYSICAL_IMMUNITY_AURAS
REFLECTION_AURAS
```

or an equivalent typed table.

Keep reflection, magic protection, physical protection, absolute immunity and
TempCC distinct.

---

## 4. Done

- exact CC mechanic learning instead of coarse stun buckets
- Vanilla Sap canonicalized to mechanic 14 / `knockout`
- NPC DR safeguard limited to the three stun pools
- DR count reset fixed
- Kidney/control/trigger stun separation
- Nampower `SPELL_MISS` argument order fixed
- bare immunity checks include mechanic immunity
- `TEMP_CC_IMMUNITIES` implemented
- Sartura 15516 / Whirlwind 26083 / stun rule
- `UnitCreatureID` + by-ID aura lookup
- TempCC live conditional integration
- TempCC guard in both automatic CC-learning routes
- no TempCC persistence/schema change
- broad mechanic-25 guard removed
- curated `IMMUNITY_GUARD_AURA_IDS`
- Ice Block and Anti-Magic Shield variants added
- absorb/damage-reduction lookalikes excluded
- TempCC path is numeric/locale-independent
- hidden-CC aura confirmation uses localized Blizzard GlobalStrings
- duplicate localized parsing hardened/removed
- split-CC fallback localized

---

## 5. Validation and open work

### Sartura

Before test:

```text
/cleveroid removeccimmune Battleguard Sartura stun
```

- [ ] outside Whirlwind: `[immune:stun]` false
- [ ] during Whirlwind: `[immune:stun]` true
- [ ] `[noimmune:stun]` HoJ refuses during Whirlwind
- [ ] forced HoJ returns `IMMUNE`
- [ ] no permanent `cc_stun`
- [ ] after Whirlwind: condition clears / HoJ eligible
- [ ] later stun can land
- [ ] unrelated CC learning is not suppressed
- [ ] direct miss + delayed verifier match
- [ ] DR/general guards unchanged
- [ ] no TempCC persistence
- [ ] aura 26083 is visible through the client aura API

### Generalized learner

Blackwing Spellbinder:
- [ ] verify entry 12457 behaviour on target server
- [ ] HoJ `IMMUNE`
- [ ] Cheap Shot lands
- [ ] Charge Stun lands
- [ ] non-Holy magic `IMMUNE`
- [ ] no false `cc_stun`
- [ ] only confirm `spellimmune` with sufficient evidence

Single-school target:
- [ ] one school immune, another magical school lands
- [ ] disprove `spellimmune`
- [ ] learn only demonstrated school

Broad CC target:
- [ ] multiple CC methods fail
- [ ] ordinary non-CC spells can land
- [ ] distinguish `ccimmune` from `spellimmune`

Absolute temporary immunity:
- [ ] physical + magical effects fail while active
- [ ] live `immune` true
- [ ] no permanent broad record from temporary protection

Temporary spell immunity:
- [ ] identify verified Vanilla Spell Shield/Anti-Magic-style aura
- [ ] magic fails, suitable physical effects still work
- [ ] no permanent school/`spellimmune` from the temporary aura

### Decisions before implementation

1. Identify the exact Vanilla basis for `spellimmune`:
   Blackwing Spellbinder + discussed ZG/Stratholme Spell Shield cases.
2. Define conservative candidate -> confirmed rules so multiple narrow school
   immunities cannot masquerade as `spellimmune`.

Then decide:

- [ ] exact semantics of school/`spellimmune`/`ccimmune`/`immune`
- [ ] macro syntax, if any
- [ ] query precedence
- [ ] whether broad categories can be inferred from outcomes alone
- [ ] candidate/evidence structure and target key
- [ ] persistence of confirmed/candidate/negative evidence
- [ ] separation of manual vs inferred records
- [ ] SavedVariables migration before any schema change

Preferred rule: confirm the narrowest explanation that fits the evidence.

---

## 6. Known limitations / deferred

- Mouseover miss learning remains conservative when no queryable unit can be
  resolved; this avoids learning through unseen temporary buffs.
- Legacy SavedVariables may contain `cc_sap`; no automatic migration.
- Reflect handling could explicitly cancel matching pending verification.
- Some unrelated old combat-log fallbacks still contain English phrases.
- Extremely short temporary auras could end before delayed verification when no
  direct miss event exists; Sartura is unaffected.
- Do not split this into a new Lua module unless the learner grows enough to
  justify it.

---

## 7. Implementation target

Keep TempCC small:

```text
TEMP_CC_IMMUNITIES
GetCreatureEntry
IsTemporarilyCCImmune
CheckCCImmunity integration
two automatic-learning guards
```

Generalized path:

```text
existing event
 -> temporary explanation?
 -> classify observation
 -> update compact per-NPC evidence
 -> confirm only when rules are satisfied
 -> immunity query consumes confirmed facts
```

No runtime change until `spellimmune` classification and confirmation rules
are settled.

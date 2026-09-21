# Immunity Framework Development

Active implementation/recovery document for the **framework stage** of the
CC/DR/immunity rework.

The durable design and historical reasoning remain in
`docs/CC-DR-IMMUNITY-REWORK.md`.

## Recovery snapshot

- Branch: `design/temp-cc-immunity`
- Base: `main`
- Branch head before this handoff refresh: `3942c67d762e4354df0a03f01c31ce1cd6b1cff8`
- Branch relation before this handoff refresh: 66 ahead / 0 behind `main`
- TOC version: `@project-version@`
- Latest runtime-related commit: `3e7eccb57858ca2a399c7fb302192859ab890f6e`
- Recent commits:
  - `3942c67d` — Resolve spell immunity classification basis
  - `b226bc67` — Record immunity framework step seven completion
  - `3e7eccb5` — Clarify school based spell immunity classification
  - `7ec46616` — Classify spell immunity dimensions
  - `b3c65497` — Record Hammer of Justice step seven invariants
  - `b17a3669` — Record immunity framework step six completion
  - `af3dc511` — Compose typed immunity precedence
  - `fabd382a` — Record framework step six start
  - `68f9385e` — Complete framework step five verification
  - `10184be3` — Record immunity framework step five completion
  - `a7ce4661` — Record framework step five start
  - `18a1cfaa` — Record immunity framework step four completion
  - `3bdeb163` — Type temporary immunity aura guards
  - `9f4016ad` — Record framework step four start
  - `adb62e8d` — Correct framework runtime head
  - `0eba3721` — Record immunity framework step three completion
  - `0b4e081e` — Track immunity query sources
  - `695f05ef` — Record framework step three start
  - `be8c4db6` — Record immunity framework step two completion
  - `97383436` — Route spell mechanic checks through typed immunity query
  - `4241f918` — Centralize typed immunity queries
  - `18c1f507` — Add canonical immunity type framework
  - `f2b5f684` — Record framework step one start
  - `7dd3cc92` — Refresh immunity framework recovery snapshot
  - `690da05a` — Add immunity framework development handoff
  - `5896f6cb` — Clean consolidated rework section breaks
- Current runtime diff is limited to `Utility.lua` and `Conditionals.lua`.
- The generalized comparative learner is **not** part of this stage.

## Stage scope

Build the immunity framework first.

This stage ends when SCRM has one consistent internal model for:

```text
school immunity
exact CC immunity
broad spell immunity
broad CC immunity
absolute immunity
temporary immunity/protection
reflection as a non-immunity explanation
```

and current known/live sources can answer those queries correctly.

Do **not** implement comparative learning, evidence persistence, or new public
macro syntax during this stage.

---

## Locked decisions

### Canonical immunity dimensions

Schools:

```text
fire
frost
nature
shadow
arcane
holy
physical
bleed
```

Exact CC mechanics remain the existing canonical mechanic keys:

```text
stun
freeze
knockout
fear
root
silence
sleep
charm
polymorph
banish
shackle
horror
disorient
daze
snare
```

Broad dimensions:

```text
spell
cc
all
```

`unknown` remains an existing learning/storage fallback, not a real immunity
dimension that should be queried as broad immunity.

### Broad meanings

```text
all
    absolute immunity; blocks every relevant action

spell
    broad non-physical school immunity (Holy/Fire/Nature/Frost/Shadow/Arcane)
    follows Vanilla school-immunity masks, not DmgClass and not the mere fact
    that an ability has a Spell.dbc row

cc
    broad immunity to all CC mechanics
    independent of whether the CC is magical or physical
```

Examples that the framework must eventually represent:

```text
Blackwing Spellbinder
    spell = true
    stun  = false

Sartura during Whirlwind
    stun  = true temporarily
    spell = false
    cc    = false

Fire-immune NPC
    fire  = true
    spell = false
```

### Temporary aura table shape

Replace the current flat `IMMUNITY_GUARD_AURA_IDS` with semantic buckets:

```lua
local IMMUNITY_AURAS = {
    all = {
        [642] = true,
        [1020] = true,
        -- more verified ranks / variants
    },

    spell = {
        [7121] = true,
        [19645] = true,
        [24021] = true,
    },

    physical = {
        [1022] = true,
        [5599] = true,
        [10278] = true,
    },

    reflect = {
        -- verified reflection IDs
    },
}
```

This shape is deliberately simple for contributors.

**Multiple spell IDs are expected.** Add ranks, NPC variants, alternate
applications, or server variants as another `[spellID] = true` entry in the
appropriate bucket.

Do not add a family abstraction unless the simple bucket form later proves
insufficient.

`reflect` is an explanation/learning guard, not an immunity dimension.

### TempCC remains separate

Keep:

```text
TEMP_CC_IMMUNITIES
    creature entry -> aura ID -> exact CC mechanic
```

Do not flatten Sartura-style encounter rules into `IMMUNITY_AURAS`.

### Framework before learner

The learner will eventually consume this framework. The framework must not be
shaped around a partial learner implementation.

---

## Current code shape

All current immunity runtime code is in `Utility.lua`.

### Existing static definitions

Around the immunity tracking section:

- `IMMUNITY_SCHOOLS`
- `CC_IMMUNITY_TYPES`
- `CC_IMMUNITY_ALIASES`
- `NormalizeCCImmunityType`
- `MECHANIC_TO_CC_TYPE`
- `MECHANIC_TO_IMMUNITY_TYPE`

Current school storage already includes:

```text
physical holy fire nature frost shadow arcane bleed unknown
```

### Current temporary guards

Near the delayed-tracking setup:

- `IMMUNITY_GUARD_AURA_IDS`
- `HasImmunityGuardAura(unit)`
- `TEMP_CC_IMMUNITIES`
- `GetCreatureEntry(unit)`
- `IsTemporarilyCCImmune(unit, ccType)`

The flat general guard currently mixes:

```text
full immunity
magic immunity
physical protection
reflection
```

because they all currently mean only "do not permanently learn this failure".

This is the main structure being replaced in this stage.

### Current query functions

- `CheckCCImmunity(unitId, ccType)`
- `SchoolImmune(unitId, school, targetName)`
- `CleveRoids.CheckImmunity(unitId, spellOrSchool)`

Current behaviour:

- exact CC query can use TempCC + learned `cc_<mechanic>`
- school query can use learned school data
- spell-name query checks exact CC mechanic, then school
- Banish has bespoke live handling
- the general temporary guard does **not** currently make generic live
  `CheckImmunity` true

### Current learning paths

Direct Nampower path:

```text
ProcessSpellMissSelf
 -> resolve queryable unit
 -> TempCC exact mechanic guard
 -> HasImmunityGuardAura
 -> DR guard
 -> RecordCCImmunity or RecordImmunity
```

Delayed missing-debuff/CC verification also checks TempCC and
`HasImmunityGuardAura`.

These guards must remain functionally safe throughout the refactor.

### Conditionals

`Conditionals.lua` already routes `[immune]` / `[noimmune]` through
`CleveRoids.CheckImmunity`.

Do not change the public conditional grammar during this stage.

---

## Implementation order

### Step 1 — canonical framework types — DONE

Add one internal canonical immunity-type layer covering:

```text
schools
exact CC mechanics
spell
cc
all
```

Implemented in `18c1f507`:

- added `BROAD_IMMUNITY_TYPES` for `spell`, `cc`, and `all`;
- added one canonical `IMMUNITY_TYPES` registry built from schools, exact CC,
  and broad types;
- deliberately excluded `unknown` because it is a storage fallback, not a
  queryable dimension;
- added `NormalizeImmunityType` and `IsValidImmunityType`;
- routed existing `NormalizeCCImmunityType` through the shared normalizer so
  CC aliases/lower-casing remain unchanged;
- no SavedVariables, query, learning, or macro behaviour changed.

Static diff review completed. Runtime validation is still covered by the later
framework regression matrix.

### Step 2 — centralize typed queries — DONE

Implemented in `4241f918` + `97383436`:

- added internal `CheckImmunityType(unit, immunityType)`;
- exact CC input now routes through the typed path;
- CC mechanic checks derived from spell names route through the typed path;
- exact canonical school queries route through the typed path;
- split physical/bleed checks route through the typed path;
- learned school lookup still uses the existing SavedVariables layout;
- TempCC still resolves through existing `CheckCCImmunity`;
- broad `spell`, `cc`, and `all` deliberately return false;
- Banish remains on its existing special live-state path;
- legacy `unknown` school/spell-specific records remain on the old compatibility
  path because `unknown` is storage, not a canonical dimension.

No public conditional grammar, learning path, or SavedVariables schema changed.

Static diff review completed. A local Lua compiler/runtime was not available in
the tool environment, so in-game/runtime validation remains part of the later
framework regression matrix.

### Step 3 — separate source from type — DONE

Implemented in `0b4e081e`.

The query framework now separates the immunity dimension from its source using
optional second/third return values:

```text
boolean, source, detail
```

Existing boolean callers remain compatible.

Current source vocabulary:

```text
recorded
    permanent SavedVariables fact
    current storage cannot distinguish automatic learning from manual creation

conditional
    recorded immunity currently active because its recorded buff is present

temporary_aura
    reserved for Step 4 typed immunity auras

temporary_cc
    curated encounter-specific TempCC rule

special
    bespoke live state, currently Banish

reflection
dr
death
debuff_cap
    explanation/guard sources for later learning-path integration
```

Current query integration:

- TempCC returns `temporary_cc` plus the matching aura ID;
- permanent exact CC/school records return `recorded`;
- buff-conditioned exact CC/school records return `conditional` plus buff name;
- Banish now enters typed school queries as `special` plus aura ID;
- public boolean behaviour is preserved;
- broad `spell` / `cc` / `all` remain inert;
- `IMMUNITY_GUARD_AURA_IDS` is unchanged and remains Step 4.

No persistence format or learning behaviour changed.

### Step 4 — replace the flat guard with `IMMUNITY_AURAS` — DONE

Implemented in `3bdeb163`.

The flat `IMMUNITY_GUARD_AURA_IDS` table is gone. It is now:

```lua
IMMUNITY_AURAS = {
    all = { ... },
    spell = { ... },
    physical = { ... },
    reflect = { ... },
}
```

Implementation details:

- all previously curated IDs were transferred exactly once;
- no new aura IDs were added;
- ranks / NPC variants / alternate applications remain simple one-line
  `[spellID] = true` additions;
- `GetActiveImmunityAura(unit, auraType)` performs direct numeric by-ID
  `C_UnitAuras` lookup;
- no aura-slot scan or polling was added;
- `HasImmunityGuardAura(unit)` remains as the compatibility learning guard and
  treats any `all`, `spell`, `physical`, or `reflect` match as
  inconclusive;
- the compatibility guard can also return bucket + spell ID for later source
  plumbing, while old callers continue consuming only the aura name;
- typed queries now report exact live `all`, `spell`, or `physical`
  aura buckets as `temporary_aura` plus aura ID;
- cross-type composition is deliberately not active yet;
- `reflect` is never a queryable immunity type;
- TempCC remains separate.

Static review confirmed the old flat-table symbol no longer exists and every
previous guard ID occurs exactly once in the new table. No Lua interpreter is
available in the tool environment, so runtime validation remains outstanding.

### Step 5 — integrate TempCC with typed queries — DONE

Verified against current runtime; **no runtime change was required**.

Current path:

```text
CheckImmunityType(unit, exactCC)
 -> CheckCCImmunity(unit, exactCC)
 -> IsTemporarilyCCImmune(unit, exactCC)
 -> true, temporary_cc, auraID
```

The ordering is important:

- exact canonical CC mechanics are checked before broad types;
- `cc` is a broad type, not an exact CC mechanic;
- `spell` and `all` have no relationship to TempCC;
- therefore one TempCC mechanic cannot promote any broad category.

Verified Sartura semantics from the code path during aura 26083:

```text
stun  -> true  (source: temporary_cc, detail: 26083)
cc    -> false
spell -> false
all   -> false
```

Also verified:

- `TEMP_CC_IMMUNITIES` remains `creature entry -> aura ID -> exact mechanic`;
- TempCC is not stored in SavedVariables;
- TempCC is not flattened into `IMMUNITY_AURAS`;
- delayed missing-CC verification still calls `IsTemporarilyCCImmune` before
  permanent learning;
- direct Nampower `SPELL_MISS -> IMMUNE` still calls
  `IsTemporarilyCCImmune` before permanent learning;
- no other automatic TempCC-learning guard exists or was removed.

This is static verification only. Live Sartura validation remains outstanding.

Step 5 verification was repeated against head `a7ce4661`: the exact CC table
does not contain broad `cc`, the Sartura rule is still only
`15516 -> 26083 -> stun`, neither TempCC definition nor helper writes
`CleveRoids_ImmunityData`, and the two automatic-learning guards remain in
the delayed verifier and direct Nampower miss path.

### Step 6 — define composition / precedence — DONE

Implemented in `af3dc511`.

Composition is now split into two layers:

```text
CheckExactImmunityType
    checks only the requested dimension/source

CheckImmunityType
    applies broader blockers in deterministic precedence
```

Source precedence is:

```text
requested exact dimension
 -> broad cc (only when requested type is an exact CC mechanic)
 -> all
```

Current semantics:

- exact CC mechanics still resolve TempCC / recorded exact immunity first;
- broad `cc` can block every exact CC mechanic once a direct `cc` source
  exists;
- `all` blocks every canonical immunity dimension except that querying
  `all` only checks `all` itself;
- school queries do not automatically imply `spell`;
- `spell` queries do not automatically imply a school;
- action-level combinations such as HoJ = holy + spell + stun + cc + all are
  deferred to Step 7/8;
- `reflect` never participates in immunity composition;
- TempCC remains one-way exact: temporary `stun` can satisfy a `stun` query
  but cannot create `cc`;
- Banish remains a special exact-school source and does not become `all`.

The exact-first order preserves the most specific provenance for later debug
output. For example Sartura Whirlwind reports `temporary_cc / 26083` for a
stun query rather than a broader aura if both are present.

Static diff review completed. No Lua interpreter is available in the tool
environment, so runtime validation remains outstanding.

### Step 7 — implement action/spell dimension classification — DONE

Implemented in `7ec46616`, with wording cleanup in `3e7eccb5`.

Research conclusion:

- vMaNGOS checks `IsImmuneToSpell` before the later hit table;
- school immunity is matched against the spell's school mask;
- broad magic immunity therefore follows the six non-physical schools:
  Holy, Fire, Nature, Frost, Shadow, Arcane;
- `DmgClass` is not the classifier for broad magic immunity;
- physical abilities remain outside broad `spell` even though they are Spell.dbc
  rows;
- Blackwing Spellbinder's observed split (Cheap Shot/Charge land, HoJ/grenades
  IMMUNE) fits this school-based model;
- Anti-Magic Shield likewise uses a six-school immunity mask.

Working HoJ invariants remain:

```text
Hammer of Justice
    holy + spell + stun + cc + all
    broad magic immunity can block it before any later hit-roll logic
    stun immunity can also block it independently
```

Implemented helper:

```lua
CleveRoids.GetSpellImmunityDimensions(spellID)
```

It returns:

1. a membership set, and
2. an ordered narrow-to-broad dimension list.

Expected examples:

```text
Hammer of Justice -> holy, spell, stun, cc, all
Cheap Shot        -> physical, stun, cc, all
Charge Stun       -> physical, stun, cc, all
Fireball          -> fire, spell, all
```

Bleeds are represented as Physical DBC school plus the additional SCRM
`bleed` dimension when the Vanilla bleed mechanic is present.

Step 7 does **not** change public `[immune]` behaviour yet. Routing spell-name
queries through the full dimension list is Step 8.

Live validation is deferred. Static/code/data evidence is sufficient to continue
the framework sequence for now.

### Step 8 — route existing public checks through dimensions

Once action classification is sound:

- spell-name `CheckImmunity` checks all relevant dimensions
- exact `[immune:stun]` still means exact stun immunity
- exact school queries still mean that school
- bare spell-aware `[immune]` can use the action's complete dimension set

Do not add new conditionals yet.

### Step 9 — add reason/debug visibility

Before learning is expanded, expose enough debug information to prove which
dimension/source blocked an action.

Desired debugging quality:

```text
HoJ -> immune: spell (Anti-Magic Shield 7121)
Cheap Shot -> no matching immunity
HoJ -> immune: temporary stun (Sartura Whirlwind 26083)
```

Exact wording is not important; source/type visibility is.

### Step 10 — regression validation

Framework validation before learner work:

- [ ] existing learned fire/frost/etc. immunity still works
- [ ] existing exact CC immunity still works
- [ ] CC aliases still normalize identically
- [ ] Sartura temporary stun behaviour is unchanged
- [ ] Divine Shield / Divine Protection / Ice Block resolve as `all`
- [ ] Anti-Magic Shield resolves as `spell`, not `all`
- [ ] Blessing of Protection resolves as `physical`, not `spell`
- [ ] reflection protects learning but is not reported as immunity
- [ ] Banish behaviour is preserved or cleanly absorbed by the new framework
- [ ] direct Nampower learning guard still works
- [ ] delayed verification guard still works
- [ ] DR guard still works
- [ ] no new SavedVariables schema
- [ ] no new polling / high-frequency scan

Only after this matrix passes should the comparative learner start.

---

## Invariants

Do not break these while refactoring:

1. **No false permanent learning from temporary state.**
2. **TempCC is mechanic-specific.**
3. **Reflection is not immunity.**
4. **Spell immunity is not school immunity.**
5. **Spell immunity is not exact CC immunity.**
6. **Broad CC immunity is not a collection of observed exact CC failures.**
7. **Absolute immunity is distinct from spell and physical protection.**
8. **Numeric IDs drive aura decisions; names are display/debug only.**
9. **ClassicAPI is available; do not add alternate aura implementations.**
10. **No new polling. Reuse existing event paths.**
11. **Do not silently rewrite existing user immunity records.**
12. **Public macro syntax stays stable during the framework stage.**

---

## Deferred until framework completion

Do not start these yet:

- comparative `ObserveImmunity(...)` learner
- candidate / disproved / confirmed evidence state
- successful-hit elimination logic
- broad-immunity promotion thresholds
- learner evidence persistence
- SavedVariables schema changes
- automatic removal of inferred records
- `[immune:spell]`, `[immune:cc]`, `[immune:all]` syntax decisions
- aliases such as `spellimmune`
- generalized inference from Blackwing Spellbinder observations

The Blackwing Spellbinder research needed to correctly classify `spell`
delivery belongs to framework Step 7; the **learner** built from those
observations does not.

---

## Completed before this stage

The branch already contains:

- exact CC mechanic learning
- Sap -> Vanilla mechanic 14 / `knockout`
- corrected NPC DR pools and reset window
- corrected Nampower `SPELL_MISS` payload handling
- curated general protection/reflection guard
- Ice Block guard
- Anti-Magic Shield 7121 / 19645 / 24021 guard
- TempCC framework
- Sartura 15516 / Whirlwind 26083 / temporary stun rule
- TempCC protection in both automatic CC-learning paths
- locale-safe numeric TempCC identity
- localized aura-landed verification fixes

Sartura live validation is still outstanding.

---

## Untested / runtime work

Existing branch work still requires live Sartura validation:

```text
clear old learned Sartura stun entry
verify [immune:stun] false before Whirlwind
verify true during Whirlwind
force HoJ and receive IMMUNE
verify no permanent cc_stun is written
verify false again after Whirlwind
verify aura 26083 is visible through ClassicAPI
```

The framework work added after this document will need the Step 10 regression
matrix before learner development begins.

---

## Exact next step

**Step 8: route spell-aware public immunity checks through the dimension helper.**

Use `GetSpellImmunityDimensions(spellID)` for spell-name/bare-action queries so
one action can be blocked by any relevant dimension.

Required behaviour:

```text
Hammer of Justice
    blocked by holy OR spell OR stun OR cc OR all

Cheap Shot
    blocked by physical OR stun OR cc OR all

Charge Stun
    blocked by physical OR stun OR cc OR all

Fireball
    blocked by fire OR spell OR all
```

Preserve exact explicit queries:

- `[immune:stun]` means the stun dimension (with Step 6 broad composition),
  not "every dimension of the currently selected spell";
- `[immune:fire]` remains a fire query;
- no new macro grammar is added.

When routing a spell/action through multiple dimensions, preserve deterministic
reason precedence and do not let `reflect` become immunity.

Do not add comparative learning in Step 8.

After Step 8, update this document before beginning Step 9.

# Temporary CC Immunity and Generalized Immunity Learning

Implemented/current work lives on branch `design/temp-cc-immunity`.

Runtime changes made so far are intentionally confined to `Utility.lua`. This
document is the branch design contract for the existing temporary-CC immunity
microsystem and for the proposed generalized immunity learner.

The structure is intentionally:

1. **Observation** — what the client/server behaviour tells us;
2. **Goals** — what SCRM should be able to represent and infer;
3. **Done** — behaviour already implemented and audited on this branch;
4. **To-Do** — design/implementation/testing that has not been completed.

---

## Observation

### Temporary encounter immunity can look permanent

SCRM learns permanent NPC CC immunity after a CC spell returns `IMMUNE`, with
guards for DR and broad temporary protection effects.

That assumption is wrong for a small class of encounter mechanics where a
specific NPC becomes immune to a specific CC mechanic only while a specific
aura is active.

Confirmed regression case:

```text
Battleguard Sartura
creature entry: 15516
aura/spell:     26083 Whirlwind
temporary CC:   stun
```

vMaNGOS' Sartura script explicitly describes her as stun immune during
Whirlwind and casts spell 26083 for that phase. Historical vMaNGOS data also
removes Sartura's static creature-template stun immunity, matching the intended
behaviour that she is not permanently stun immune.

Without a temporary-state explanation, SCRM can observe a stun returning
`IMMUNE` during Whirlwind and incorrectly record:

```text
Battleguard Sartura -> cc_stun -> permanent
```

That poisons later `[immune:stun]` / `[noimmune:stun]` decisions after the
Whirlwind has ended.

### One `IMMUNE` result can have several valid explanations

A single failed spell does not necessarily identify the immunity category.

For example, Hammer of Justice returning `IMMUNE` could be explained by any
of the following, depending on the target:

```text
stunimmune
ccimmune
holyimmune
spellimmune
immune
temporary encounter immunity
temporary broad protection
```

The current learner is strongest when one event maps cleanly to one exact
mechanic or school. It becomes vulnerable when several independent immunity
dimensions overlap.

The useful distinction is therefore:

```text
Observation
    What actually happened?
    Example: Hammer of Justice returned IMMUNE.

Inference
    Which immunity categories could explain that observation?

Confirmed knowledge
    Which immunity category has enough independent evidence to be used by
    normal [immune] / [noimmune] decisions?
```

Those three concepts should not be collapsed into one write operation.

### Immunity has multiple independent axes

The discussion on this branch has identified these useful immunity dimensions.

#### School-specific immunity

```text
fireimmune
frostimmune
natureimmune
shadowimmune
arcaneimmune
holyimmune
```

SCRM already stores learned school immunity internally as `fire`, `frost`,
`nature`, `shadow`, `arcane`, `holy`, plus existing `physical` and
`bleed` categories.

A school immunity means only that school is blocked.

Example:

```text
fireimmune = true
spellimmune = false

Fireball  -> IMMUNE
Frostbolt -> can land
HoJ       -> can land unless another immunity applies
```

#### Broad spell/magic immunity

Conceptual category:

```text
spellimmune
```

This is distinct from a CC mechanic.

It means that broad magical spell effects are rejected, but a physical/melee
CC can still work.

Important terminology note: in WoW implementation terms many physical
abilities also have Spell.dbc records. `spellimmune` must therefore not be
implemented as "anything with a spell ID". Its exact classification must match
the game's broad magical spell-immunity behaviour.

#### Broad CC immunity

Conceptual category:

```text
ccimmune
```

This means the target is immune to all relevant CC mechanics regardless of
which specific mechanic was attempted.

It is broader than:

```text
stunimmune
fearimmune
rootimmune
knockoutimmune
...
```

but independent from `spellimmune`.

#### Specific CC immunity

Existing exact mechanic categories remain necessary:

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
...
```

The learner must continue to preserve exact mechanic identity rather than
collapsing unrelated mechanics into a broad stun bucket.

#### Absolute immunity

Conceptual category:

```text
immune
```

This represents a true broad state where effectively all relevant attacks or
effects are rejected.

This is different from `spellimmune`, `ccimmune`, or one school immunity.

### Blackwing Spellbinder demonstrates why these axes must stay separate

Blackwing Spellbinder, creature entry 12457, is a useful regression/design
case.

vMaNGOS migration `20231216221145_world.sql` explicitly annotates:

```text
Blackwing Spellbinder (HAS AURAS: Spell Immunity)
```

The same migration removes blanket mechanic-immunity bits for several mechanics
and records observed distinctions for stun behaviour. Its comments list
physical/melee stun examples such as Cheap Shot, Charge Stun, Kidney Shot,
Bash, Revenge Stun, Concussion Blow, Intercept Stun and War Stomp as mechanic
stuns, while Hammer of Justice and grenades are listed among observed
`IMMUNE` stun results.

That gives us the important model:

```text
Blackwing Spellbinder

spellimmune = true
stunimmune  = false

Hammer of Justice -> IMMUNE
Cheap Shot         -> can stun
Charge Stun        -> can stun
```

Therefore a Hammer of Justice `IMMUNE` must not automatically become
`cc_stun = permanent`. Doing so would incorrectly suppress Cheap Shot and
other physical stuns.

The exact Spell Immunity aura ID/effect classification still needs to be
verified before implementing a generic `spellimmune` detector.

### Spell Shield / Anti-Magic-style auras are another motivating case

Some Vanilla NPCs use temporary effects commonly described as Spell Shield or
Anti-Magic Shield which can make them immune to magic/spells without making
them globally CC immune.

The existing branch already has verified Vanilla Anti-Magic Shield variants
(7121, 19645, 24021) in the general immunity-learning guard because those
auras can make magic spells return `IMMUNE`.

Similar names are not sufficient evidence. Absorb shields and
damage-reduction effects are deliberately excluded, including later TBC Spell
Shield 33054, which is damage reduction rather than immunity.

ZG and Stratholme NPC "Spell Shield" examples discussed during design should be
identified by exact Vanilla spell/aura ID and effect before being added to any
typed live-immunity table.

### Comparative observations can resolve ambiguous immunity cheaply

The learner can infer more accurately by comparing events it already sees.

Example sequence:

```text
1. Hammer of Justice -> IMMUNE

possible explanations:
    holyimmune
    spellimmune
    stunimmune
    ccimmune
    immune
```

Then:

```text
2. Charge Stun -> LANDS

disproves:
    stunimmune
    ccimmune
    immune

remaining explanation for HoJ:
    holyimmune OR spellimmune
```

Then:

```text
3. Fireball -> IMMUNE

possible explanations for Fireball:
    fireimmune
    spellimmune
    immune

immune was already disproved.

The common explanation between HoJ and Fireball is now:
    spellimmune
```

A further independent magical school can strengthen the conclusion:

```text
4. Frostbolt -> IMMUNE

HoJ       -> holy or spell
Fireball  -> fire or spell
Frostbolt -> frost or spell

shared explanation:
    spellimmune
```

However, multiple school immunities can masquerade as broad spell immunity:

```text
holyimmune = true
fireimmune = true
```

would explain HoJ + Fireball without requiring `spellimmune`.

Therefore two or more `IMMUNE` observations must not be treated as automatic
proof of broad immunity merely because they share a possible explanation.

### Successful hits are strong negative evidence

A successful effect is often more useful than another `IMMUNE` result because
it disproves broad categories.

Examples:

```text
Frostbolt HITS
    -> NOT spellimmune
    -> NOT frostimmune
    -> NOT immune

Cheap Shot HITS
    -> NOT stunimmune
    -> NOT ccimmune
    -> NOT immune

Fear HITS
    -> NOT fearimmune
    -> NOT ccimmune
    -> NOT immune
```

Successful observations should therefore be able to eliminate unresolved
candidate explanations.

They must not blindly delete deliberately persisted user data until the
interaction between learned facts, candidates, and manual records is explicitly
designed.

### Temporary explanations must win before permanent inference

A known live temporary state is an explanation for an `IMMUNE` result and
must be evaluated before generalized permanent inference.

Examples include:

- Sartura's Whirlwind temporary stun immunity;
- Divine Shield / Divine Protection / Ice Block;
- Anti-Magic Shield;
- Blessing of Protection;
- spell-reflection effects;
- DR;
- recent target death;
- debuff-cap ambiguity.

An event explained by one of those states must not reinforce permanent
`stunimmune`, `holyimmune`, `spellimmune`, `ccimmune`, or `immune`
candidates.

### The required metadata is already available

The generalized learner should not require another scanner, polling loop, aura
sweep, or high-frequency `OnUpdate`.

The current SCRM paths already process or derive:

- explicit Nampower `SPELL_MISS -> IMMUNE`;
- successful `SPELL_GO` observations;
- confirmed debuff/CC applications;
- spell ID;
- DBC spell school;
- exact CC mechanic;
- target GUID/name;
- DR grouping;
- current temporary-immunity guard state.

For a spell such as Hammer of Justice, the learner can already derive
conceptually:

```text
school = holy
CC     = stun
magic  = yes
```

For Charge Stun:

```text
school = physical
CC     = stun
magic  = no
```

For Fireball:

```text
school = fire
CC     = none
magic  = yes
```

The additional runtime work should therefore be small table/bitset operations
at event points SCRM already visits.

---

## Goals

### Preserve the narrow TempCCImmune contract

The existing TempCCImmune microsystem answers exactly one question:

```text
Is this creature temporarily immune to this CC mechanic because a curated
encounter aura is active right now?
```

It must:

- key rules by creature entry ID, never NPC name;
- key temporary state by exact aura spell ID;
- specify the exact CC mechanic(s) suppressed by that aura;
- affect only matching CC mechanics;
- be usable by both macro immunity checks and immunity-learning guards;
- write nothing to `CleveRoids_ImmunityData`;
- remain small, explicit and easy to audit;
- live in the existing immunity utility code unless it grows enough to justify
  extraction later.

It must not:

- disable all immunity learning while any listed aura is active;
- infer encounter behaviour from arbitrary DBC aura effects;
- treat a listed aura as generic invulnerability;
- special-case NPC names;
- silently add or remove learned permanent immunity records.

### Generalize immunity without flattening different causes

The future immunity model should be able to represent independent facts such
as:

```text
school immunity
    fireimmune
    frostimmune
    natureimmune
    shadowimmune
    arcaneimmune
    holyimmune

broad spell/magic immunity
    spellimmune

broad CC immunity
    ccimmune

specific CC immunity
    stunimmune
    fearimmune
    rootimmune
    ...

absolute immunity
    immune
```

These are overlapping axes, not a simple inheritance tree.

For example:

```text
spellimmune = true
stunimmune  = false
```

is valid and is the Blackwing Spellbinder use case.

Likewise:

```text
stunimmune  = true
spellimmune = false
ccimmune    = false
```

is valid for Sartura during Whirlwind.

### Separate observation, candidate inference, and confirmed knowledge

The desired learner states are conceptually:

```text
unknown
candidate
confirmed
```

with negative evidence able to disprove candidate explanations.

An `IMMUNE` event should first describe what could explain the result.

A later successful observation should be able to eliminate incompatible
candidate explanations.

Only sufficiently confirmed knowledge should affect normal permanent
`[immune]` / `[noimmune]` behaviour.

Exact persistence semantics for candidate evidence are still to be designed.

### Prefer the narrowest explanation supported by evidence

The system should not learn `immune` when `spellimmune` explains the
evidence, and should not learn `spellimmune` when a single school immunity is
the only demonstrated fact.

Likewise, a magical stun returning `IMMUNE` should not become
`stunimmune` if a physical stun later proves that stun itself works.

### Use successful observations as eliminators

The inference system should consume positive land/hit evidence from existing
event paths, not only failures.

A successful spell/effect can invalidate broad candidates and improve the
quality of later learning without additional scanning.

### Keep temporary/current-state immunity separate from permanent learning

Known temporary aura state remains read-only/current-state information.

Temporary state can answer a live macro query and can explain a failure, but it
must not be persisted as a permanent learned immunity.

### Preserve locale independence

Runtime decisions should continue to use:

- numeric creature entry IDs where curated encounter identity is required;
- numeric spell/aura IDs;
- DBC mechanic/school fields;
- SCRM's canonical internal mechanic tokens.

NPC/spell names should remain comments or debug/display data except where
legacy SavedVariables behaviour explicitly depends on names.

### Keep overhead essentially flat

The generalized learner should reuse existing event dispatch and metadata.

Initial design should require:

- no additional frame scanner;
- no full aura scan;
- no periodic target sweep;
- no new combat-log parser solely for generalized immunity;
- no additional high-frequency `OnUpdate`.

Small per-event candidate updates are acceptable.

---

## Done

### TempCCImmune curated data model

The implemented table shape is:

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

A rule is true only when all three identities match.

For Sartura:

```text
15516 + 26083 + stun -> true
15516 + 26083 + fear -> false
15516 + any other aura + stun -> false
another creature + 26083 + stun -> false
```

This is stricter than a global `auraID -> mechanic` table and prevents an aura
ID from becoming an unintended cross-encounter rule.

### Creature entry identity

The subsystem uses ClassicAPI's `UnitCreatureID(unit)` for stable creature
entry identity.

`UnitCreatureID` resolves normal and extended unit tokens, including raw GUID
tokens, and returns the creature-template/NPC entry directly. This keeps GUID
layout and client/server GUID-prefix details out of TempCCImmune.

The implementation hides that dependency behind a small creature-entry helper.
The rest of TempCCImmune does not parse localized NPC names.

ClassicAPI encapsulates the supported normal creature GUID forms, including the
forms historically described as `F130` / `F530`; pet GUID forms such as
`F140` / `F540` are not treated as creature-template identities for these
rules.

`UnitCreatureID` was added to ClassicAPI before the v1.15.8 minimum already
required by SCRM.

### Aura lookup

Once a creature entry matches a curated rule, only the aura IDs listed for that
creature are queried.

Implemented flow:

```text
IsTemporarilyCCImmune(unit, ccType)
    -> resolve creature entry
    -> find TEMP_CC_IMMUNITIES[entry]
    -> query only the listed aura IDs
    -> return true only when an active listed aura contains ccType
```

The implementation uses:

```lua
C_UnitAuras.GetUnitAuraBySpellID(unit, auraID)
```

ClassicAPI's by-ID lookup searches both helpful and harmful aura ranges when no
filter is supplied. The curated temporary-immunity table therefore does not
need to classify a rule aura as a buff or debuff.

No target-wide aura classification scan is performed.

### Interaction with `CheckCCImmunity`

Temporary immunity is a current-state fact and is checked alongside learned
immunity.

Implemented behaviour is conceptually:

```text
CheckCCImmunity(unit, ccType)

1. IsTemporarilyCCImmune(unit, ccType)?
      yes -> true
2. existing learned permanent / conditional immunity logic
3. otherwise false
```

For Sartura, assuming no stale permanent SavedVariables record:

```text
outside Whirlwind -> [immune:stun] = false
during Whirlwind  -> [immune:stun] = true
after Whirlwind   -> [immune:stun] = false
```

A stale permanent SavedVariables entry from an older build can still override
the post-Whirlwind state through existing learned-immunity behaviour.
TempCCImmune intentionally does not silently delete user data.

### Interaction with automatic immunity learning

TempCCImmune guards both current automatic CC-learning routes:

1. explicit Nampower `SPELL_MISS -> IMMUNE`;
2. delayed CC verification where the expected debuff never appeared.

Implemented concept:

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

There is no broad `IsAnyTempCCImmune()` switch disabling all learning for the
target.

### Relationship to the general immunity guard

TempCCImmune remains separate from the curated general
protection/reflection-learning guard.

The two concepts are:

```text
general immunity-guard aura
    makes a failed spell/debuff observation inconclusive while a known
    protection or reflection effect is active

TempCCImmune rule
    explains only the explicitly listed CC mechanic for one creature while
    one explicitly listed aura is active
```

Sartura's Whirlwind is therefore not in the general immunity-guard table.
Putting it there could suppress learning of unrelated real immunities observed
during Whirlwind.

### General immunity guard audit

The September 2026 audit replaced broad DBC-mechanic/invulnerability reasoning
with curated `IMMUNITY_GUARD_AURA_IDS`.

The guard currently includes explicitly verified categories such as:

- full protection:
  - Divine Protection;
  - Divine Shield;
  - Ice Block;
- Vanilla Anti-Magic Shield magic-immunity family:
  - 7121;
  - 19645;
  - 24021;
- Blessing of Protection physical protection;
- explicit spell-reflection and school-reflector effects.

Unrelated effects were removed.

Same-name-but-non-immune shields are excluded. In particular, absorb shields
are not treated as immunity, and later TBC Spell Shield 33054 is documented as
damage reduction rather than immunity.

The current table is intentionally conservative and is a **learning guard**,
not yet a typed live `spellimmune` / `immune` state provider.

### First curated TempCCImmune rule

Implemented rule:

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

The rule is curated encounter knowledge, not generic DBC inference.

### Implemented integration footprint

Current implementation contains:

- `TEMP_CC_IMMUNITIES` in `Utility.lua`;
- a creature-entry resolver backed by ClassicAPI `UnitCreatureID(unit)`;
- `IsTemporarilyCCImmune(unit, ccType)`;
- curated by-ID aura lookup through
  `C_UnitAuras.GetUnitAuraBySpellID`;
- a live-state check in `CheckCCImmunity`;
- a matching-mechanic guard in delayed missing-debuff immunity learning;
- a matching-mechanic guard in Nampower `SPELL_MISS -> IMMUNE` learning.

No new runtime Lua module was added.

No SavedVariables format change was introduced.

### Exact CC mechanic and DR audit already completed

The branch also contains the preceding CC/immunity corrections which
TempCCImmune depends on:

- Vanilla 1.12 Sap handling is corrected;
- client `SpellMechanic.dbc` mechanic 14 is canonicalized as
  `knockout`, with `sap` retained as a compatibility alias;
- the incorrect client mechanic-30 distinction was removed while documenting
  the broader server-side `MECHANIC_SAPPED = 30` enum;
- learned CC immunity records the exact immunity mechanic rather than a coarse
  stun bucket;
- DR protection is keyed to the real Vanilla NPC-applicable DR groups rather
  than permanent coarse counters.

### Locale and portability audit

TempCCImmune makes no runtime decision from localized game text:

- creature identity is numeric via ClassicAPI `UnitCreatureID(unit)`;
- aura identity is numeric via `C_UnitAuras.GetUnitAuraBySpellID`;
- the table stores SCRM's canonical mechanic token, for example `stun`;
- NPC/aura names in the table are comments only;
- `C_Spell.GetSpellName` is used only for debug/display output.

The subsystem therefore does not require English NPC names or English spell
names.

The related aura-landed verifier used by hidden Pounce/bleed tracking was also
made locale-safe during the audit. It now derives patterns from Blizzard's
localized `AURAADDEDOTHERHARMFUL` /
`AURAAPPLICATIONADDEDOTHERHARMFUL` GlobalStrings and resolves relevant
pending effects from numeric spell IDs and mechanics.

The previous hard-coded English `"is afflicted by"` gate and English
spell-name lookup table were removed.

Duplicate localized aura parsing was removed/hardened, and split-CC name
fallback was localized.

Other older combat-log fallbacks elsewhere in SCRM still contain language
patterns for unrelated features. They are outside TempCCImmune and should be
audited separately rather than expanding this microsystem.

### Learning-path parity audit

Both automatic CC-immunity learning paths consult the same
`IsTemporarilyCCImmune(unit, immunityType)` helper:

1. Nampower `SPELL_MISS -> IMMUNE`;
2. delayed verification when the expected CC aura did not appear.

A matching temporary rule suppresses learning only for the matching mechanic.
It does not disable unrelated CC or school-immunity learning while the aura is
active.

### Persistence and stale-data behaviour

TempCCImmune writes nothing to SavedVariables and introduces no SavedVariables
schema change.

A stale permanent immunity learned by an older build remains authoritative
after the temporary aura ends until removed through existing cleanup behaviour
or explicitly with:

```text
/cleveroid removeccimmune Battleguard Sartura stun
```

The microsystem intentionally does not silently rewrite existing user data.

### Conservative failure mode

The first rule is deliberately specific to:

```text
creature entry 15516 + aura 26083 + stun
```

If a server implements the encounter differently, changes the aura spell ID, or
does not expose that aura to the client, the rule simply fails to match and the
existing immunity-learning logic continues.

That can re-expose the original false-learning behaviour on that server, but it
does not broaden the rule to unrelated creatures or mechanics.

New server or encounter variants should be added as separately verified curated
entries rather than inferred dynamically.

### Current audit conclusion

The implemented TempCCImmune subsystem is narrow, locale-independent,
read-only, and mechanic-specific.

It introduced no new English-name dependency, broad immunity suppression,
generic DBC inference, SavedVariables schema change, or persistence coupling.

The remaining TempCCImmune work is live validation.

---

## To-Do

### 1. Live-validate the existing Sartura implementation

Before testing, remove any previously learned false permanent stun entry:

```text
/cleveroid removeccimmune Battleguard Sartura stun
```

Then validate:

- [ ] Before Whirlwind, `[immune:stun]` is false.
- [ ] During Whirlwind, `[immune:stun]` is true.
- [ ] During Whirlwind, the normal HoJ macro using `[noimmune:stun]`
      refuses to cast.
- [ ] During that same Whirlwind, force a plain HoJ without the immunity
      conditional.
- [ ] Confirm the server returns `IMMUNE`.
- [ ] Confirm that `IMMUNE` does not create a permanent `cc_stun`
      SavedVariables entry.
- [ ] After Whirlwind ends, `[immune:stun]` returns false.
- [ ] After Whirlwind, the normal HoJ macro becomes eligible again.
- [ ] Confirm a later successful stun can land normally.
- [ ] Confirm an unrelated CC `IMMUNE` during Whirlwind is not suppressed
      unless that mechanic is explicitly listed for the aura.
- [ ] Confirm explicit Nampower miss learning and delayed missing-debuff
      learning both obey the same TempCCImmune rule.
- [ ] Confirm existing DR safeguards continue unchanged.
- [ ] Confirm existing generic protection/invulnerability handling continues
      unchanged.
- [ ] Confirm no TempCCImmune state is persisted to SavedVariables.

The runtime confirmation still specifically needs to prove that Sartura's 26083
aura is visible through the client's aura API during Whirlwind.

### 2. Preserve the curated-rule admission standard

Only add a new TempCCImmune rule when all of these are known:

- [ ] exact creature entry ID;
- [ ] exact active aura spell ID;
- [ ] exact CC mechanic(s) made temporarily immune;
- [ ] evidence that the immunity is temporary and tied to that aura.

Preferred style remains:

```lua
[creatureEntry] = { -- NPC Name
    [auraSpellID] = {
        stun = true, -- Aura Name: why this mechanic is temporarily immune
    },
},
```

Do not add an entry merely because an `IMMUNE` event was observed.

First exclude:

- permanent creature immunity;
- DR;
- death;
- generic invulnerability/protection;
- reflection;
- debuff-cap ambiguity;
- other existing learning safeguards.

### 3. Define the generalized immunity vocabulary precisely

Design and document exact semantics for:

- [ ] `fireimmune`;
- [ ] `frostimmune`;
- [ ] `natureimmune`;
- [ ] `shadowimmune`;
- [ ] `arcaneimmune`;
- [ ] `holyimmune`;
- [ ] `spellimmune`;
- [ ] `ccimmune`;
- [ ] absolute `immune`;
- [ ] existing exact CC immunity categories;
- [ ] existing `physical` and `bleed` immunity handling.

Decide whether those names are:

1. internal conceptual/category names only;
2. user-visible conditional tokens;
3. aliases over the existing `[immune:<type>]` syntax;
4. some combination of the above.

Do not change macro syntax until that mapping is explicitly chosen.

### 4. Define `spellimmune` by game behaviour, not by the existence of a spell ID

This is critical because physical/melee abilities are also represented by
Spell.dbc records.

The classifier must answer the practical distinction demonstrated by Blackwing
Spellbinder:

```text
HoJ / magical spell effect -> blocked
Cheap Shot / physical stun -> not blocked
Charge Stun / physical stun -> not blocked
```

Tasks:

- [ ] identify the exact Vanilla Spell Immunity aura/effect used by Blackwing
      Spellbinder;
- [ ] verify whether the correct primitive is a school-immunity mask, aura
      effect, spell attribute, or another DBC/server concept;
- [ ] identify exact Vanilla Spell Shield examples in ZG and Stratholme;
- [ ] verify their spell/aura IDs and actual immunity effect;
- [ ] keep absorb or damage-reduction shields out of `spellimmune`.

### 5. Split the existing general immunity guard into typed live explanations

The current `IMMUNITY_GUARD_AURA_IDS` intentionally lumps several temporary
causes together because all of them mean "do not learn this failure as
permanent".

That is adequate as a learning guard but insufficient for a generalized live
immunity model.

Design whether it should become typed data such as:

```text
FULL_IMMUNITY_AURAS
SPELL_IMMUNITY_AURAS
PHYSICAL_IMMUNITY_AURAS
REFLECTION_AURAS
```

or an equivalent single typed table.

Requirements:

- [ ] preserve the existing no-false-learning behaviour;
- [ ] do not make reflection equivalent to immunity;
- [ ] distinguish broad magic/spell protection from absolute immunity;
- [ ] distinguish physical protection from spell immunity;
- [ ] keep TempCCImmune separate and mechanic-specific;
- [ ] keep lookup curated and by numeric aura ID.

### 6. Introduce an observation layer before permanent writes

Design one small entry point, conceptually:

```lua
ObserveImmunity(target, spellID, result)
```

It should receive facts from event paths SCRM already handles rather than
creating new scanners.

For an `IMMUNE` observation, derive the set of plausible explanations from
existing spell metadata.

For a successful hit/land observation, derive which broad/specific candidates
that success disproves.

Tasks:

- [ ] define the exact observation structure;
- [ ] define target identity/keying;
- [ ] define the spell metadata cached/reused by the observation;
- [ ] ensure temporary-state guards run before candidate reinforcement;
- [ ] ensure DR/death/debuff-cap ambiguity cannot reinforce permanent
      candidates;
- [ ] keep event work to small table/bit operations.

### 7. Add candidate/disproved/confirmed inference without eager persistence

Conceptual states:

```text
unknown
candidate
confirmed
```

Design requirements:

- [ ] one ambiguous `IMMUNE` must not immediately become several permanent
      immunity records;
- [ ] successful observations can eliminate incompatible candidates;
- [ ] candidate evidence from distinct schools can reinforce
      `spellimmune`;
- [ ] one successful magical school disproves broad `spellimmune`;
- [ ] one successful CC mechanic disproves `ccimmune`;
- [ ] one successful stun disproves `stunimmune`;
- [ ] one successful relevant effect disproves absolute `immune`;
- [ ] evidence explained by temporary state does not enter the candidate model;
- [ ] manual/user-created records are not silently removed by inferred
      negative evidence.

### 8. Define safe confirmation rules

Do not simply use "two immune events means broad immunity".

For example:

```text
HoJ IMMUNE + Fireball IMMUNE
```

can mean:

```text
spellimmune
```

but can also mean:

```text
holyimmune + fireimmune
```

The confirmation algorithm therefore needs explicit safeguards.

Possible direction to evaluate:

- [ ] require independent schools before considering broad `spellimmune`;
- [ ] prefer a direct known typed aura when available;
- [ ] use successful school observations to eliminate broad candidates;
- [ ] decide whether broad categories are ever inferred solely from combat
      outcomes, or require stronger/direct evidence;
- [ ] prefer the narrowest explanation that accounts for all observations;
- [ ] avoid promoting a broad category when multiple narrow confirmed facts
      explain the same evidence.

### 9. Define how confirmed knowledge affects spell decisions

For a magical CC spell such as Hammer of Justice, the final decision can
conceptually consider:

```text
absolute immune?
spellimmune?
ccimmune?
stunimmune?
holyimmune?
temporary matching immunity?
```

For a physical stun such as Cheap Shot:

```text
absolute immune?
ccimmune?
stunimmune?
physical immunity/protection?
```

`spellimmune` must not suppress a physical stun merely because the ability
has a Spell.dbc record.

Tasks:

- [ ] define query precedence;
- [ ] define interaction between school and mechanic facts;
- [ ] define exact behaviour of bare `[immune]`;
- [ ] define exact behaviour of typed immunity conditionals;
- [ ] keep live temporary state and learned permanent state distinguishable in
      debug output.

### 10. Reuse existing events; do not add polling overhead

Implementation should preferentially hook the observation/inference updates
into existing paths:

- [ ] Nampower `SPELL_MISS -> IMMUNE`;
- [ ] successful `SPELL_GO`;
- [ ] confirmed CC/debuff landed paths;
- [ ] existing delayed verifier when necessary.

Explicit non-goals for the first implementation:

- [ ] no new aura scanning frame;
- [ ] no target polling loop;
- [ ] no high-frequency `OnUpdate`;
- [ ] no duplicate combat-log parser;
- [ ] no whole-aura DBC classification pass.

### 11. Build a generalized validation matrix before enabling permanent inference

At minimum cover:

#### Blackwing Spellbinder

- [ ] verify exact creature entry 12457 behaviour on the target server;
- [ ] HoJ returns `IMMUNE`;
- [ ] Cheap Shot can land;
- [ ] Charge Stun can land;
- [ ] a non-Holy magical school returns `IMMUNE`;
- [ ] learner does not create permanent `cc_stun`;
- [ ] learner converges on the intended broad spell-immunity explanation only
      when evidence is sufficient.

#### Single-school-immune NPC

- [ ] one school returns `IMMUNE`;
- [ ] another magical school lands;
- [ ] broad `spellimmune` is disproved;
- [ ] only the demonstrated school is learned.

#### Broad CC-immune NPC

- [ ] different delivery methods for different CC mechanics fail;
- [ ] ordinary non-CC spells can still land;
- [ ] `ccimmune` is distinguishable from `spellimmune`.

#### Absolute-immunity state

- [ ] physical and magical attacks/effects fail while the state is active;
- [ ] live `immune` is true;
- [ ] no permanent broad immunity is learned from a temporary absolute aura.

#### Temporary spell/magic immunity

- [ ] identify a verified Vanilla Spell Shield / Anti-Magic-style NPC aura;
- [ ] magical effects fail while active;
- [ ] physical effects still work where appropriate;
- [ ] no permanent school or broad spell immunity is learned solely from that
      temporary aura.

#### Sartura

- [ ] retain all TempCCImmune checks from the first validation section;
- [ ] ensure generalized inference does not regress the matching-mechanic
      temporary explanation.

### 12. Decide persistence only after inference semantics are stable

Current TempCCImmune remains intentionally non-persistent.

For generalized learner evidence, decide separately whether to persist:

- [ ] only confirmed immunity facts;
- [ ] unresolved candidate evidence;
- [ ] negative/disproving observations;
- [ ] confidence/evidence counts;
- [ ] direct known-aura classifications.

Avoid a SavedVariables schema change until the runtime model and migration
behaviour are explicit.

Historical SavedVariables may also contain legacy `cc_sap` data. Current
learning canonicalizes Sap to `cc_knockout`. No automatic migration has been
added because silent rewriting of user immunity data is intentionally avoided.

### 13. Deferred/low-priority follow-ups

These remain outside the immediate generalized learner implementation:

- [ ] Reflect handling could explicitly cancel matching pending verification at
      the reflect handler; current miss/reason handling already prevents normal
      reflect events from becoming permanent immunity.
- [ ] Older non-TempCC combat-log fallbacks elsewhere in `Utility.lua` still
      contain English phrases, for example fade/resist tracking.
- [ ] The delayed verifier checks TempCC live state at verification time. A
      hypothetical extremely short temporary-immunity aura could end before the
      delayed check when no explicit Nampower miss event is available. Sartura's
      Whirlwind duration makes this irrelevant to the current rule.
- [ ] Extract immunity code to a separate Lua module only if this design grows
      enough to justify the additional module boundary.

### 14. Implementation footprint target

The existing TempCCImmune footprint should remain:

- one curated `TEMP_CC_IMMUNITIES` table;
- one creature-entry resolver;
- one `IsTemporarilyCCImmune(unit, ccType)` helper;
- one call from `CheckCCImmunity`;
- one guard in each automatic CC-immunity learning route.

The generalized learner should be added with the smallest practical extension
to the existing immunity utility path.

The preferred direction is a small observation/inference helper plus compact
per-NPC evidence state, not another subsystem that independently watches the
world.

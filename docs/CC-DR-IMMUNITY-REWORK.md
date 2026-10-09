# CC, DR and Immunity Rework

Development/status document for the SCRM immunity work on
`design/temp-cc-immunity`.

This file records only the fork-specific immunity work that differs from or
extends the upstream baseline. It is intentionally a concise recovery document,
not a chronological development log.

## Documentation and branch rules

- `main` mirrors `brues-code/SuperCleveRoidMacros`.
- `docs/CC-IMMUNITY-DR.md` and `docs/CLASSICAPI-TODO.md` are upstream baseline
  documents and remain unchanged on this branch.
- This file is the single fork-specific immunity design/status/handoff document.
- Update existing sections when state changes instead of appending chronology.
- Do not create additional immunity development/handoff documents.
- Do not duplicate upstream documentation here unless this branch changes or
  extends the upstream behaviour.

## Recovery snapshot

- Branch: `design/temp-cc-immunity`
- Base: `main`
- Priority learner-fix handoff:
  `e3bb90015f0bd341614fa8bc8d0dd532737531a7`.
- Corrected learner implementation:
  `6df12256213c73cc5236abb716b7ef8e7c692a3a` — direct
  `IMMUNE` is now narrowed before school persistence and `IMMUNE2` is
  non-learning evidence.
- Blackwing Spellbinder HoJ regression fix:
  `43850cb6b3025c09ce480f994fe573dab33f6577` — the final direct-school
  ambiguity gate now retains resolved CC/effect mechanics and falls back to
  ClassicAPI's spell Dispel type when Nampower's raw field is nil.
- TOC version: `@project-version@`
- Latest known-good runtime before this correction:
  `aa2b761d1c45d1a28c8354b2f13f216a21403569` — immunitydebug local-scope
  runtime fix; that build started with no Lua errors.
- Current phase: bounded generalized-backend implementation is complete through
  Slice 7. Slice 8 source/static cross-core validation plus the production
  adapter activation cleanup is complete at
  `e8634814e321a9bff23529875c2504e1fc2ac80e`. The required live runtime
  matrix has not been executed because this development environment does not
  expose a WoW 1.12.1 client/server runtime, so Slice 8 remains runtime-pending
  rather than being claimed complete.
- No runtime testing was performed between implementation slices. Slice 8 has
  now completed repository/source-level validation, but live vMaNGOS and
  Turtle/Octo combat-event replay, visual SCT behavior, and real HearthDB
  reload/persistence still require an actual game runtime.
- The old direct `SPELL_MISS_SELF`, delayed bleed/non-bleed/CC/shared-debuff
  and text-only persistence paths remain only as pre-cutover compatibility code.
  When the generalized backend is active their permanent SavedVariables writes
  are suppressed; storage failure does not reactivate them.
- Blessing of Protection remains typed temporary `physical` immunity.
  Blessing of Freedom is now typed temporary `root` + `snare` immunity.
- Portability target remains one learner for **vMaNGOS and Turtle/Octo**.
  vMaNGOS and the inspected public Turtle-family server source agree on the
  relevant Vanilla 1.12 split: whole-spell immunity is `IMMUNE`, while a
  target whose final effect mask is empty becomes `IMMUNE2`. Slice 8 now
  selects the normalized `vmangos` or `octowow` adapter at production
  startup instead of leaving the generalized learner on the non-inferential
  `portable` development default. Live Turtle/Octo packet/runtime replay is
  still required before cross-core runtime compatibility can be marked PASS.
- Generalized durable learning now records vulnerability facts and unresolved
  hypotheses in HearthDB, confirms an exact permanent immunity only after one
  valid permanent candidate remains, revokes that exact fact on authoritative
  success, and preserves a disproved confirmed immunity with the independent
  dynamic/conditional-suspicion flag. Production immunity queries now consume
  those Mob-ID-keyed facts. Slice 7 exposes those learner transitions and their
  compact provenance for validation. Broad-immunity promotion remains deferred.

## Branch-specific immunity model

The upstream exact-CC model remains the baseline. This branch extends immunity
handling across several independent dimensions.

### Exact learned CC immunity

The current permanent CC learner uses these canonical immunity keys:

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

These are not the complete set of `[cc:*]` conditionals. They are the exact CC
mechanics currently admitted to permanent immunity learning.

Important Vanilla correction on this branch:

```text
sap -> mechanic 14 / knockout
```

`sap` is a compatibility alias, not a separate mechanic-30 immunity bucket.

### School/action immunity

```text
physical
holy
fire
nature
frost
shadow
arcane
```

`unknown` may exist as a storage fallback but is not a queryable immunity
dimension.

### Independent effect immunity

Current independent effect immunity:

```text
bleed
```

The learner design must also preserve these distinctions when supported:

```text
poison != nature
curse  != shadow
disease remains distinct from school immunity
```

School, CC/mechanic and effect-family immunity are orthogonal. Do not infer one
axis from another.

### Broad immunity

```text
spell
cc
all
```

Meanings:

```text
spell
    broad immunity to the six non-physical Vanilla schools:
    Holy, Fire, Nature, Frost, Shadow and Arcane

cc
    broad immunity to CC mechanics

all
    absolute immunity
```

These dimensions remain distinct.

Examples:

```text
Blackwing Spellbinder:
    spell = true
    stun  = false

Sartura during Whirlwind:
    stun  = true temporarily
    spell = false
    cc    = false

Fire-immune NPC:
    fire  = true
    spell = false
```

Spell/action checks consume every relevant dimension.

Examples:

```text
Hammer of Justice
    holy -> spell -> stun -> cc -> all

Frostbolt
    frost -> spell -> all

Cheap Shot
    physical -> stun -> cc -> all
```

The first applicable immunity blocks the action.

## Temporary immunity and non-permanent explanations

A real `IMMUNE` result is not automatically a permanent NPC fact.

### TempCC

Encounter-specific temporary CC immunity is keyed by:

```text
creature entry -> aura spell ID -> exact CC mechanic
```

Current rule:

```text
Battleguard Sartura
creature 15516
Whirlwind 26083
temporary stun immunity
```

TempCC:

- is exact/mechanic-specific;
- participates in live immunity queries;
- guards both automatic CC-learning routes;
- is never persisted to `CleveRoids_ImmunityData`;
- does not imply broad `cc`, `spell` or `all` immunity.

### Temporary protection

Temporary protection is classified by cause rather than collapsed into one
immunity type.

Current framework distinctions include:

```text
full protection     -> all
magic protection    -> spell
physical protection -> physical
reflection          -> non-immunity explanation
```

Examples include Divine Protection/Divine Shield/Ice Block, Anti-Magic Shield,
Blessing of Protection, and curated reflection auras.

Paladin player protections need two explicit temporary meanings:

```text
Blessing of Freedom
    -> temporary movement-impairment immunity
    -> at minimum root + snare for the immunity model
    -> never persisted

Blessing of Protection
    -> temporary physical immunity
    -> never persisted
```

Blessing of Protection is already present in the current typed temporary
`physical` aura bucket. Blessing of Freedom is not yet represented in the
typed temporary-aura model and must be added before the next learner validation
pass.

Player exemption is stronger than these aura-specific explanations:

```text
player target
    -> may still expose live temporary immunity state
    -> must never contribute permanent learned immunity
```

Numeric creature/aura/spell IDs are authoritative. Names are display/debug
information only.

Reflection, DR, death, player temporary protections and similar explanations
may reject a learning event but must never become permanent immunity themselves.

## Learner invariants

Do not change these during the current validation phase:

1. Temporary immunity must not become permanent learned immunity.
2. TempCC is exact/mechanic-specific.
3. Reflection is not immunity.
4. Broad spell immunity is not equivalent to one school immunity.
5. Spell immunity is not exact CC immunity.
6. Broad CC immunity is not inferred merely from several exact-CC failures.
7. Absolute immunity remains distinct from spell and physical protection.
8. Existing user immunity data is not silently rewritten.
9. `CleveRoids_ImmunityData` remains the authoritative real immunity store.
10. No new polling or high-frequency `OnUpdate`.
11. Public immunity macro syntax remains stable during validation.
12. Build the generalized backend only through the bounded slice sequence. Do not
    runtime-test between implementation slices; run the combined conservative
    and generalized validation matrix in Slice 8.
13. Learn only the immunity dimension uniquely proven by the observed effect
    result. If multiple dimensions could explain the same evidence, persist
    nothing.
14. **Player targets are categorically excluded from permanent immunity
    learning.** This applies to every automatic learner route, regardless of
    miss code, aura state, PvP mechanic or temporary protection. Live temporary
    immunity queries may still describe a player's current state.

The direct `SPELL_MISS_SELF` path is authoritative for the spell-level miss
result when available. Only `IMMUNE`/`IMMUNE2` can contribute positive immunity
evidence; ordinary MISS/RESIST/DODGE/PARRY/BLOCK results do not teach permanent
immunity.

A generic `IMMUNE` proves that the action was immune, but not necessarily which
component caused it. School/action, CC/mechanic, bleed and other effect-family
immunities must remain separate unless the observed evidence uniquely identifies
the failed dimension.

Before a real write, the existing learner applies its current safeguards,
including target/spell identity, split-CC handling, death state, TempCC,
temporary protection/reflection, NPC-applicable DR and queryable-target
requirements.

## Immunity diagnostics

### `/cleveroid immunities`

The immunity UI exposes recorded immunity and live temporary state for testing
and management. It does not perform immunity inference.

### `/cleveroid immunitydebug`

`immunitydebug` is a snooper over the real learner. It must not act as a
second learner.

SavedVariable:

```text
CleveRoids_ImmunityDebug
```

The real learner never consumes this journal.

### Schema v1 decoder

Top level:

```text
v   schema version; currently 1
en  immunitydebug enabled: 0/1
ns  addon-load/session counter
e   append-oriented journal records
```

Common record fields:

```text
t   absolute timestamp
s   session ID
r   milliseconds since addon load
e   event code
g   target GUID
m   creature/Mob ID
n   localized NPC name
p   spell ID
sc  raw Spell.dbc school
sm  raw spell mechanic ID
em  raw three-effect mechanic array
```

School values:

```text
0 Physical
1 Holy
2 Fire
3 Nature
4 Frost
5 Shadow
6 Arcane
```

Event codes:

```text
1 learner decision/rejection/exclusion
2 real immunity persistence write
3 real immunity removal
```

Decision records may also contain:

```text
x   raw SPELL_MISS result
q   learner decision
z   rejection/exclusion reason
i   resolved canonical immunity type
dr  learner DR bucket
u   relevant temporary/guard aura ID
c   auxiliary numeric value
h   auxiliary textual/detail value
```

Raw miss values relevant to this journal:

```text
1 MISS
2 RESIST
3 DODGE
4 PARRY
5 BLOCK
6 EVADE
7 IMMUNE
8 IMMUNE2
9 DEFLECT
10 ABSORB
11 REFLECT
```

Decision codes:

```text
0 rejected / ignored
1 accepted CC write path
2 accepted school/general write path
3 explicit exclusion
```

Reason codes:

```text
0 accepted / no rejection
1 missing target or spell identity
2 split-CC safeguard
3 recently dead target GUID
4 target currently dead
5 curated TempCC explains immunity
6 temporary protection/reflection guard makes result inconclusive
7 NPC DR safeguard
8 no queryable target unit
9 REFLECT; explicitly not immunity
10 ambiguous immunity cause / raw result does not identify one safe dimension
11 player target; permanent learning is categorically excluded
```

Mutation records may additionally contain:

```text
k   exact CleveRoids_ImmunityData storage key
b   presence before mutation: 0/1
f   presence after mutation: 0/1
h   optional mutation detail
```

`/cleveroid immunitydebug clear` clears only the diagnostic journal. It must
not clear or alter `CleveRoids_ImmunityData`.

A schema mismatch resets only the debug journal/control structure, never real
immunity data.

## Live validation state

### Sartura TempCC — PASS

Live Hammer of Justice test:

```text
Whirlwind active:
    [noimmune] HoJ is blocked as immune

Whirlwind ends:
    HoJ becomes eligible and fires
```

No unexpected learned-immunity entries were present in the user's dataset at
that point.

This validates the intended player-facing temporary-stun transition.

### Anti-Magic Shield — PARTIAL PASS

Live-tested in Stratholme while Anti-Magic Shield was active:

```text
Gaia Frostbolt + [noimmune] -> blocked
Hammer of Justice + [noimmune] -> blocked
```

This confirms live broad spell protection for at least Frost and Holy actions.

Still useful to verify:

```text
an appropriate Physical action remains eligible while Anti-Magic Shield is active
no permanent Frost/Holy/Stun immunity is written from the temporary state
```

### Player-target immunity leak — FIX LANDED; RUNTIME REPLAY PENDING

Observed micro-anomaly:

```text
player friend
+ Blessing of Freedom active
+ NPC attempts movement CC/root
-> player later appears in permanent immunity data as physical-immune
```

The exact runtime event has not yet been replayed under `immunitydebug`, so
the causal sequence is still labelled **likely**, not proven from a captured
journal.

Static code review proved the original safety hole and the persistence audit
found one additional fallback worth closing:

- bleed/non-bleed delayed verification already rejects `UnitIsPlayer`;
- delayed CC verification already rejects `UnitIsPlayer`;
- shared-debuff verification already rejects `UnitIsPlayer`;
- recorded immunity queries are already NPC-specific;
- the direct `ProcessSpellMissSelf()` learner previously lacked a player
  rejection before permanent learning;
- the legacy text-only school persistence fallback also lacked an explicit
  player rejection.

The landed micro-fix now:

- rejects a queryable player target in `ProcessSpellMissSelf()` before any
  permanent learner decision/write;
- adds the same protection to the legacy text-only school fallback;
- records an `immunitydebug` decision reason of `player target` for the
  direct rejection;
- preserves Blessing of Protection as typed temporary `physical` immunity;
- adds Blessing of Freedom spell ID 1044 as typed temporary `root` and
  `snare` immunity;
- resolves temporary CC aura state before the NPC-only recorded-CC gate, so a
  player may correctly be reported temporarily root/snare immune without ever
  contributing a permanent record.

Implementation commit:

`dcd522e9e66b54a6f38a563184d949f4a640be25`

Required rule:

```text
temporary player immunity is valid live state
permanent player immunity learning is never valid
```

The blocker is fixed in code. The original live anomaly still needs a focused
runtime replay to confirm that no permanent player record is written under
Blessing of Freedom or Blessing of Protection.

### Individual effect-failure evidence audit — REVISED

The evidence audit changed the working model in an important way.

The previous assumption was too broad:

> a generic `SPELL_MISS_SELF IMMUNE` may have been caused by any immune effect
> contained in the spell

Server-side review shows that this is not generally how mixed-effect spells are
reported.

#### ClassicAPI is already a hard requirement

Current brues-code SCRM already requires:

- Nampower v3.0.0+;
- ClassicAPI v1.15.8+;
- UnitXP_SP3.

`ClassicAPI.lua` explicitly describes ClassicAPI as a hard requirement, and
`Core.lua` enforces the minimum version. The learner therefore does not need to
preserve a Nampower-only runtime path.

ClassicAPI may be used freely where it gives stronger evidence.

#### Static spell evidence

ClassicAPI provides substantially better static spell decomposition than the
learner currently uses.

For arbitrary spell IDs it can provide:

- spell school;
- spell-level mechanic;
- individual Spell.dbc effects;
- per-effect mechanics;
- applied aura types;
- spell dispel type such as Magic / Curse / Disease / Poison;
- authoritative target aura state through `C_UnitAuras`.

This is especially useful for mixed spells such as:

- Frostbolt — Frost damage + snare;
- Rake — physical direct hit + bleed aura;
- Hammer of Justice — Holy spell + stun aura;
- poison — Nature school + Poison dispel family;
- curse — usually Shadow school + Curse dispel family;
- disease — school + Disease dispel family.

ClassicAPI does **not** currently provide a runtime event identifying which
individual spell effect failed.

Better spell metadata must therefore not be confused with better failure
evidence.

#### Nampower runtime evidence

Relevant existing Nampower evidence:

##### `SPELL_MISS_SELF`

Provides:

- caster GUID;
- target GUID;
- spell ID;
- miss reason.

For immunity the important values are:

- `IMMUNE`;
- `IMMUNE2`.

It does **not** include an effect index.

##### `SPELL_GO`

Provides spell completion plus hit/miss target counts.

It does not identify which individual effect succeeded or failed.

##### `SPELL_DAMAGE_EVENT_SELF`

Provides strong positive evidence that actual spell damage occurred for a
specific:

- caster;
- target;
- spell ID;
- runtime damage school.

This is stronger than inferring damage success from `SPELL_GO`.

##### `AURA_CAST_ON_OTHER`

This must **not** be treated as authoritative proof that an aura actually
landed.

Nampower generates `AURA_CAST` from:

- the target being present in the `SPELL_GO` hit list;
- the spell's static Spell.dbc aura effects.

It does not first verify that the aura exists in the target's actual aura state.

For mixed spells, a target can therefore count as a spell hit while one
individual aura effect has been rejected.

##### Actual aura state

Stronger positive evidence comes from:

- `DEBUFF_ADDED_*`;
- ClassicAPI `C_UnitAuras`;
- existing delayed aura/debuff verification.

These can prove that an aura actually exists.

Aura absence alone still does not automatically prove why the aura failed.

#### Important server-side finding: effect immunity is often silent

Review of the vMaNGOS spell execution path materially changes the interpretation
of `IMMUNE`.

The server internally tracks an `effectMask` for each target.

For each spell effect:

1. `IsImmuneToSpellEffect()` is checked.
2. If that individual effect is immune, its bit is removed from the target's
   `effectMask`.
3. Other non-immune effects are still allowed to execute.

This means:

> an individual secondary effect may be immune without producing a separate
> spell-miss event.

This matches observed Frostbolt behaviour:

- Frost damage lands;
- Frostbolt slow is immune;
- scrolling combat text does not show a separate `Immune` for the slow.

That observation is consistent with the server implementation.

##### `IMMUNE2`

vMaNGOS writes `IMMUNE2` when the final target `effectMask` is zero as
`SPELL_GO` targets are serialized.

Per-effect immunity is one direct way to reach that state:

1. `IsImmuneToSpellEffect()` rejects an effect;
2. that effect bit is omitted/removed;
3. if no effect bits remain, the outgoing miss condition becomes `IMMUNE2`.

The important correction is that `IMMUNE2` is a **final zero-mask result**, not
an effect-cause code. Other spell-target logic can also clear an effect mask.
Nampower exposes the raw result but no effect index or server-side rejection
reason.

Therefore the direct learner treats `IMMUNE2` as:

```text
no executable effect bits remained
!=
a uniquely identified school / mechanic / aura-state / effect-type immunity
```

No permanent immunity dimension is written from raw `IMMUNE2`.

##### `IMMUNE`

vMaNGOS whole-spell `IMMUNE` is produced by the whole-spell hit path.

The relevant direct causes are:

- spell-school immunity via `IsImmuneToSpell()`;
- damage-school immunity via `IsImmuneToDamage()`;
- spell Dispel-family immunity via `IMMUNITY_DISPEL`;
- spell-level mechanic immunity via `IMMUNITY_MECHANIC`.

For delayed spells, `Spell::CheckAtDelay()` can also change the target result
to `IMMUNE` when `CheckTargetCreatureType()` no longer matches. That is not a
permanent immunity dimension at all, so a spell with a non-zero
`TargetCreatureType` cannot safely teach from a generic `IMMUNE`.

Per-effect mechanic, aura-state and effect-type immunity are handled through
`IsImmuneToSpellEffect()`; on the inspected vMaNGOS path they remove effect
bits rather than directly producing whole-spell `IMMUNE`.

The smallest safe direct rule is therefore:

```text
IMMUNE
+ known DBC school
+ spell-level mechanic == 0
+ Dispel == 0
+ TargetCreatureType == 0
=> school/action is the only represented whole-spell cause
=> learn the literal DBC school

otherwise
=> ambiguous
=> learn nothing
```

School immunity and damage immunity are distinct server checks, but both operate
on the same school mask and map to the same existing SCRM school/action
dimension. They therefore do not create a persistence ambiguity for this narrow
learner.

The direct path intentionally forces the literal Spell.dbc school. This avoids
misclassifying a whole-spell Physical `IMMUNE` as `bleed` merely because the
spell also carries a bleed effect/mechanic.

#### Final vMaNGOS outcome/cause map

The table below means **direct/sufficient path for that observed outcome**.
A cause can coexist with another cause without being the reason encoded by that
outcome.

| Candidate cause | Silent individual effect rejection | `SPELL_MISS_SELF IMMUNE` | `SPELL_MISS_SELF IMMUNE2` |
| --- | --- | --- | --- |
| school immunity | no | yes | not by itself |
| damage immunity | no | yes | not by itself |
| dispel-family immunity | no | yes | not by itself |
| spell-level mechanic immunity | no | yes | not by itself |
| per-effect mechanic immunity | yes | no | yes if all remaining effect bits are removed |
| aura-state immunity | yes | no | yes if all remaining effect bits are removed |
| effect-type immunity | yes | no | yes if all remaining effect bits are removed |

Additional non-immunity ambiguity:

| Cause | Outcome |
| --- | --- |
| delayed target-creature-type mismatch | can be rewritten to `IMMUNE` by `Spell::CheckAtDelay()` |
| any other path that leaves final `effectMask == 0` | can surface as `IMMUNE2`; raw `IMMUNE2` does not identify why |

Concrete vMaNGOS source points audited:

- `Unit::IsImmuneToSpell()`;
- `Unit::IsImmuneToDamage()`;
- `Unit::IsImmuneToSpellEffect()`;
- `Creature::IsImmuneToSpell*()`;
- `SpellCaster::SpellHitResult()`;
- `Spell::AddUnitTarget()`;
- `Spell::CheckAtDelay()`;
- `Spell::WriteSpellGoTargets()`.

Nampower's current SpellRec field map was also checked. The direct classifier
uses existing fields `school`, `mechanic`, `dispel`, and
`targetCreatureType`; no new client dependency is introduced.

#### Representative cases under the finalized direct rule

These are direct-event classifications only. They do not add the deferred
cross-event comparative learner.

| Representative | Relevant static dimensions | Exact runtime outcome interpretation | Permanent learning from the direct event |
| --- | --- | --- | --- |
| Frostbolt | Frost school; Dispel=Magic; per-effect snare | snare-only rejection may be silent; generic `IMMUNE` has Frost-school/damage vs Magic-dispel alternatives | no write from generic `IMMUNE`; no write from `IMMUNE2` |
| Rake | Physical school; no spell-level mechanic/dispel; direct hit + effect-level bleed | bleed-only rejection may be silent; generic `IMMUNE` has only the existing Physical school/action whole-spell dimension | generic `IMMUNE` may learn **physical**; never reinterpret this direct result as bleed |
| Rupture | Physical school; spell-level Bleed mechanic; no dispel | generic `IMMUNE` can be Physical school/damage or Bleed mechanic | no write |
| Hammer of Justice | Holy school; spell-level Stun mechanic; Dispel=Magic | generic `IMMUNE` has multiple whole-spell causes before any effect inference | no Holy or stun write |
| Intercept parent | Physical school; no spell-level mechanic/dispel; trigger-spell effect | classify the actual spell ID in the Nampower event; parent `IMMUNE` can narrow to Physical | parent generic `IMMUNE` may learn physical |
| Intercept Stun trigger | Physical school; spell-level Stun mechanic | generic `IMMUNE` is Physical vs Stun ambiguous | no write |
| poison spell/debuff | school such as Nature + Dispel=Poison | generic `IMMUNE` can be school/damage or Poison-family immunity | no write |
| Curse of Agony example | Shadow school + Dispel=Curse | generic `IMMUNE` can be Shadow/damage or Curse-family immunity | no write |
| Devouring Plague example | Shadow school + Dispel=Disease | generic `IMMUNE` can be Shadow/damage or Disease-family immunity | no write |

This intentionally leaves some real immunities unlearned. False negatives are
acceptable at this stage; false permanent writes are not.

#### Revised evidence rule

The overall design rule remains:

```text
unique failed dimension -> learn it
multiple plausible causes -> ambiguous; learn nothing
```

But the candidate set must now be built from the **actual server failure path**,
not merely from every effect contained in the spell.

In particular:

```text
silent effect-level failure
```

must not automatically be added as an explanation for:

```text
whole-spell SPELL_MISS_SELF IMMUNE
```

The learner must distinguish at least:

```text
individual effect rejected
whole spell immune
all effects immune
```

before choosing what dimensions are candidates.

#### Combined evidence model

The strongest eventual learner is likely to combine:

##### ClassicAPI

For:

- spell decomposition;
- school;
- spell-level mechanic;
- per-effect mechanic;
- aura types;
- dispel family;
- authoritative actual aura state.

##### Nampower

For:

- `SPELL_MISS_SELF IMMUNE`;
- `SPELL_MISS_SELF IMMUNE2`;
- `SPELL_GO`;
- actual damage success;
- spell/caster/target correlation.

Positive evidence should be used to eliminate impossible causes.

Examples:

```text
actual Frost damage occurred
=> Frost-school immunity did not block that damage component
```

```text
actual physical Rake hit occurred
=> the direct physical component was not immune
```

```text
actual stun aura exists
=> stun immunity did not reject that application
```

Only after eliminating positively disproven candidates should permanent learning
occur.

#### Persistent Mob-ID knowledge + live observation architecture

The generalized learner should use a hybrid model rather than either repeatedly
re-learning every mob from scratch or persisting raw combat history.

Persistent knowledge is keyed by **creature/Mob ID** and stores only compact,
long-lived facts that can improve future inference:

- confirmed permanent immunity dimensions;
- confirmed susceptibility / disproved immunity dimensions;
- unresolved candidate evidence when one observation still has several valid
  explanations.

Unresolved evidence must survive reloads, resets and later encounters. If an
`IMMUNE` result leaves several plausible permanent causes today, later positive
evidence may disprove candidates until one cause remains and can be promoted to
a confirmed immunity. "Not recorded as immune" must therefore never mean
"confirmed susceptible".

Do **not** persist raw combat-event history or transient state. Current DR,
temporary protection/CC auras, death/despawn state and individual cast timing
remain live-only evidence.

Runtime observation should be lightweight and event-driven:

- Nampower supplies spell/caster/target outcomes, damage and aura/debuff events;
- relevant evidence must include **all observable casters**, not only the player;
- ClassicAPI supplies cached spell decomposition and targeted authoritative aura
  checks when an ambiguous case actually needs them;
- spell-ID classification should be cached so ordinary combat events reduce to
  a cheap lookup and early exit;
- the learner should query known Mob-ID facts first and perform deeper
  cross-event reasoning only for unknown, unresolved or contradictory evidence;
- no continuous mob/aura scanning and no new high-frequency polling should be
  introduced.

#### Generalized backend design decisions — COMPLETE

Confirmed decisions after the audit:

- target environments remain Vanilla 1.12.1 vMaNGOS and OctoWoW; one
  normalized evidence/inference pipeline should serve both, with core-specific
  observation interpretation isolated at the input boundary where required;
- HearthDB is a hard dependency for the generalized learner. Do not design a
  SavedVariables fallback knowledge store. Runtime must fail the learner
  clearly if HearthDB is unavailable rather than silently switching persistence
  models;
- the overhaul starts with a clean knowledge database. Do not migrate the old
  name-keyed immunity records into the new evidence store;
- authoritative dimension-specific success outranks permanent-immunity
  evidence: observed damage success disproves permanent immunity to that exact
  school/action dimension; authoritative aura presence disproves permanent
  immunity to that exact CC/mechanic dimension;
- vulnerability/susceptibility is persistent knowledge, not merely absence of
  an immunity. This prevents repeated re-investigation of dimensions already
  positively disproved;
- permanent disposition and dynamic-immunity suspicion are separate axes. A
  dimension can be positively known to succeed (therefore not permanently
  immune) while also carrying a persistent "temporary/conditional immunity
  suspected" flag when credible immunity evidence has been observed in another
  context. This covers uncatalogued temporary auras, boss-script phases and
  spawn/encounter-specific random immunity profiles without erasing either
  observation;
- ambiguous IMMUNE observations create linked candidate hypotheses rather than
  independent flat "suspected" facts. A candidate becomes confirmed immune only
  when all other valid permanent candidates have been positively disproved and
  no transient explanation remains;
- if every candidate in a hypothesis is later positively disproved, the
  original immune observation is discarded as unresolved/temporary/otherwise
  non-permanent evidence; it must not manufacture another immunity;
- if an already confirmed permanent immunity later succeeds authoritatively for
  the same dimension, success wins immediately for the permanent disposition:
  the permanent immunity is revoked and the dimension becomes
  vulnerable/susceptible. Because the earlier immunity evidence was credible,
  also set "temporary/conditional immunity suspected" rather than discarding
  that observation. A merely ambiguous candidate that is later disproved does
  not set this dynamic flag; it is simply eliminated from its hypothesis;
- keep compact conclusion provenance only (for example direct/comparative and a
  proof spell/event kind), not raw combat history.

Recommended HearthDB shape:

- `mobs`: Mob ID plus lightweight display metadata such as last known name;
- `facts`: one durable row per Mob-ID + dimension, with permanent verdict
  `immune` or `vulnerable`, an independent dynamic-immunity suspicion flag,
  and compact proof/provenance fields;
- `hypotheses`: unresolved ambiguous observations that still matter;
- `hypothesis_candidates`: the linked candidate dimensions for each unresolved
  hypothesis.

Unknown is represented by absence of a fact. "Suspected" is derived from
membership in an unresolved hypothesis rather than stored as a competing final
verdict.

Learning SCT belongs in the existing `/cleveroid immunities` UI as a toggle.
For development/testing it should expose state transitions compactly using
candidate icons/borders:

```text
yellow border = immunity candidate / suspect
green border  = candidate positively disproved (vulnerable)
red border    = confirmed permanent immunity
orange border = temporary/conditional immunity suspected

The x/y/z letters used during design discussion were shorthand only and must
never appear in SCT output.
```

Conceptually, one observation can progress from several yellow candidate icons,
through green elimination of disproved candidates, to one red confirmed
permanent-immunity icon. If a previously credible immunity is later
authoritatively disproved as permanent, preserve that history with the orange
temporary/conditional-suspicion treatment.

Do not emit separate vulnerability SCT spam by default; green candidate state in
the active learning trace is sufficient for testing. Whether the native SCT
surface can render independently bordered icons or requires a small custom
combat-text frame is an implementation/API detail to verify later.

#### Pre-implementation deep-evidence audit — COMPLETE

The focused audit needed before choosing the generalized learner policy is now
complete. It did not start generalized inference code.

Runtime evidence coverage is sufficient for the intended backend:

- `SPELL_MISS_SELF` / `SPELL_MISS_OTHER` provide caster GUID, target GUID,
  spell ID and miss reason for the player and other observable casters;
- `SPELL_DAMAGE_EVENT_SELF` / `SPELL_DAMAGE_EVENT_OTHER` provide direct
  positive evidence that a spell damage component actually landed, including
  caster GUID, target GUID, spell ID and runtime school;
- Nampower BUFF/DEBUFF gain events provide authoritative evidence that an aura
  actually exists on a tracked unit, including target GUID and spell ID;
- `AURA_CAST_ON_*` includes caster GUID and effect metadata but remains
  correlation metadata, not authoritative aura-success evidence. Nampower builds
  it from the SpellGo hit-target list plus static spell effects, so it must never
  by itself disprove an immunity;
- ClassicAPI authoritative aura data may supply `sourceGUID` / `sourceUnit`
  when available, which can improve attribution but is not required for the
  core positive-evidence model.

Mob identity is also sufficient. ClassicAPI's `UnitCreatureID(unit)` accepts a
raw GUID token directly and resolves the live creature-template entry from the
object when available. Its out-of-view GUID fallback is exact for stock-Vanilla
single-entry spawns, but Turtle-style multi-entry creature spawns can carry a
different template entry in the GUID. Therefore permanent Mob-ID evidence should
only be promoted from a live/resolvable identity; unresolved/out-of-view GUID
evidence should remain transient until the live Mob ID is known.

One correctness gap remains in all-caster NPC stun DR classification. vMaNGOS
chooses controlled-vs-triggered stun DR using a runtime `triggered` flag.
Nampower's OTHER miss/damage/aura events do not expose that flag, and the
existing `WasClientInitiatedSpell()` test is player-only. Known explicit spell
IDs can still be classified exactly. For an otherwise-unclassifiable landed stun
from another caster, the safe backend behavior is to retain a transient
"DR category uncertain" guard that prevents DR-dependent permanent inference
until the reset window expires rather than guessing a DR bucket. This may create
temporary false negatives but cannot create a false permanent immunity.

The remaining work before implementation is therefore policy/design rather than
additional immunity-semantics research:

- exact persistent state-transition / contradiction / revocation rules;
- migration treatment for legacy name-keyed recorded immunities;
- how much compact provenance to retain without storing raw combat history;
- SCT presentation and verbosity. SCT should consume centralized learner
  state-transition notifications rather than raw combat events.

NPC DR is a correctness prerequisite for this model. The existing
`recentCCHits` safeguard is currently populated from player-owned verified CC,
which is insufficient once comparative inference begins. Before DR is used as
positive/negative evidence by the generalized learner, SCRM must record
**qualifying landed stuns from all observable casters**, target-centrically, in
the existing independent Vanilla NPC DR buckets:

```text
stun_control
stun_trigger
stun_kidneyshot
```

These are separate DR categories that share the broad CC type `stun`; they must
not be collapsed into one stun counter. Runtime DR state remains temporary and
must never be written into the permanent Mob-ID knowledge store.

The safety invariant does not change:

```text
one remaining valid permanent cause -> learn / promote it
multiple remaining valid causes -> preserve compact unresolved evidence
transient cause still plausible -> do not persist a permanent immunity
```

#### Audit conclusion and landed correction

The original working correction:

```text
every direct IMMUNE -> school
```

was unsafe.

The next proposed correction:

```text
generic IMMUNE -> enumerate every school/effect/mechanic contained in the spell
```

was also too coarse because vMaNGOS often rejects individual effects silently.

The landed minimal correction is narrower:

```text
IMMUNE2
    -> never persist directly

IMMUNE
    -> inspect only valid whole-spell causes
    -> school/damage collapse to current school/action persistence
    -> any spell-level mechanic, Dispel family, target-type restriction,
       or missing DBC school makes the result inconclusive
    -> otherwise persist the literal DBC school
```

Implementation commit:

```text
6df12256213c73cc5236abb716b7ef8e7c692a3a
```

The existing target/spell identity, split-CC, death, TempCC, temporary
protection/reflection, NPC DR, queryable-target, persistence and public macro
safeguards remain in place.

Portability boundary:

- raw Nampower `IMMUNE`/`IMMUNE2` remains the shared observable interface;
- raw `IMMUNE2` is conservatively non-learning on every core;
- the positive `IMMUNE -> school/action` narrowing currently follows the
  inspected vMaNGOS whole-spell semantics;
- Turtle/Octo compatibility is still an explicit assumption to verify in
  runtime testing, not a claimed proven server implementation detail.

### Blackwing Spellbinder — HoJ FIX LANDED; RUNTIME RETEST PENDING

Focused runtime results before the fix:

```text
Fire Blast IMMUNE
    -> Fire learned
    -> expected under the current direct-school rule

Frostbolt IMMUNE
    -> Frost not learned
    -> expected under the current conservative ambiguity rule

Hammer of Justice IMMUNE
    -> Holy learned
    -> FAIL; expected neither Holy nor Stun
```

The HoJ failure was localized to the direct `SPELL_MISS_SELF` learner:
`GetSpellImmunityType()` already resolved HoJ as Stun from effect-level
mechanics, but the final school-learning gate discarded that classification.

The focused correction now:

- reuses the resolved CC/immunity classification in the final ambiguity decision;
- rejects a direct school write whenever that classification resolves to a CC
  mechanic, including effect-level Stun;
- retains the existing spell-level mechanic, target-creature and Dispel-family
  safeguards;
- falls back to ClassicAPI `C_Spell.GetSpellDispelType()` only when Nampower's
  raw `dispel` field is nil/unavailable;
- includes the resolved CC/effect-mechanic reason in `immunitydebug`.

Implementation commit:

```text
43850cb6b3025c09ce480f994fe573dab33f6577
```

Expected replay on Blackwing Spellbinder:

```text
Hammer of Justice IMMUNE
    -> ambiguous: resolved CC/effect mechanic=stun
    -> no Holy write
    -> no Stun write
```

This remains a focused correction to the current conservative learner.
The generalized comparative implementation may now proceed through the staged
development plan below. Runtime validation is deferred until the complete
implementation is assembled; do not insert in-game test gates between
development slices. Broad `spell` promotion remains outside the initial slices
unless later evidence justifies it.

## Generalized backend development sequence

The design phase is complete enough to implement. Keep each slice small enough
to finish, statically review, document and commit in one development chat.
Do not begin the next slice in the same chat unless the current slice is
trivially small.

The slices are context/tooling boundaries, not runtime-test gates. Do not
runtime-test between implementation slices. Assemble the complete backend first,
then perform the focused and cross-core runtime matrix in the final validation
slice.

The runtime rule during development is **one active learner**. New backend code
may be built behind an explicit development gate, but when the generalized
learner is enabled it must suppress the old permanent-learning write path rather
than allowing two learners to compete.

### Slice 0 — conservative learner static checkpoint — COMPLETE

Purpose: verify that the currently landed conservative learner still has the
intended safety boundaries before changing the learner architecture, without
introducing an in-game test gate.

Completed static review at handoff
`f145aed3ba5620d3267cb9be5891b3adab8d1934`:

- branch head matched the supplied handoff;
- the six commits after the HoJ fix `43850cb6b3025c09ce480f994fe573dab33f6577`
  changed only this document, so the learner code under review was unchanged;
- the direct learner still places player, split-CC, death, TempCC, temporary
  protection/reflection, NPC-DR, queryable-target and `IMMUNE2` rejection gates
  before permanent persistence;
- the HoJ correction still makes resolved Stun/effect-mechanic evidence an
  ambiguity before any Holy school write;
- no HearthDB or generalized learner implementation was started during this
  checkpoint.

The previously planned live HoJ/player/`IMMUNE2`/TempCC/protection/reflection/
NPC-DR/death/split-CC matrix is retained for the final runtime validation slice;
it is not required between implementation slices.

Stop condition: static checkpoint complete; proceed to Slice 1 in a fresh
development chat.

### Slice 1 — HearthDB dependency and schema foundation — COMPLETE

Purpose: establish the clean authoritative datastore without changing combat
learning.

Implemented at code checkpoint
`a1a757289ae76db16a25290eb11b2d0d001141bf`:

- added `ImmunityStorage.lua` and load it before runtime initialization;
- HearthDB is feature-detected as a hard dependency for the new immunity
  knowledge store; there is no SavedVariables fallback;
- the store opens/creates
  `CustomData/SuperCleveRoidMacros_Immunity.db`;
- schema v1 is managed with SQLite `PRAGMA user_version`;
- a fresh database creates the schema, while an incompatible or structurally
  invalid schema is cleanly reset rather than migrated;
- schema v1 creates `mobs`, `facts`, `hypotheses`, and
  `hypothesis_candidates`, with foreign-key cleanup and a Mob-ID hypothesis
  index;
- durable fact rows reserve the designed permanent verdict
  (`immune`/`vulnerable`), independent dynamic-suspicion flag, and compact
  proof source/spell/event provenance;
- the storage API exposes readiness/diagnostics, guarded execute/query calls and
  escaped/validated text, integer, boolean and enumerated SQL literal helpers;
- missing HearthDB API, database-open failures and schema failures are surfaced
  distinctly through the existing requirement diagnostics;
- the database handle is closed during addon disable/logout.

Static review completed:

- branch state matched the supplied Slice 0 handoff before implementation;
- Lua parse/helper checks passed for the new storage module;
- stubbed lifecycle checks passed for fresh-schema creation and incompatible
  schema reset;
- the schema create/reset SQL executed successfully against SQLite with
  `user_version = 1` and the expected columns;
- the implementation adds no combat-event learner, no generalized inference
  path and no migration/read of legacy name-keyed immunity SavedVariables.

No runtime testing was performed. Runtime DB/plugin validation remains deferred
until Slice 8.

Stop condition: Slice 1 complete; proceed to Slice 2 in a fresh development
chat.

### Slice 2 — normalized observation pipeline — COMPLETE

Purpose: create the single evidence input seam before inference exists.

Implemented at code checkpoint
`cea27a03b2d9d8ab4753f29e563dca3023374d95`:

- added `ImmunityObservations.lua` as an isolated event-driven normalization
  seam loaded after `ClassicAPI.lua`; it has no persistence or production
  immunity-query consumer yet;
- normalized both SELF and OTHER Nampower spell-miss and spell-damage events,
  all BUFF/DEBUFF added/removed variants, and `UNIT_DIED`;
- authoritative damage-landed observations and authoritative actual aura
  presence are represented separately from ambiguous `IMMUNE`/`IMMUNE2`
  observations; full aura removals and ordinary misses remain neutral evidence;
- `AURA_CAST_ON_*` is intentionally not registered or consumed as positive
  evidence because it is correlation metadata rather than authoritative aura
  state;
- added ClassicAPI wrappers that resolve a combat-event GUID through
  `UnitTokenFromGUID`, immediately re-verify the live token GUID, and only then
  call `UnitCreatureID`; the raw-GUID out-of-view fallback is therefore not
  accepted as a live Mob ID;
- cached spell profiles include DBC school, spell-level mechanic, per-effect
  mechanics, raw effect/aura records, dispel family and normalized SCRM mechanic
  dimensions; aura-name fallback classification is only used when no recognized
  explicit mechanic exists;
- the input boundary exposes selectable `portable`, `vmangos`, and
  `octowow` miss adapters. `portable` is the default, vMaNGOS-specific
  `IMMUNE`/`IMMUNE2` descriptions remain diagnostic metadata, and OctoWoW
  semantics remain explicitly unverified until Slice 8;
- a listener seam plus compact counters/last-observation diagnostics were added,
  but there are no inference listeners in Slice 2.

Static review completed:

- the required ClassicAPI identity and spell-decomposition APIs were verified
  against the repository's required ClassicAPI v1.15.8 tag;
- the code checkpoint changes only `ClassicAPI.lua`,
  `ImmunityObservations.lua`, and `SuperCleveRoidMacros.toc`;
- static registration/scope checks cover SELF/OTHER miss, damage, buff/debuff
  add/remove and death observations;
- a structural Lua block-balance check passed for the new module;
- scope scans confirm the new pipeline does not call HearthDB/ImmunityStorage,
  `RecordImmunity`, NPC DR state or `AURA_CAST_ON_*`;
- the existing conservative learner remains untouched and therefore remains the
  only code producing current permanent learner output.

No runtime testing was performed. Runtime event verification remains deferred
until Slice 8.

Stop condition: Slice 2 complete; proceed to Slice 3 in a fresh development
chat.

### Slice 3 — transient-context and all-caster NPC DR safety — COMPLETE

Purpose: make the safety layer sufficient before permanent inference is allowed.

Implemented at code checkpoint
`93d6a647708b0bd148ef824a82af65772e0f41b3`:

- added `ImmunityTransient.lua` as an event-driven listener on the normalized
  observation seam; it owns live-only target-centric transient state and does
  not write HearthDB, SavedVariables or the existing production learner;
- qualifying authoritative NPC stun aura-presence observations from any
  observable caster now advance target-centric DR state. A GUID must either
  resolve to a live Mob ID on that observation or already belong to transient
  state whose Mob ID was previously proven live;
- preserved independent `stun_control`, `stun_trigger`, and
  `stun_kidneyshot` counters with the existing 20-second reset model;
- added a generalized-backend stun classifier without changing the conservative
  learner's existing `GetSpellImmunityDRType()` behavior. Kidney Shot and the
  existing explicit controlled-stun overrides classify exactly; player-caster
  evidence may use the existing client-initiated cast evidence;
- when another caster's controlled-vs-triggered category cannot be proven from
  the available event data, no bucket is guessed. A target-level
  `dr_category_uncertain` blocker is retained through the DR reset window;
- an otherwise-unclassifiable current OTHER-caster stun also remains blocked if
  either plausible controlled/triggered bucket is already at immune-stage DR;
- existing curated TempCC and temporary protection/reflection definitions remain
  authoritative in `Utility.lua`, but are exposed to the transient reducer as
  normalized aura explanations rather than duplicated into another spell list;
- direct `REFLECT` miss observations are exposed as reflection explanations,
  never as immunity;
- `UNIT_DIED` clears target DR/aura context and retains the existing short
  recent-death safety window; `PLAYER_ENTERING_WORLD` emits a normalized
  `world_reset` lifecycle observation that clears stale transient target
  state;
- the normalized pipeline now exposes an explicit lifecycle seam for a proven
  `despawned` observation. Nampower has no separate per-unit despawn event in
  the currently supported event surface, so no synthetic individual-despawn
  inference was added;
- transient explanation queries expose death, temporary CC, temporary
  protection, reflection, DR/uncertain-DR and unresolved live-identity blockers
  for the later inference slices;
- no permanent comparative inference, fact/hypothesis persistence, production
  query cutover or UI/SCT behavior was added.

Static review completed:

- branch state matched handoff
  `58cc090c289170377ac5bf6108109a9a765f7d2b` before implementation, whose
  parent is the Slice 2 code checkpoint
  `cea27a03b2d9d8ab4753f29e563dca3023374d95`;
- the code checkpoint changes only `ImmunityObservations.lua`,
  `ImmunityTransient.lua`, `Utility.lua`, and
  `SuperCleveRoidMacros.toc`;
- structural Lua block/bracket checks pass for the new transient reducer and the
  modified observation module;
- the Utility-wide structural heuristic produces exactly the same two
  pre-existing false-positive `end` reports at the handoff and code
  checkpoint, while both inserted Utility methods balance cleanly in isolation;
- the new Utility helpers are direct `CleveRoids` methods, so Slice 3 adds no
  chunk-scope locals to the already local-limit-sensitive `Utility.lua`;
- scope scans confirm the transient reducer has no executable reference to
  HearthDB/ImmunityStorage, `CleveRoids_ImmunityData`,
  `RecordImmunity`/`RecordCCImmunity`, UI/SCT or an `OnUpdate` loop;
- SELF/OTHER miss, damage and aura inputs plus `UNIT_DIED` remain registered,
  and the transient reducer consumes the existing listener seam rather than
  adding a second combat-event normalization path;
- the existing conservative DR classifier/write paths remain intact.

No runtime testing was performed. All-caster and uncertain-DR runtime
verification remains deferred until Slice 8.

Stop condition: Slice 3 complete; proceed to Slice 4 in a fresh development
chat.

### Slice 4 — durable vulnerability and hypothesis engine — COMPLETE

Purpose: add persistent learning without yet broadening public immunity behavior.

Implemented at code checkpoint
`dad3406ea1099b28259851fd71cfacf9be8201ac`:

- added `ImmunityKnowledge.lua` as a listener after the normalized transient
  reducer. It writes only the HearthDB knowledge store and does not mutate the
  legacy SavedVariables learner;
- authoritative landed damage persists vulnerability for the proven runtime
  school/action dimension. Authoritative hostile aura presence may additionally
  prove the action school, Dispel family, and an exact spell/effect mechanic
  when that mapping is unambiguous;
- expanded normalized spell metadata with exact spell-level and per-effect
  mechanic dimensions, mechanic 15 `bleed`, Dispel-family dimensions and the
  existing `targetCreatureType` restriction. The internal
  `dispel_magic` learning dimension remains separate from broad `spell`;
  Poison, Curse and Disease likewise remain distinct from spell school;
- core-specific miss interpretation remains at the observation adapter boundary.
  When the verified vMaNGOS adapter supplies `whole_spell`, generic
  `IMMUNE` can create one linked unresolved hypothesis from only the
  whole-spell permanent candidates: school/action, spell-level mechanic and
  Dispel family;
- vMaNGOS `IMMUNE2` / `effect_mask_zero` is deliberately not persisted yet:
  aura-state, effect-type and other unmodelled effect-mask causes mean a partial
  candidate set could later over-confirm. Portable and Octo/Turtle raw
  `IMMUNE` semantics also remain non-durable until their adapter semantics are
  verified;
- a spell with a static target-creature restriction likewise abstains from
  durable whole-spell hypothesis creation because that is a known non-permanent
  alternative explanation. The same conservative abstention applies when a
  spell-level mechanic or Dispel family is present but has no recognized durable
  Slice 4 dimension, so an unmodelled cause cannot be silently dropped and later
  over-confirmed;
- transient explanations from Slice 3 are checked before hypothesis persistence:
  reflection, death, DR/uncertain DR, unresolved live identity, broad temporary
  protection and applicable exact temporary immunity block the observation;
- already-known `vulnerable` facts are removed from a new candidate set
  immediately. A new authoritative vulnerability removes that same dimension
  from every existing hypothesis for the Mob ID and deletes hypotheses whose
  candidate set becomes empty;
- exact duplicate unresolved candidate sets are deduplicated per Mob ID, keeping
  compact conclusion provenance rather than raw combat history;
- `unknown` remains absence of a fact. `suspected` is derived at read time
  from membership in an unresolved hypothesis; it is not stored as another fact
  verdict;
- a hypothesis narrowed to one candidate remains unresolved and is only exposed
  as ready for later confirmation. Slice 4 never writes an `immune` fact;
- if authoritative success contradicts an already-existing `immune` fact,
  Slice 4 deliberately leaves it untouched and records only a diagnostic
  deferral. Revocation and dynamic-suspicion semantics belong to Slice 5;
- no broad-immunity promotion, production query/macro cutover, UI/SCT behavior
  or runtime test was added.

Static review completed:

- branch state matched supplied handoff
  `2264460bdf50ff56e326104904dfa29dc23391d9` before implementation;
- the code checkpoint changes only `ImmunityKnowledge.lua`,
  `ImmunityObservations.lua`, and `SuperCleveRoidMacros.toc`;
- structural bracket and Lua block-balance checks pass for both changed Lua
  modules;
- static SQL transition checks pass for creation of a linked two-candidate
  hypothesis, authoritative elimination to one candidate, and elimination of
  the final candidate with empty-hypothesis cleanup;
- scope scans confirm no `OnUpdate` polling, legacy immunity writes, UI/SCT
  execution, broad candidate creation, permanent `immune` fact mutation, or
  common-reducer branch on core name;
- TOC order is transient reducer -> durable knowledge reducer -> immunity UI,
  so hypothesis persistence can consume the complete transient safety context;
- the incomplete `IMMUNE2`, target-creature restriction, unrecognized
  spell-mechanic and unrecognized Dispel-family abstention paths are present at
  the final code checkpoint.

No runtime testing was performed. Cross-encounter/reload persistence and
cross-core behavior remain deferred until Slice 8.

Stop condition: Slice 4 complete; proceed to Slice 5 in a fresh development
chat.

### Slice 5 — permanent confirmation, revocation and dynamic suspicion — COMPLETE

Purpose: complete the evidence reducer.

Implemented at code checkpoint
`9253437f2b32d87f9addef9b6323fa0d8a03ce10`:

- an ambiguous immunity observation now writes a permanent `immune` fact only
  when transient/live explanations have been excluded and exactly one valid
  permanent candidate remains after known vulnerability is removed;
- hypotheses persisted by Slice 4 are trusted only because persistence already
  required transient explanations to be absent. When later authoritative
  success eliminates candidates, a hypothesis that reaches one remaining valid
  permanent dimension is confirmed in the same deterministic transition;
- authoritative success always wins for its exact proven dimension. It records
  `vulnerable`; if the previous durable verdict was `immune`, the same
  transaction revokes it and sets `dynamic_suspected = 1`;
- ordinary candidate elimination never sets the dynamic flag. A newly inserted
  or already-vulnerable fact remains `dynamic_suspected = 0` unless a
  credibly confirmed `immune` fact was actually revoked;
- dynamic suspicion is itself treated as a credible conditional/non-permanent
  explanation for later ambiguous immunity. New hypotheses involving that
  dimension are blocked, and an existing hypothesis containing a dimension
  that has just been revoked to dynamic vulnerability is discarded whole
  rather than narrowed into a false permanent confirmation;
- a candidate that is already confirmed immune resolves a later ambiguous
  observation without creating another hypothesis about its other dimensions;
- when confirmation proves a dimension, unresolved hypotheses already explained
  by that confirmed dimension are removed. If more than one ready hypothesis
  proves the same dimension, the earliest persisted hypothesis supplies the
  compact proof source/spell/event provenance;
- conclusion storage remains one fact row plus compact proof provenance and the
  unresolved linked hypotheses that still matter. No raw combat history is
  added;
- no broad-immunity promotion, production query/macro cutover, legacy
  SavedVariables write, UI/SCT behavior or runtime test was added.

Static review completed:

- branch state matched supplied handoff
  `49ce7a7fa581a724e1050c4dbc9a7e30b4e6ad1e` before implementation;
- the code checkpoint changes only `ImmunityKnowledge.lua`;
- delimiter and Lua block-balance checks pass for the modified reducer;
- the transition matrix was checked for ordinary candidate elimination to one
  confirmed candidate, exact confirmed-immunity revocation, dynamic-suspicion
  blocking/discard behavior, known-immune resolution, and multiple independent
  hypotheses narrowed by one authoritative success;
- SQL transition checks cover absent, ordinary-vulnerable,
  dynamic-vulnerable and confirmed-immune starting facts. Only a prior
  `immune` verdict causes authoritative success to set the dynamic flag, while
  an existing dynamic flag is preserved across later successes;
- scope scans confirm no `OnUpdate` polling, no legacy
  `CleveRoids_ImmunityData` / `RecordImmunity` writes, no UI/SCT execution,
  and no `spell`/`cc`/`all` candidate promotion;
- branch HEAD at static-review completion is the code checkpoint above.

No runtime testing was performed. Reload/persistence and cross-core behavior
remain deferred until Slice 8.

Stop condition: Slice 5 complete; proceed to Slice 6 in a fresh development
chat.

### Slice 6 — production cutover and query integration — COMPLETE

Purpose: make the generalized backend the sole active immunity knowledge source.

Implemented at code checkpoint
`419a31b58de9ee4e60c7b2ac95bcf79f49687351`:

- `CleveRoids.CheckImmunity`, exact CC queries and spell-action dimension
  queries now consume confirmed Mob-ID-keyed HearthDB facts through
  `ImmunityKnowledge`; existing `[immune]` / `[noimmune]` macro conditionals
  already funnel through that query seam and required no parser changes;
- action queries now include the generalized learner's exact dispel-family
  dimensions (`dispel_magic`, `curse`, `disease`, `poison`) in addition to
  school, bleed, exact CC and existing broad composition, so confirmed exact
  facts are usable by production spell decisions;
- broad `spell` / `cc` / `all` facts are queryable if present, but Slice 6
  does not add any broad candidate or promotion rule;
- the generalized module exposes an explicit active cutover gate that is
  independent of storage readiness. When active, the old direct, delayed and
  text-only permanent SavedVariables write/remove paths cannot compete with the
  HearthDB learner; HearthDB failure therefore does not silently fall back to a
  second learned store;
- `CleveRoids_ImmunityData` is retained only for genuinely separate explicit
  manual/static and conditional overrides. Data version 7 clears the old
  indistinguishable name-keyed learned/manual records once; no legacy learned
  facts are migrated into HearthDB;
- existing hard-coded/live inputs remain separate and compose with the same
  production query path, including typed temporary protection/CC auras and the
  bespoke Banish live state;
- the existing immunity UI's learned columns and current-target read path now
  consume confirmed HearthDB facts while still showing manual/static overrides.
  Slice 7 transition/SCT diagnostics, candidate/vulnerability/dynamic-state
  presentation and provenance expansion were not started;
- repeated authoritative success on dimensions already durably known
  `vulnerable` now takes a fast path before hypothesis loading or SQL writes.
  Existing known-immune, known-vulnerable and dynamic-candidate hypothesis
  short-circuits remain intact.

Static review completed:

- branch state matched supplied handoff
  `ecabd5c45e9c8d0a79edd30bb1d2763fed06af31` before implementation, whose
  parent code checkpoint is
  `9253437f2b32d87f9addef9b6323fa0d8a03ce10`;
- the code checkpoint changes only `Utility.lua`, `ImmunityKnowledge.lua`,
  `ImmunityUI.lua` and `Init.lua`;
- changed-file Lua block/delimiter delta checks balance against the supplied
  handoff state;
- the new UI fact query was checked against the existing HearthDB schema and
  uses `mobs.last_name`; no schema change or migration was introduced;
- repo-wide Lua scope scanning finds legacy `CleveRoids_ImmunityData` usage
  only in `Utility.lua`, `Init.lua` and `ImmunityUI.lua`. The remaining
  automatic compatibility writers are cutover-gated; the ungated mutations are
  explicit manual/static management/reset paths;
- production query scans confirm exact CC, school/mechanic, dispel-family and
  broad reads reach `ImmunityKnowledge`, while the candidate set still contains
  no `spell` / `cc` / `all` promotion;
- `Conditionals.lua` remains unchanged and continues to route both `immune`
  and `noimmune` through `CleveRoids.CheckImmunity`;
- no Slice 7 learning SCT, candidate-state UI, broad-immunity inference, Slice 8
  cleanup or runtime test was added.

No runtime testing was performed. Production cutover behavior, persistence and
cross-core compatibility remain deferred until Slice 8.

Stop condition: Slice 6 complete; proceed to Slice 7 in a fresh development
chat.

### Slice 7 — learning SCT / immunity-screen diagnostics — COMPLETE

Purpose: expose the learner's state transitions for runtime validation.

Implemented at code checkpoint
`4d12a0eafa4932df4afb5967a2ac81ca5fc4c277`:

- `ImmunityKnowledge` now owns a centralized transition-listener seam. UI/SCT
  presentation consumes committed learner state changes instead of re-deriving
  inference independently;
- a new `/cleveroid immunities` **Learning SCT** toggle persists through
  `CleveRoidMacros.learningImmunitySCT` and is disabled by default when no
  setting exists;
- the compact custom learning-SCT surface uses relevant dimension
  spell/mechanic icons with the designed states: yellow unresolved candidate,
  green positively disproved candidate, red confirmed permanent immunity, and
  orange temporary/conditional suspicion after a confirmed immunity is
  authoritatively revoked;
- yellow is emitted only when a durable unresolved hypothesis is created.
  Green is emitted only when authoritative success removes a dimension that was
  actually present in an unresolved hypothesis. Routine standalone
  vulnerability recording and the already-known-vulnerable fast path do not
  emit green SCT;
- red is emitted only after the permanent fact transaction succeeds, both for a
  directly unique remaining candidate and for comparative confirmation after
  later candidate elimination;
- orange is emitted only when authoritative success revokes a previously
  confirmed permanent immunity and therefore establishes the independent
  dynamic/temporary/conditional-suspicion state;
- the design-only x/y/z shorthand is not present in runtime output;
- the current-target immunity screen now exposes the Mob ID, every durable fact
  verdict, dynamic-suspicion state, proof source/spell/event provenance, and
  every unresolved hypothesis ID/candidate set with its proof
  source/spell/event. These are read-only diagnostic views over HearthDB;
- creating a new durable hypothesis now triggers the existing event-driven
  immunity-screen refresh so an open screen reflects candidate state
  immediately;
- no schema change, raw combat-history persistence, broad-immunity promotion or
  second inference path was introduced.

Static review completed:

- branch state matched supplied handoff
  `8f72ed5045ed2abf31ecbdc38397aaf82ad15d0c` before implementation, whose
  parent code checkpoint is
  `419a31b58de9ee4e60c7b2ac95bcf79f49687351`;
- the Slice 7 code checkpoint changes only `ImmunityKnowledge.lua` and
  `ImmunityUI.lua`;
- comment/string-stripped Lua block deltas plus parenthesis/brace deltas balance
  against the supplied handoff state for both changed files;
- post-commit scans confirm all four transition states are wired from the
  centralized reducer, broad `spell` / `cc` / `all` remain absent from
  `CANDIDATE_DIMENSIONS`, the known-vulnerable fast path emits no learning
  SCT, and no x/y/z shorthand is present in runtime code;
- transition emission is downstream of successful durable mutations: failed
  storage operations do not create UI/SCT state that the database did not
  commit;
- the repository provides no lint/test workflow beyond release packaging, so
  no automated repository test suite was available for this slice;
- `dev_rulebook.md` and `DEV_PROGRESS.md` are absent from both this branch
  and `main`; the existing rework document therefore remains the available
  branch-specific handoff source for this work.

No runtime testing was performed. Visual alert layout, live transition behavior,
persistence/reload behavior and cross-core compatibility remain deferred to
Slice 8.

#### Runtime-driven immunity-learning alert revision — UI IMPLEMENTED; COMPLETE PROOF-TRAIL PENDING

Implementation checkpoint (9 October 2026): `a16fc9a89caaaf3a1a53aab4a3e4eecc4c9ed4da`.
- Header-layout follow-up: `4bbe5edd01e4d43d3a798c815714ce0601218682` moves controls below the title, shifts the CC/spell sections down, suppresses default below-slider endpoint captions, and places `Off` and `10 sec` beside the duration slider. Runtime UI recheck pending.

- `ImmunityUI.lua` now shows the **Immunity Learning Alerts** duration slider (0–10 seconds; 0 disabled), proportional fading, draggable Unlock/Lock template, and saved popup offsets in the addon SavedVariables table.
- The alert uses a compact two-row header/mob-name surface, content-sized width, and grouped evidence icons. Numeric Mob IDs and spell IDs are excluded from popup text; the detailed immunity inspection screen remains authoritative for these diagnostics.
- Existing boolean `learningImmunitySCT` is only a compatibility input when no new duration exists; newly selected duration is persisted under `learningImmunityAlertDuration`. Position is persisted under `learningImmunityAlertX` / `learningImmunityAlertY`.
- The centralized listener and learner transition meanings were preserved; no change was made to `ImmunityKnowledge.lua`, HearthDB, combat observations, or learner inference.
- **Outstanding presentation gap:** current transition payloads do not include the *complete historical list* of spell/dimension observations that eliminated other candidates during a multi-observation resolution. The UI may therefore show only the individually emitted confirmed/disproved pairs, not a single combined red+green proof trail. It must not invent such historical evidence. A follow-up bounded presentation-provenance design is required before marking the full proof-trail requirement complete. This work must not alter inference semantics.
- Live 1.12.1 validation and a full Lua syntax/test-run have not yet been performed; inspect the alert, slider, saved location, fading, stacking/wrapping and evidence colours before treating the UI revision as runtime PASS.


Live Slice 8 use showed that the Slice 7 custom popup is useful, but the
"Learning SCT" name is misleading because it is not Blizzard scrolling combat
text. The popup should be revised as a bounded presentation/settings change;
the learner, inference rules, transition seam and HearthDB model must remain
unchanged.

The `/cleveroid immunities` control row should become conceptually:

```text
Immunity Learning Alerts | Duration 0 ---------- 10 | Unlock / Lock
```

Required behaviour:

- rename the existing "Learning SCT" control/surface to **Immunity Learning
  Alerts**;
- replace the binary enable toggle with a persisted **0-10 second duration**
  control;
- duration `0` means disabled;
- duration `1-10` is the popup lifetime in seconds;
- fading should remain relative to the selected lifetime rather than using the
  current hard-coded `3.5` / `2.7` second constants;
- add one **Unlock / Lock** position control;
- Unlock shows a draggable template at the saved/current alert position;
- while unlocked, dragging the template changes the alert anchor;
- Lock saves the position and hides the template;
- normal alerts use that persisted position. Position is therefore user-set,
  not a new fixed screen coordinate.

The alert itself should become a compact two-row surface. Evidence icons span
the height of both text rows, so the left text block can use exactly those two
rows for the alert state and mob name:

```text
+----------------------------------------------------------------------------------+
| Immunity Resolved!   [Spell][Dimension]   [Spell][Dimension]   [Spell][Dimension]|
| Blackwing Spellbinder                                                            |
+----------------------------------------------------------------------------------+
```

The live popup should show the mob **name only**. Mob ID, spell IDs and other
diagnostic/provenance detail remain available in `/cleveroid immunities` rather
than consuming popup space.

Detected/unresolved presentation:

```text
+---------------------------------------------------------------+
| Immunity Detected!   [Trigger spell]   [Candidate] [Candidate]|
| Blackwing Spellbinder                                         |
+---------------------------------------------------------------+
```

- the triggering spell icon is shown;
- candidate school/CC/effect icons are shown beside it;
- the existing yellow candidate border communicates unresolved possibilities;
- explanatory candidate text is unnecessary because the icon plus border state
  is the intended compact presentation.

Resolved presentation is an evidence trail, not only the final answer. Each
piece of evidence is rendered as a tightly grouped **spell + dimension pair**:

```text
Immunity Resolved!   [Hammer of Justice][Holy]   [Charge Stun][Stun]
                     [Fireball][Spell]
Blackwing Spellbinder
```

The actual popup remains horizontal where space permits; the wrapped example
above is only to illustrate pair membership.

Resolved evidence-pair semantics:

- both icons in a pair share the same outcome border colour;
- **red** pair = that evidence/dimension survives as the confirmed permanent
  immunity;
- **green** pair = authoritative success eliminated that candidate;
- **orange** remains reserved for the existing temporary/conditional suspicion
  state where that transition is relevant;
- multiple spell icons are expected when several observations contributed to a
  resolution;
- only evidence that actually participated in the learner's resolution chain is
  shown. The popup must not become a generic combat-history display;
- the spell icon and its dimension icon must stay visually adjacent, with a
  larger gap between evidence pairs so pair ownership is obvious.

Example resolved proof trail:

```text
Immunity Resolved!   [Charge Stun][Stun]   [Auto Attack][Physical]
Blackwing Spellbinder

[Charge Stun][Stun]      red
[Auto Attack][Physical]  green
```

Another valid trail:

```text
Immunity Resolved!   [Hammer of Justice][Holy]   [Charge Stun][Stun]
                     [Fireball][Spell]
Blackwing Spellbinder

[Hammer of Justice][Holy] red
[Charge Stun][Stun]       green
[Fireball][Spell]         green
```

Layout requirements:

- evidence icons are approximately the height of the two text rows combined;
- the alert status occupies the first text row at the left;
- the mob name occupies the second text row at the left;
- evidence begins to the right of that two-row text block;
- popup width should be content-driven rather than permanently reserving the
  current 480-pixel width;
- if a long proof trail must wrap, wrap whole spell+dimension pairs and never
  separate a spell icon from its paired dimension icon;
- preserve the existing state-colour meanings and centralized transition
  listener; this revision must not re-derive learner inference in the UI.

This UI revision is intentionally separate from broad-immunity promotion and
must not change the Slice 8 learner/runtime invariants.

Stop condition: Slice 7 learner diagnostics are implemented; this agreed alert
revision remains a bounded pending UI task during Slice 8 validation.

### Slice 8 — cross-core runtime matrix and cleanup — RUNTIME PENDING

Purpose: validate the completed pipeline on the intended ecosystems after all
implementation slices are assembled, then remove only cleanup justified by that
validation.

Source/static validation completed from handoff
`e599ae47bd7cd7968f7ed66aa3b9b7bb26ce50ea`:

- the supplied handoff was exactly the branch tip before Slice 8 work; its parent
  code checkpoint remains Slice 7
  `4d12a0eafa4932df4afb5967a2ac81ca5fc4c277`;
- `dev_rulebook.md` and `DEV_PROGRESS.md` remain absent from both this branch
  and `main`; no replacement contents were invented;
- the conservative safeguards remain present for player-target rejection,
  `IMMUNE2`, TempCC, temporary protection/reflection, NPC DR, recent death,
  queryable-target identity and split-CC handling, while generalized cutover
  continues to suppress legacy learned-SavedVariables writes;
- SELF/OTHER miss and damage plus SELF/OTHER authoritative aura-presence events
  still enter the one normalized observation pipeline. Other-caster stun
  evidence that cannot prove controlled-vs-triggered DR still creates a
  target-level `dr_category_uncertain` blocker for the 20-second reset window
  instead of guessing a DR bucket;
- a valid HearthDB v1 schema is reopened and validated without reset, durable
  facts/hypotheses are read from the same database, and
  `PLAYER_ENTERING_WORLD` clears only live transient context. This statically
  preserves the intended durable-vs-transient reload boundary;
- current vMaNGOS server source confirms the adapter model already documented:
  per-effect immunity removes effect-mask bits, whole-spell immunity reports
  `IMMUNE`, and a final empty effect mask reports `IMMUNE2`;
- inspected public Turtle-family server source has the same relevant
  `IMMUNE`/`IMMUNE2` split. Nampower's documented
  `SPELL_MISS_SELF`/`SPELL_MISS_OTHER` interface forwards the raw numeric
  miss variants, so no second inference engine is required for the two target
  families;
- validation exposed one activation defect: the assembled generalized backend
  still defaulted to the deliberately non-inferential `portable` adapter and
  nothing selected a production adapter. That meant durable ambiguous-IMMUNE
  inference could never start on a normal load even on verified vMaNGOS;
- cleanup commit `e8634814e321a9bff23529875c2504e1fc2ac80e` fixes only that
  defect. Normal startup now selects `octowow` when the existing Turtle-family
  environment flag is present and `vmangos` otherwise; both adapters feed the
  same reducer. `portable` remains available only as an explicit conservative
  diagnostic/test override;
- post-change scans confirm the portable development default and
  `raw_immune*_unverified` Octo paths are gone from production startup, while
  broad `spell`, `cc` and `all` remain absent from
  `CANDIDATE_DIMENSIONS`. No broad-immunity promotion or unrelated feature
  work was introduced.

The required **live runtime matrix was not executable in this development
environment**. There is no attached WoW 1.12.1 client/server process, no live
vMaNGOS/Turtle/Octo combat stream, and no live HearthDB plugin instance here.
Source inspection and static control-flow review are not substitutes for those
runtime observations, so the following items are deliberately **not marked
PASS**:

- vMaNGOS 1.12.1 conservative replay: Blackwing Spellbinder HoJ, player targets
  under Blessing of Freedom/Protection, direct `IMMUNE2`, Sartura TempCC,
  temporary protection/reflection, NPC DR, recent death and split-CC cases;
- generalized vMaNGOS comparative inference: candidate creation/elimination,
  permanent confirmation, authoritative revocation/dynamic suspicion, known-fact
  fast paths and Learning SCT/UI transitions;
- other-caster live miss/damage/aura evidence plus the uncertain-DR reset case;
- repeated encounters and `/reload` proving facts/hypotheses persist while
  transient DR/death/aura state resets and no legacy learned write reappears;
- Turtle/Octo live raw `IMMUNE`/`IMMUNE2` replay confirming that the selected
  adapter receives the same semantics observed in the inspected family source.

No additional cleanup is justified before those live results. In particular,
Learning SCT/provenance diagnostics remain useful for the pending matrix, and
broad-immunity promotion remains explicitly out of scope.

Stop condition is therefore **not yet satisfied**: source-level compatibility
and a single shared inference engine are established, but both target
environments still need the documented live runtime matrix before Slice 8 can be
closed.

## Exact next step

Before continuing the remaining Slice 8 runtime matrix, implement only the
bounded **Immunity Learning Alerts** presentation/settings revision documented
under Slice 7 above. Do not change learner inference, storage, broad-immunity
rules or combat-observation semantics as part of that UI work.

Then resume **Slice 8 runtime validation** from code checkpoint
`e8634814e321a9bff23529875c2504e1fc2ac80e` in an environment with the actual
Vanilla clients/servers and HearthDB available.

Run the pending live matrix above first. If a runtime case fails, make only the
smallest cleanup/correction justified by that failure and rerun the affected
case. If the matrix passes, update this document to mark Slice 8 complete and
make the final docs-only handoff commit. Do not start broad-immunity promotion
or unrelated work.

The generalized learner's permanent-inference invariant remains:

```text
one remaining valid permanent cause + no transient explanation -> confirm
multiple remaining valid causes -> keep hypothesis unresolved
authoritative dimension-specific success -> permanent immunity disproved
credible confirmed immunity later disproved -> vulnerable + dynamic suspicion
```



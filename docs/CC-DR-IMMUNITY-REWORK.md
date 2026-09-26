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
- TOC version: `@project-version@`
- Latest known-good runtime before this correction:
  `aa2b761d1c45d1a28c8354b2f13f216a21403569` — immunitydebug local-scope
  runtime fix; that build started with no Lua errors.
- Current phase: the server outcome audit and first learner correction are
  complete, but a new player-target leak was found before focused validation.
  The corrected learner has **not** yet had a clean runtime validation pass.
- **Focused learner testing is paused again until the player-exemption micro-fix
  lands.** Do not return to the pre-correction generic `IMMUNE -> school`
  build.
- New anomaly: a player target appears to have learned permanent `physical`
  immunity after an NPC attempted movement CC while Blessing of Freedom was
  active. Static review confirms the direct `SPELL_MISS_SELF` learner lacks
  the `UnitIsPlayer` rejection already present in several older delayed
  learner paths.
- Blessing of Protection is already represented as temporary `physical`
  immunity. Blessing of Freedom is not yet represented as a typed temporary
  movement-impairment source.
- Portability target remains one learner for **vMaNGOS and Turtle/Octo**.
  vMaNGOS semantics are proven below. Turtle/Octo `IMMUNE`/`IMMUNE2`
  semantics remain an explicit compatibility assumption to verify; the
  vMaNGOS-specific positive inference is kept local to the direct miss learner.
- The generalized comparative learner has not started.

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
12. Do not begin the generalized comparative learner until the current learner
    has been observed against known real cases.
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

### Player-target immunity leak — FOUND

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

Static code review does prove the safety hole:

- bleed/non-bleed delayed verification already rejects `UnitIsPlayer`;
- delayed CC verification already rejects `UnitIsPlayer`;
- shared-debuff verification already rejects `UnitIsPlayer`;
- recorded immunity queries are already NPC-specific;
- the new direct `ProcessSpellMissSelf()` persistence path does **not**
  currently reject a player target before permanent learning.

That makes the direct `SPELL_MISS_SELF` learner the most plausible source of
the observed permanent player record.

Related temporary-aura state:

- Blessing of Protection is already curated as temporary `physical` immunity;
- because typed temporary `physical` state is resolved before recorded
  NPC-only school data, BoP can still correctly describe live physical immunity
  on a player without requiring any permanent player record;
- Blessing of Freedom is currently missing from the typed temporary immunity
  model and should provide temporary root/snare (movement-impairment) immunity.

Required rule:

```text
temporary player immunity is valid live state
permanent player immunity learning is never valid
```

This is a validation blocker because the learner has now demonstrated a path
that can pollute persistent immunity data with a player name.

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

### Blackwing Spellbinder — PENDING

Primary spell-vs-CC ambiguity regression case.

Required distinction:

```text
Hammer of Justice IMMUNE
    -> Holy/spell vs stun ambiguous from a generic spell-level result

physical stun
    -> remains independently eligible unless its own evidence proves immunity
```

A generic HoJ `IMMUNE` must not write either `holy` or `cc_stun` without
effect-specific evidence.

Broad `spell` promotion remains deferred to the generalized learner.

## Deferred

Do not begin during the current validation phase:

```text
generalized comparative immunity learner
candidate/disproved/confirmed evidence model
successful-hit elimination inference
broad-immunity promotion thresholds
learner evidence persistence
inferred broad-immunity persistence
Mob-ID migration of real immunity storage
automatic removal of inferred immunity
new public immunity grammar
```

These require a separate design decision after the existing learner has been
validated against real immunity cases.

## Exact next step

Before resuming the focused learner validation, land one small safety correction
for the newly discovered player-target leak.

Required correction:

1. add an early player-target rejection to the direct
   `ProcessSpellMissSelf()` learning path before any permanent immunity write;
2. audit every automatic `RecordImmunity` / `RecordCCImmunity` call path and
   confirm an equivalent player exclusion exists. The older delayed bleed,
   non-bleed, CC and shared-debuff routes already have explicit `UnitIsPlayer`
   guards; preserve them;
3. add Blessing of Freedom to the typed temporary-immunity model as
   movement-impairment immunity covering root + snare;
4. preserve Blessing of Protection as typed temporary `physical` immunity;
5. do **not** make player exemption suppress live temporary immunity queries:
   the rule is no permanent player learning, not "players can never currently
   be immune."

After that micro-fix lands, resume the previously planned focused validation:

1. load the addon and confirm no Vanilla-Lua startup/runtime error;
2. enable `/cleveroid immunitydebug` and clear old diagnostic evidence;
3. first reproduce/cover a player under Blessing of Freedom and Blessing of
   Protection and confirm no permanent player record can be written;
4. verify a generic `IMMUNE` on an NPC spell with no spell-level mechanic, no
   Dispel family and no target-creature restriction can still write its literal
   DBC school;
5. verify Frostbolt does **not** turn a generic result into a permanent snare or
   Frost write merely from the direct event;
6. verify Hammer of Justice on the Blackwing Spellbinder regression case writes
   neither Holy nor Stun from a generic `IMMUNE`;
7. verify an `IMMUNE2` event produces an immunitydebug rejection and no
   permanent write;
8. recheck TempCC, temporary protection/reflection, NPC DR, death and split-CC
   safeguards for regressions.

Record the raw miss code and learner decision/reason for each focused case.
If Turtle/Octo testing becomes available, first verify whether their
`IMMUNE`/`IMMUNE2` split matches the assumptions above before broadening
positive learning there.

Still do **not** implement:

- generalized cross-event comparative inference;
- loose time-window correlation;
- speculative effect-level learning from aura absence;
- new persistence categories;
- broad-immunity promotion.

The intended invariant remains:

```text
one remaining valid cause -> learn
multiple remaining valid causes -> ambiguous; learn nothing
```


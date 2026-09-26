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
- Current implementation commit:
  `edd53975621e452b29281603790565e7a98aa67c` — direct spell-level
  `IMMUNE` currently routes to school; this is now known to be too broad.
- TOC version: `@project-version@`
- Latest Vanilla-Lua runtime fix:
  `aa2b761d1c45d1a28c8354b2f13f216a21403569` — scope immunitydebug locals.
- Runtime after that fix starts with no Lua errors.
- Current phase: audit the three server-side immunity outcome paths, then
  correct the learner boundary from the resulting evidence map.
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

Numeric creature/aura/spell IDs are authoritative. Names are display/debug
information only.

Reflection, DR, death and similar explanations may reject a learning event but
must never become permanent immunity themselves.

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

Before `SPELL_GO` targets are written, the server checks the final effect mask.

If:

```text
effectMask == 0
```

then:

```text
missCondition = IMMUNE2
```

Therefore `IMMUNE2` means:

> every applicable spell effect for that target was removed as immune.

This is stronger evidence than a generic per-effect failure, but it still does
not necessarily identify the immunity dimension if multiple dimensions could
independently explain all effects failing.

##### `IMMUNE`

The server also performs a whole-spell immunity check using
`IsImmuneToSpell()`.

That path can include:

- dispel-type immunity;
- spell-school immunity;
- spell-level mechanic immunity;
- other whole-spell restrictions.

Therefore:

> `IMMUNE` is whole-spell immunity evidence, but not automatically
> school-immunity evidence.

The current direct learner remains too aggressive if it interprets every
`IMMUNE` as spell school.

#### Representative cases under the revised model

##### Frostbolt — Frost damage + snare

Static structure:

```text
Frost school
+ direct Frost damage
+ snare aura
```

If only the snare is immune:

```text
damage effect remains in effectMask
snare effect is removed
spell still counts as a hit
no separate IMMUNE is necessarily emitted
```

Therefore a Frostbolt slow immunity is **not** by itself a plausible explanation
for every generic whole-spell `IMMUNE`.

This materially weakens the earlier assumption that:

```text
Frostbolt IMMUNE -> { frost, snare }
```

must always be treated as ambiguous.

However `IMMUNE` still cannot immediately be equated with Frost immunity
because whole-spell immunity may arise through another whole-spell dimension.

Further classification of the `IMMUNE` path is required.

##### Rake — physical hit + bleed

Static structure:

```text
physical direct damage
+ bleed aura
```

Rake's bleed mechanic is stored on an individual Spell.dbc effect.

An effect-level bleed immunity may remove the bleed effect while allowing the
direct physical hit to land.

Positive runtime evidence can therefore distinguish:

```text
physical damage succeeded
bleed aura did not appear
```

but absence of the bleed alone still needs careful classification before
permanent learning.

##### Rupture — bleed with no independent direct hit

Rupture does not provide the same independent direct-hit evidence as Rake.

Its harmful effect can carry overlapping concepts such as:

```text
physical spell school
+ bleed mechanic
```

Even if the failed effect is known, the failed **dimension** may remain
ambiguous.

This remains an example where effect identification alone does not necessarily
permit permanent learning.

##### Hammer of Justice — Holy + stun

HoJ has no independent damage component.

Its relevant hostile effect is a stun carried by a Holy spell.

If the entire effect is rejected, the evidence may still have more than one
plausible whole-spell cause.

Do not assume:

```text
HoJ IMMUNE -> stun immune
```

or:

```text
HoJ IMMUNE -> holy immune
```

without narrowing the applicable immunity path.

##### Intercept — physical damage + stun

Intercept includes a trigger-spell relationship.

ClassicAPI currently provides the effect structure but does not expose the
triggered spell ID through the wrapper used by SCRM.

Nampower raw SpellRec data does expose `effectTriggerSpell`.

The eventual candidate builder may therefore need both APIs for complete static
decomposition.

The same runtime principle applies:

```text
damage success can positively eliminate some hypotheses
```

but generic `IMMUNE` alone does not identify the failed dimension.

##### Poison / Curse / Disease

ClassicAPI exposes these independently through the spell's dispel type.

Examples may therefore contain two separate static dimensions:

```text
Nature + Poison
Shadow + Curse
Shadow + Disease
```

These must remain independent learner categories.

Do not collapse:

```text
poison -> nature
curse -> shadow
disease -> spell school
```

A whole-spell `IMMUNE` may originate from either the dispel-family immunity
path or the school-immunity path.

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

#### Current conclusion

ClassicAPI is more useful than originally assumed, but not because it exposes
individual failure events.

Its value is:

```text
accurate static decomposition
+ authoritative aura-state verification
```

Nampower remains the stronger runtime source for:

```text
actual spell damage
+ explicit spell miss/immunity events
```

Neither source currently exposes:

```text
this exact Spell.dbc effect failed for this exact immunity reason
```

The important new finding is that the server often handles effect-level
immunity **silently**, while `IMMUNE` and `IMMUNE2` represent stronger
target/spell-level outcomes.

Therefore the previous proposed correction:

```text
generic IMMUNE
-> enumerate every school/effect/mechanic candidate in the spell
-> if multiple, learn nothing
```

is itself too coarse.

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

Audit the three server-side immunity outcome paths and map each one to the
immunity dimensions that can actually produce it.

Do this **before changing the learner again**.

The three outcomes to distinguish are:

```text
1. silent individual effect rejection
2. SPELL_MISS_SELF IMMUNE
3. SPELL_MISS_SELF IMMUNE2
```

For each outcome, trace the relevant vMaNGOS checks and determine whether it can
be caused by:

- school immunity;
- damage immunity;
- dispel-family immunity;
- spell-level mechanic immunity;
- per-effect mechanic immunity;
- aura-state immunity;
- effect-type immunity.

Then validate the result against the representative spells:

- Frostbolt;
- Rake;
- Rupture;
- Hammer of Justice;
- Intercept;
- poison;
- curse;
- disease where relevant.

For every representative spell, record:

```text
static immunity dimensions
server failure path
Nampower event produced
ClassicAPI evidence available
what the event proves
what remains ambiguous
whether permanent learning is safe
```

The key question is no longer:

```text
what immunity dimensions does this spell contain?
```

It is:

```text
which immunity dimensions are capable of producing the exact runtime outcome we observed?
```

Only after that mapping is complete should the minimal learner correction be
designed.

The intended learner rule remains:

```text
one remaining valid cause -> learn
multiple remaining valid causes -> ambiguous; learn nothing
```

Do not yet implement:

- generalized cross-event comparative inference;
- loose time-window correlation;
- speculative effect-level learning from aura absence;
- new persistence categories unless the audit proves they are required.

Preserve all existing TempCC, temporary-protection, reflection, DR, death,
split-CC, persistence, and public macro safeguards.

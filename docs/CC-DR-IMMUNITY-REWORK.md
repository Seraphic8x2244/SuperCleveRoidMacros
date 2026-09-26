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
- Current phase: audit available per-effect evidence, then correct the learner
  boundary.
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

### Immunity learner boundary — DESIGN REVISED, IMPLEMENTATION PENDING

Do not classify permanent immunity from spell identity alone. Learn only the
dimension proven by the observed effect result.

Core rule:

```text
unique failed dimension   -> learn it
multiple plausible causes -> ambiguous; learn nothing
```

Examples:

```text
Frostbolt: Frost damage + snare
damage specifically immune        -> frost
damage lands, snare fails         -> cc_snare
undifferentiated IMMUNE           -> ambiguous

Rake: physical hit + bleed
hit specifically immune           -> physical
hit lands, bleed fails            -> bleed
combined/undifferentiated IMMUNE  -> ambiguous

Rupture: no independent hit; bleed is the damage effect
generic IMMUNE                    -> physical vs bleed ambiguous

Hammer of Justice: Holy + stun, no damage
generic IMMUNE                    -> holy vs stun ambiguous

Intercept: physical damage + stun
damage specifically immune        -> physical
damage lands, stun fails          -> cc_stun
undifferentiated IMMUNE           -> ambiguous
```

The same principle applies to other effect families:

```text
poison immunity != nature immunity
curse immunity  != shadow immunity
disease immunity remains independent if supported
```

The original Frostbolt failure exposed a general learner-boundary bug:

```text
Hydrospawn + Frostbolt
IMMUNE -> incorrectly learned cc_snare
```

The first correction stopped direct `IMMUNE` from selecting the CC write path,
but the current implementation then went too far in the opposite direction by
routing generic direct `IMMUNE` to school immunity.

That implementation is not the final learner design.

CC/effect persistence requires evidence that the actual secondary effect failed.
School persistence likewise requires evidence that the school/action component
is the uniquely identified failure. An undifferentiated whole-action `IMMUNE`
must not choose between plausible dimensions.

Preserve the existing split-CC, death, TempCC, temporary-protection/reflection,
DR and queryable-target safeguards.

No generalized comparative learner or broad-immunity promotion is part of this
correction.

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

Audit what Nampower/combat-log evidence actually distinguishes individual effect
failure from whole-action `IMMUNE`, then revise the current learner around that
evidence boundary.

Implementation rule:

```text
unique failed dimension   -> learn it
multiple plausible causes -> ambiguous; learn nothing
```

Key regression cases after implementation:

```text
Hydrospawn + Frostbolt
Rake
Rupture
Blackwing Spellbinder + HoJ
Intercept
poison-immune target
curse-immune target
```

During regression testing also confirm:

```text
TempCC remains temporary
temporary protection/reflection does not persist
DR and death do not become permanent immunity
split-CC safeguards remain intact
existing persistence and public macro syntax remain unchanged
```

Do not begin the generalized comparative learner until the corrected per-event
learner boundary has been implemented and observed against these cases.

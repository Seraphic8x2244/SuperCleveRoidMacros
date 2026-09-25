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
- Branch head before this documentation cleanup:
  `10f32b2f08a6567eb64c98bc97847b7be82257fd`
- TOC version: `@project-version@`
- Latest Vanilla-Lua runtime fix:
  `aa2b761d1c45d1a28c8354b2f13f216a21403569` — scope immunitydebug locals.
- Runtime after that fix starts with no Lua errors.
- Current phase: live validation of the existing immunity learner and temporary
  immunity safeguards.
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
bleed
```

`unknown` may exist as a storage fallback but is not a queryable immunity
dimension.

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

The direct `SPELL_MISS_SELF` path is authoritative when available. Only
`IMMUNE`/`IMMUNE2` results may reach real immunity learning; ordinary
MISS/RESIST/DODGE/PARRY/BLOCK results do not teach permanent immunity.

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

### Hydrospawn / Frostbolt — FAIL: mixed school + CC classification

Observed with Frostbolt:

```text
Frostbolt returned IMMUNE
cc_snare was learned
frost immunity was not learned
```

Current direct `SPELL_MISS_SELF IMMUNE` logic chooses an exact CC immunity when
the spell exposes a learnable CC mechanic, otherwise it learns the spell school.
Frostbolt exposes `snare`, so the CC path wins and the Frost-school path is
never reached.

This is a confirmed classification problem for spells that combine a damage
school with a CC effect. Do not fix it by blindly recording both dimensions.
Capture/review the immunitydebug trace for a representative case before
changing learner semantics.

### Blackwing Spellbinder — PENDING

Primary broad-spell-immunity regression case.

Required distinction:

```text
magical actions such as HoJ -> IMMUNE
physical stuns              -> can remain eligible
```

The test must confirm that broad spell immunity does not become false permanent
stun immunity.

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

Continue live immunity sampling without changing learner or persistence
semantics.

Finish the Anti-Magic Shield validation when convenient:

```text
verify an appropriate Physical action remains eligible while the shield is active
verify no permanent Frost/Holy/Stun immunity was written from the temporary state
```

Before changing learner semantics, capture/review an immunitydebug trace for a
mixed school + CC failure such as Hydrospawn/Frostbolt.

Next major regression case:

```text
Blackwing Spellbinder with immunitydebug enabled
```

Then inspect:

```text
CleveRoids_ImmunityDebug
CleveRoids_ImmunityData
```

Decode the schema-v1 journal and verify that:

```text
the expected evidence reached the real learner
temporary safeguards behaved correctly
the learner accepted/rejected the observation for the correct reason
persisted immunity matches the learner decision
```

Do not begin the generalized learner until these validation cases are understood.

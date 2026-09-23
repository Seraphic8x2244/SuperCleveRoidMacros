# Immunity Framework Development

Active implementation/recovery document for the **framework stage** of the
CC/DR/immunity rework.

The durable design and historical reasoning remain in
`docs/CC-DR-IMMUNITY-REWORK.md`.

The active mouseover/camera-drag sidequest is documented separately in
`docs/MOUSEOVER-WORLDFRAME-DEV.md`. Use that document as the source of truth for
mouseover consolidation and WorldFrame-action suspension semantics.

## Recovery snapshot

- Branch: `design/temp-cc-immunity`
- Base: `main`
- Branch head before this status refresh: `ad653f5401eb8c67e97e7f3e8a80d3a6934b307b`
- Branch relation before this status refresh: 137 ahead / 0 behind `main`
- TOC version: `@project-version@`
- Latest framework/runtime behavior commit: `c23a80c4cff5d64765b25464b88738fdf93bfa31`
- Latest immunity UI runtime commit: `6726ce1e39332581ba9145bad954341f0bd439d0`
- Recent commits:
  - `ad653f54` — Save immunitydebug journal
  - `602a3c27` — Persist immunitydebug controls
  - `44651eed` — Make immunitydebug a learner snooper
  - `3bbb7dd2` — Revise immunitydebug snooper design
  - `da741af8` — Document immunitydebug implementation status
  - `1d1b8116` — Add immunitydebug slash command
  - `d3efe5de` — Add runtime immunity debug diagnostics
  - `99963d76` — Close mouseover cast acceptance
  - `cac16d5e` — Record unit-frame and cast live pass
  - `53280257` — Track WorldFrame mouse scripts safely
  - `5a7388cd` — Record protected hook removal
  - `b24c0f3a` — Document protected hook removal
  - `93f1f69a` — Remove protected WorldFrame hooks
  - `7b9112eb` — Record mouseover protected-hook failure
  - `717da83c` — Record protected hook live-test failure
  - `ed777632` — Unify macro mouseover resolution
  - `49da0702` — Route target validation through mouseover resolver
  - `2be9746b` — Suspend mouseover during WorldFrame actions
  - `2c0a0ae3` — Refresh immunity recovery snapshot
  - `d5902db0` — Refresh mouseover recovery snapshot
  - `9e3574c2` — Link mouseover sidequest handoff
  - `e795de92` — Document mouseover WorldFrame sidequest
  - `7aa64375` — Record mouseover camera-drag investigation
  - `6726ce1e` — Add rotating target model to immunity UI
  - `d737fb87` — Queue target model UI pass
  - `3a6a2f88` — Record historical false immunity provenance
  - `39d05b95` — Record explicit miss immunity fix status
  - `2e0edc18` — Clarify shared miss immunity authority
  - `c23a80c4` — Stop generic shared misses learning immunity
  - `4c6d7946` — Require explicit miss reason for immunity learning
  - `e04d5c21` — Record false immunity learning diagnosis
  - `9cd181fa` — Fix immunity scroll offset and modal layering
  - `53493d85` — Record immunity UI scroll and icon test state
  - `fd366a56` — Fix immunity scrolling and add header icons
  - `0666d34a` — Fix immunity UI placement comment newline
  - `bdcd6977` — Refresh immunity UI live-test handoff
  - `f362b465` — Center immunity UI composite at 1024 width
  - `6c49e979` — Harden immunity UI for Vanilla layout
  - `9270bb99` — Add immunities slash command

### Implementation checkpoint — immunitydebug

- Branch: `design/temp-cc-immunity`
- Revision handoff: `3bbb7dd219dac175d4cf604b586ae43245a0f9e9`.
- Corrected implementation commits: `44651eed` (pure snooper +
  journal instrumentation), `602a3c27` (persistent command controls), and
  `ad653f54` (diagnostic SavedVariables declaration).
- Completed: removed the debug-owned `suspects` / `disproved` model and all
  generic `SPELL_GO` success inference; instrumented the real direct
  `SPELL_MISS_SELF` IMMUNE/IMMUNE2 safeguard/decision path; instrumented actual
  `Record*Immunity` writes and `Remove*Immunity` removals; persisted the
  debug enable preference; added schema-v1 append-oriented
  `CleveRoids_ImmunityDebug`; added `/cleveroid immunitydebug clear`; retained
  compact chat output only for real learner decisions and real persistence
  transitions.
- Static-checked: the handoff-to-implementation comparison is exactly three
  commits and changes only `Utility.lua`, `Core.lua`, and
  `SuperCleveRoidMacros.toc`; no conditional grammar, real
  `CleveRoids_ImmunityData` schema, learner safeguard order, generalized
  learner, or polling loop changed. Debug instrumentation returns immediately
  while disabled and its journal/display work is `pcall`-isolated while
  enabled, so a diagnostic error cannot abort or redirect the learner path.
  The old generic-success debug hook is absent. No GitHub CI/status checks are
  configured for the implementation head.
- Untested: all immunitydebug live acceptance items remain live-pending; no
  scarce raid observation has been consumed by this corrected implementation.
- Deferred: generalized learner/evidence persistence, Mob-ID migration of real
  immunity storage, inferred broad-immunity persistence, new public immunity
  grammar, diagnostic retention/pruning policy, and any dump/copy UI.
- Exact next step: after this static-reviewed handoff is committed, do only the
  cheap plumbing checks first (enable persistence across reload/login and
  explicit journal clear), then begin the scarce live immunity acceptance
  observations against a deliberately clean test dataset.

### Immunitydebug revision — snooper + persistent test journal — 2026-09-23

The first immunitydebug implementation is **not ready for raid testing as-is**.
Its runtime `suspects` / `disproved` model independently interprets evidence.
That violates the revised design below and must be corrected before scarce,
non-repeatable raid observations are collected.

#### Defining principle

**Immunitydebug is a snooper/instrumentation layer over the real immunity
learner. It is not a second learner.**

The debug feature must observe the existing learner's real inputs, safeguards,
decision path, persistence/removal calls, and resulting authoritative immunity
state. It must not independently classify evidence into its own immunity
hypotheses, maintain a parallel immunity model, or reach conclusions the learner
itself has not reached.

Consequences:

- existing `CleveRoids_ImmunityData` is always the source of truth for learned
  immunity knowledge and therefore for red/current-known state;
- debug may expose unresolved/transient learner state only when that state
  actually exists in the learner; it must not invent yellow/green state by
  running a parallel inference path;
- after reload/login, current learned knowledge is reconstructed naturally from
  the real immunity records, not from debug state;
- debug on/off must have zero effect on what the learner learns, removes,
  confirms, rejects, queries, or exposes through conditionals;
- instrument the learner at meaningful decision points rather than duplicating
  its classification logic.

#### Persist the debug enable setting

For the raid-testing campaign, immunitydebug should remain enabled across
`/reload`, logout, and login until explicitly disabled with
`/cleveroid immunitydebug 0`.

This is a diagnostic preference only. Persisting the enable flag must not
persist a second immunity model.

#### Persistent machine-oriented diagnostic journal

Add a dedicated SavedVariables diagnostic journal, separate from
`CleveRoids_ImmunityData` and separate from real learner state.

The journal exists because raid observations can be lockout-limited and
non-repeatable. Its purpose is to preserve enough raw evidence and learner
decision information for later inspection even after reload/logout or across
several days of testing.

The journal is primarily for development analysis, not human readability:

- include an explicit schema/version key (for example `v = 1`);
- use compact deterministic field names and event/decision/reason codes;
- document the complete decoder in this file so a future development chat can
  decode a pasted SavedVariables section without relying on conversation
  memory;
- use the real numeric values wherever they already exist: numeric Mob ID,
  spell ID, CC/mechanic ID, school mask/category ID, miss result, aura ID, etc.;
- compact codes are appropriate only for diagnostic concepts such as journal
  event type, learner decision, safeguard/rejection reason, and state
  transition.

Do not merely journal the rendered chat line. Record the evidence and the
learner's actual handling of it. Where available, a record should preserve:

```text
absolute timestamp
session identifier / session-relative time where useful
target GUID
numeric Mob ID
localized NPC name (supplemental display/debug identity)
spell ID
raw authoritative event/result
learner-relevant immunity dimensions/types using native numeric IDs where possible
safeguards actually checked and the resulting reason/decision
real persistence/removal action, if any
authoritative before/after immunity state where useful
```

Rejected/ignored evidence is important and must also be journalled when it
passes through the instrumented learner path. Examples include temporary
immunity aura, TempCC, death, DR, reflection/protection guard, split-CC handling,
and inconclusive/no-query-unit cases. This allows later diagnosis of false
negatives as well as false positives.

The journal should be append-oriented during this testing phase and should not
be aggressively pruned. A retention policy can be designed after the framework
is validated.

Provide an explicit clear operation (planned shape:
`/cleveroid immunitydebug clear`) so a clean test dataset can be deliberately
started. A dump/copy UI is optional; pasting the SavedVariables journal itself
is sufficient as long as the schema is documented.

#### Relationship between chat colors and learner state

The existing red/yellow/green presentation may remain useful, but its meaning
must be driven by the learner rather than by debug-owned inference:

- **red**: real current persisted immunity data records the category as immune;
- **yellow**: only if the real learner itself has a relevant unresolved/candidate
  state at that point; debug must not create one merely for display;
- **green**: only when the learner's actual authoritative processing positively
  disproves/removes a relevant immunity state; debug must not independently
  infer a disproval from generic success.

If the current learner has no persistent/transient concept corresponding to a
yellow or green state, the snooper should report the actual learner decision
instead of manufacturing that state.

#### Scope boundary

This revision intentionally permits **diagnostic** SavedVariables for the
enable preference and journal. It does not authorize any change to the schema
or semantics of `CleveRoids_ImmunityData`, learner evidence persistence,
generalized comparative learning, inferred broad-immunity persistence, Mob-ID
migration of real immunity storage, or public conditional grammar.

No polling or high-frequency `OnUpdate` is authorized.

#### Required correction before live raid testing

Audit and revise commits `d3efe5de` / `1d1b8116` before using immunitydebug
for raid evidence:

1. remove or neutralize the debug-owned `suspects` / `disproved` learning
   model and any independent success-based inference;
2. retain useful presentation only where it reflects real learner state;
3. instrument the existing learner's authoritative evidence/safeguard/decision
   path;
4. add the persistent enable preference;
5. add the versioned machine-oriented SavedVariables journal and document its
   exact field/code dictionary here as part of implementation;
6. add explicit journal clear handling;
7. static-review that debug enabled vs disabled cannot change learner outcomes;
8. only then begin the scarce live raid acceptance tests.

All previous immunitydebug acceptance items remain **live-pending**. The old
requirements that the debug flag/state be entirely runtime-only and that no
immunitydebug SavedVariables exist are superseded by this revision.

#### Implemented diagnostic journal schema v1 — decoder

The implementation uses the dedicated SavedVariable
`CleveRoids_ImmunityDebug`. It is diagnostic state only; the learner never
queries it when deciding immunity.

Top-level shape:

```text
v   schema version; currently 1
en  persistent immunitydebug enable preference: 0 off, 1 on
ns  monotonically incremented addon-load/session counter
e   append-oriented array of journal records
```

A schema mismatch deliberately starts a fresh diagnostic journal with
`v = 1`, `en = 0`, `ns = 0`, and an empty `e` array. This reset applies
only to diagnostic state and never touches `CleveRoids_ImmunityData`.
`/cleveroid immunitydebug clear` clears only `e`; it preserves `v`, `en`,
and `ns`.

Common record fields:

```text
t   absolute Unix-style timestamp from time(); 0 only if that API is unavailable
s   session identifier copied from top-level ns
r   milliseconds since the current addon load
e   diagnostic event code
g   target GUID string, when known
m   numeric creature/Mob ID from UnitCreatureID, when the target is queryable
n   localized NPC name, when known
p   numeric spell ID, when known
sc  raw Spell.dbc school enum for p, when available
sm  raw spell-level Spell.dbc mechanic ID for p, when available
em  three-element raw effect-mechanic array for p, when available
```

The raw school enum in `sc` follows the existing Vanilla/Nampower mapping:
`0=Physical`, `1=Holy`, `2=Fire`, `3=Nature`, `4=Frost`,
`5=Shadow`, `6=Arcane`. `sm` and `em` are unmodified DBC mechanic IDs,
not debug-owned classifications. Relevant exact learned-CC mechanics currently
include `1=Charm`, `2=Disorient`, `5=Fear`, `7=Root`, `9=Silence`,
`10=Sleep`, `11=Snare`, `12=Stun`, `13=Freeze`, `14=Knockout`,
`17=Polymorph`, `18=Banish`, `20=Shackle`, `24=Horror`, and
`27=Daze`.

Event code `e`:

```text
1  learner decision / rejection / exclusion observation
2  real learned-immunity persistence write occurred
3  real learned-immunity removal occurred
```

Decision records (`e = 1`) may additionally contain:

```text
x   raw SPELL_MISS result code
q   learner-decision code
z   rejection/exclusion reason code
i   learner's canonical immunity type string when one was actually resolved
dr  learner's existing DR bucket string when applicable
u   numeric aura spell ID responsible for a temporary/guard rejection
c   numeric auxiliary value; schema v1 uses this for the observed DR hit count
h   textual auxiliary value; schema v1 uses this for the guard-aura type
```

Raw `x` values follow Nampower's existing miss constants:
`1=MISS`, `2=RESIST`, `3=DODGE`, `4=PARRY`, `5=BLOCK`, `6=EVADE`,
`7=IMMUNE`, `8=IMMUNE2`, `9=DEFLECT`, `10=ABSORB`, `11=REFLECT`.
The authoritative automatic immunity learner is instrumented on
`IMMUNE/IMMUNE2`; `REFLECT` is journalled as an explicit non-immunity
exclusion.

Decision code `q`:

```text
0  rejected / ignored by the immunity learner
1  accepted for the real CC-immunity write path
2  accepted for the real school/general-immunity write path
3  explicitly excluded from immunity learning
```

Reason code `z`:

```text
0  no rejection reason; accepted learner path
1  missing target identity and/or spell identity
2  split-CC safeguard
3  target GUID was recently recorded dead
4  target is currently dead
5  curated TempCC aura explains the immunity
6  broad protection/reflection guard aura makes the observation inconclusive
7  NPC-applicable DR safeguard
8  no queryable target unit; aura checks cannot be completed
9  REFLECT result; explicitly not immunity
```

The existing learner-native `dr` values are not diagnostic codes. Current
stun safeguards can report `stun_control`, `stun_trigger`, or
`stun_kidneyshot`. Likewise `i` is the learner's canonical immunity type,
not a separate debug hypothesis.

Mutation records (`e = 2` or `e = 3`) may additionally contain:

```text
k   exact real CleveRoids_ImmunityData storage key affected, e.g. cc_stun/fire
b   authoritative recorded-state presence immediately before mutation: 0/1
f   authoritative recorded-state presence immediately after mutation: 0/1
h   optional mutation detail; schema v1 uses this for a conditional buff name
```

The mutation event is emitted only after the real persistence/removal function
has actually changed `CleveRoids_ImmunityData`. A mutation record can omit
`p`, `g`, or `m` when that information is not available at the persistence
call site; the corresponding decision record retains the authoritative spell
input and GUID when known.

#### Static review of the corrected snooper — 2026-09-23

- `suspects`, `disproved`, `ImmunityDebugObserveImmune`,
  `ImmunityDebugObserveSpellSuccess`, `ImmunityDebugMarkDisproved`, and
  `ImmunityDebugRefresh` are absent from the corrected implementation.
- The generic `SPELL_GO numHit > 0` debug-success block was deleted; debug no
  longer interprets successful casts as immunity evidence.
- The direct IMMUNE/IMMUNE2 learner keeps its pre-existing decision order:
  identity resolution, split-CC, death, TempCC, broad guard aura, DR,
  queryability, then the existing real `RecordCCImmunity` or
  `RecordImmunity` call.
- Diagnostic calls on rejected branches occur immediately before the existing
  return. Accepted decision records are emitted only after the unchanged real
  record function has run.
- Red chat output is emitted only by an actual real immunity write; green only
  by an actual real immunity removal. This learner has no matching candidate
  state for the old yellow display, so no yellow state is manufactured.
- Every runtime journal/display entry point returns immediately when
  immunitydebug is disabled. When enabled, journal/display code is wrapped in
  `pcall`; its failure cannot prevent the existing learner write, removal, or
  rejection path from completing.
- The only new SavedVariable is `CleveRoids_ImmunityDebug`; the format and
  semantics of `CleveRoids_ImmunityData` are untouched.
- No new `OnUpdate`, polling loop, generalized evidence store, public
  conditional, or real learner inference was added.
- Compare `3bbb7dd2...design/temp-cc-immunity` before this documentation commit:
  three commits ahead, zero behind, with changes limited to `Utility.lua`,
  `Core.lua`, and `SuperCleveRoidMacros.toc`.
- Branch relation to `main` at the reviewed implementation head:
  137 ahead / 0 behind. GitHub reports no configured commit status checks.
- This is static review only. All live acceptance items remain unpassed until
  observed in WoW.

### Resume status — 2026-09-22

Completed / implemented:

- implemented `/cleveroid immunities` as the framework testing/management UI;
- added a movable Vanilla-style Lua-created `SCRM Immunities` main window;
- added horizontally scrollable CC columns with canonical Vanilla mechanic IDs,
  recorded mob lists, and per-column counts;
- added horizontally scrollable All / Spell / Physical / school / Bleed columns;
- kept legacy `unknown` records in a separate diagnostic area;
- added the attached `Current Target` companion panel on the right of the main
  window;
- current-target inspection separates recorded/conditional state from live
  temporary/current-state immunity and exposes source/detail provenance;
- reflection is exposed only as a non-immunity explanation;
- target state refresh is event-driven through target/aura/world events; no new
  `OnUpdate` poll was added;
- immunity-data mutations notify the UI through a narrow refresh bridge;
- added selective CC clears, selective spell/general clears, full-category
  clears, and full learned-immunity clear;
- added manual whole-dataset Backup controls beside the destructive controls;
- added manual backup history under `CleveRoidMacros.immunityBackups`, with
  dated labels, data-version metadata, explicit Restore, and explicit Delete;
- loaded `ImmunityUI.lua` between `Utility.lua` and `Core.lua`;
- added the slash-dispatch/help entry for `/cleveroid immunities`;
- centered the 1014 px combined main + attached-target footprint so its initial
  placement fits inside a 1024-wide UI with a small margin;
- added representative Vanilla spell icons to every CC and spell-immunity column
  header via `C_Spell.GetSpellTexture(spellID)`; examples include Seduction for
  Charm, Exorcism for Holy, and Fireball for Fire;
- replaced the ambiguous native horizontal-scroll inversion with an explicit
  left-origin content offset: slider value 0 keeps the first columns at the left,
  and increasing the slider physically offsets the column strip left to reveal
  later columns on the right;
- raised Clear and Backup History modal frames by an explicit 50 frame levels
  over their parent so header icons/content behind them cannot draw above the
  modal backdrop;
- made Nampower `SPELL_MISS_SELF` the authoritative automatic immunity-learning
  source whenever direct miss events are available;
- prevented delayed missing-aura verification from persisting permanent
  immunity for bleed, non-bleed personal debuffs, CC, and shared debuffs when
  `CleveRoids.usingSpellMissEvents` is true;
- prevented text-only school immunity messages from persisting immunity when
  direct numeric `SPELL_MISS` events are available;
- retained the old missing-aura/text heuristics only as legacy fallback paths
  for environments without direct `SPELL_MISS` support.
- added a cosmetic `PlayerModel` to the Current Target panel using
  `SetUnit("target")`;
- added slow target-model rotation at one revolution per 12 seconds;
- rotation attaches only while the immunity UI is shown with a valid target and
  is explicitly detached on no-target, model failure, or UI hide;
- moved target identity text beside the model and now displays Name, Mob ID,
  Level, Creature Type, and Classification (Normal/Elite/Rare/Rare Elite/Boss);
- shifted the Recorded CC / Recorded Spell / live-state lists downward to make
  room for the model without changing the overall 300 x 690 target-panel
  footprint or immunity-learning logic.
- implemented the separate mouseover WorldFrame sidequest runtime slice in
  `2be9746b`, `49da0702`, and `ed777632`: post-hooked WoW's left/right
  WorldFrame actions, added one canonical mouseover resolver with suspension
  semantics, and routed normal execution, `IsValidTarget`, conditional
  `/target`, and `/pfcast` through it without changing immunity behavior.

Static-checked:

- UI/framework wiring has been reviewed without finding generalized
  learner/evidence state or new high-frequency polling;
- `ImmunityUI.lua` avoids Lua 5.1-only length/select patterns and uses Vanilla
  event globals (`event`, `arg1`) in its script handlers;
- the relevant UI calls used by this surface are consistent with the 1.12-era
  FrameXML API surface reviewed for this work;
- the 1024-wide initial-position correction is geometry-checked;
- `C_Spell.GetSpellTexture(spellID)` was already used by the addon runtime in
  `Utility.lua`, so the column icons reuse an established API path;
- post-write source review confirms `9cd181fa` starts each horizontal control
  at offset 0 and moves the scroll child left with a negative X anchor as the
  slider value increases;
- post-write source review confirms both modal boxes explicitly set a frame
  level 50 above the main panel;
- Nampower miss constants are independently mapped as MISS=1, RESIST=2,
  DODGE=3, PARRY=4, BLOCK=5, EVADE=6, IMMUNE=7, IMMUNE2=8, DEFLECT=9,
  ABSORB=10, REFLECT=11; crit is not a `SPELL_MISS` outcome;
- static write-path review found four legacy absence learners (bleed,
  non-bleed, CC, shared) plus one text-only school fallback; all are now gated
  away when direct `SPELL_MISS` events are active;
- the shared-debuff path previously treated generic `SPELL_GO` misses as
  candidates for immunity despite `SPELL_GO` lacking a miss reason, which can
  explain false Holy/Physical records from ordinary misses/resists/avoidance.
- historical audit shows this unsafe shape predates the current framework
  branch: `4c00ade6` (2026-02-07) explicitly annotated pending CC/shared
  verification with binary `SPELL_GO` hit/miss and sent misses onward to the
  immunity verifier; earlier/later history also contains dedicated false-
  immunity fixes (`8f1e2166` on 2026-01-16 and `719021ff` on 2026-03-27);
  therefore existing SavedVariables may contain months-old contamination and
  cannot be used alone to prove the current branch still learns false entries.
- target-model source review confirms the cosmetic spinner is isolated to
  `ImmunityUI.lua`, uses no immunity mutations, and adds no always-on poll;
- target-model `OnUpdate` is installed only for a visible valid target and is
  removed when the main window hides or the target/model becomes unavailable;
- target model is frame-level +1 inside the target panel while the Clear and
  Backup History modals remain +50 over the parent, preserving the modal
  layering fix;
- Vanilla API references were checked for `PlayerModel:SetUnit`,
  `PlayerModel:SetRotation`, `UnitCreatureType`, and `UnitClassification`;
- no CI workflow/status was attached to `6726ce1e`; verification so far is
  source/API static review only.
- mouseover runtime source audit confirms no raw LMB/RMB polling or new
  `OnUpdate` was added; stored mouseover sources are suspended rather than
  cleared during WorldFrame actions;
- compare from `9e3574c2` through mouseover runtime head `ed777632` shows
  only `Utility.lua`, `Conditionals.lua`, `Core.lua`, and the two handoff
  docs changed; no immunity-learning or immunity SavedVariables code changed;
- no GitHub CI workflow/status is attached to `ed777632`;
- first WoW test of the mouseover slice reported ClassicAPI being blocked from
  an action restricted to Blizzard UI; the cause was the attempted
  `hooksecurefunc` wrapping of the four protected WorldFrame movement/action
  globals;
- those four hooks were removed in
  `93f1f69a664907a67d37d78413738e69b3585dd3`;
- `532802577f2b5d56b9a9ad88318abe0e58a83170` restores WorldFrame
  suspension through `WorldFrame:HookScript("OnMouseDown"/"OnMouseUp")`
  without wrapping the protected movement/action globals;
- user live-tested both LMB and RMB WorldFrame paths successfully: mouseover
  works before the click, is suppressed while either button is held in the 3D
  world even if camera/mouselook movement would put the hidden cursor over a
  unit, and resumes after release;
- pfUI/unit-frame clicks are live-confirmed not to interfere with mouseover;
- the user's real macro usage is `/cast`, and that path is live-confirmed.
  Conditional `/target`, `IsValidTarget("mouseover", ...)`, and `/pfcast`
  remain static-checked/deferred rather than requiring unnecessary live tests.
- @mouseover investigation (no behavior change yet): SCRM maintains a
  priority-ordered synthetic mouseover aggregate (unit-frame sources > native
  UPDATE_MOUSEOVER_UNIT > tooltip) and may call `SetMouseoverUnit` itself;
- Vanilla `UPDATE_MOUSEOVER_UNIT` is not a reliable "mouseover became nil"
  notification for 3D-world hover, so the stored native source can outlive the
  game's visible cursor state;
- current consumers independently re-resolve mouseover through combinations of
  `UnitExists("mouseover")`, `CleveRoids.mouseoverUnit`,
  `pfUI.uf.mouseover.unit`, and (for /pfcast) `GetMouseFocus`, which permits
  stale/synthetic hover state to intercept a clause while the cursor is hidden;
- SCRM currently has no camera-control guard around @mouseover;
- the preferred design under discussion is to post-hook the exact protected
  WorldFrame actions `CameraOrSelectOrMoveStart/Stop` (left-button
  camera/select) and `TurnOrActionStart/Stop` (right-button turn/action), then
  make one central mouseover resolver return nil while either action is active;
  this is more precise than gating on raw `IsMouseButtonDown`, which would
  also suppress legitimate UI-frame clicks;
- ClassicAPI already provides `hooksecurefunc` and `IsMouseButtonDown`;
  current SCRM requires ClassicAPI >= 1.15.8, while the held-button API predates
  that requirement. `IsMouselooking` alone is insufficient because it covers
  right-button mouselook but not left-button camera orbit.

Live-tested:

- the immunity UI opens on the target client;
- the original pre-`fd366a56` horizontal mapping started on the left but moved
  the subheaders right, exposing empty space instead of later columns;
- the `fd366a56` inversion was also tested and confirmed wrong: it started on
  the right and still moved the subheaders right, so the inverted direction and
  start point cancelled the intended correction;
- representative header icons render in the client;
- the pre-`9cd181fa` modal layering is confirmed wrong: header icons from the
  panel behind can render above the overlay/modal boxes.

Untested / outstanding:

- mouseover user-facing `/cast` acceptance is complete: normal world/pfUI
  mouseover, LMB/RMB WorldFrame suppression, release/resume, and unit-frame
  click preservation are live-passed; unused `/target`, `IsValidTarget`, and
  `/pfcast` parity tests remain deferred;
- live-test the new `6726ce1e` target model: model renders for ordinary NPCs,
  rotates at a comfortable speed, changes promptly with target, and stops while
  the immunity window is hidden;
- verify Name, Mob ID, Level, Type, and Classification formatting for normal,
  elite/rare/boss, player, and no-target cases;
- verify the reduced Recorded CC / Recorded Spell list heights remain practical
  and that the model stays below Clear/Backup modal overlays;
- live testing found false learned immunities on ordinary mobs, including
  Physical, Snare, Stun (Riverpaw Scout), and multiple Holy records;
- provenance of those specific stored entries is unknown; they may have been
  learned by an earlier build rather than the current framework;
- the false records already present in SavedVariables cannot be safely
  auto-pruned because the existing storage does not distinguish manual records
  from automatically learned records; use Backup then clear the affected
  categories (or all learned immunity data) before the clean retest;
- verify ordinary MISS, RESIST, DODGE, PARRY and BLOCK outcomes do not create
  any new school or CC immunity records after `c23a80c4`;
- specifically retest Riverpaw Scout with stun/snare-capable actions and confirm
  no permanent Stun/Snare entry appears unless the server reports
  IMMUNE/IMMUNE2;
- retest representative Holy and Physical debuffs/attacks on ordinary mobs and
  confirm no school record is learned from an ordinary miss or missing aura;

- verify `9cd181fa` now starts both horizontal sections on the left and moves
  the subheaders left to reveal later columns as the slider moves right;
- verify `9cd181fa` keeps all background/header icons below both Clear and
  Backup History overlays;
- verify the representative icon choices and header spacing remain readable,
  especially `14 Knockout (Sap)`;
- verify main/target panel dragging and vertical list controls at practical UI
  scales/resolutions;
- verify target and aura events refresh the Current Target panel as expected;
- verify manual Backup, history browsing, Restore, Delete, and each selective
  clear path persist correctly across reload/logout;
- complete the existing live framework regression matrix:
  - Sartura: live Stun appears only during Whirlwind 26083;
  - forced HoJ during Whirlwind does not create permanent `cc_stun`;
  - Divine Shield / Divine Protection / Ice Block appear as live All;
  - Anti-Magic Shield appears as live Spell;
  - Blessing of Protection appears as live Physical;
  - reflection appears only as an explanation/guard;
  - Blackwing Spellbinder can be inspected as permanent broad Spell immunity
    without falsely becoming Stun immune.

Deferred:

- generalized observation/comparative learner;
- candidate/disproved/confirmed evidence;
- inferred broad-immunity persistence;
- new public `[immune:*]` grammar;
- any new polling or high-frequency `OnUpdate` mechanism.

Exact next step: implement the **immunitydebug** diagnostic slice below, then
resume the existing clean-dataset immunity testing with that compact chat view.
Do not change immunity persistence/learning semantics while adding it. The
mouseover sidequest's user-facing `/cast` acceptance path is complete; leave
unused `/target`, `IsValidTarget("mouseover", ...)`, and `/pfcast` live
tests deferred unless they become relevant. Do not start the generalized
immunity learner during this testing period.

## Next implementation slice — immunitydebug

Add a dedicated compact chat diagnostic:

```text
/cleveroid immunitydebug 1
/cleveroid immunitydebug 0
```

This exists only to make current clean-dataset immunity testing practical
without leaving the very large `/cleveroid immunities` window open.

### Hard constraints

This is **diagnostic-only**.

Do not change:

- `CleveRoids_ImmunityData` layout, category grouping, keys, or query behavior;
- any SavedVariables schema or migration;
- what is learned, removed, confirmed, or rejected by the current learner;
- public immunity conditional grammar;
- persistence/removal semantics in `RecordCCImmunity()`,
  `RemoveCCImmunity()`, `RecordImmunity()`, or `RemoveSpellImmunity()`;
- the direct Nampower `SPELL_MISS_SELF` authority model;
- current temporary-aura, death, DR, reflection, split-CC, or inconclusive
  safeguards.

Do not add persistent suspect/candidate/disproved/confirmed evidence, a
generalized learner, polling, or a high-frequency `OnUpdate`.

The immunitydebug enabled flag and any display state must be runtime-only. Do
not add a SavedVariable for this feature.

### Command behavior

- default off;
- `/cleveroid immunitydebug 1` enables only this compact immunity stream;
- `/cleveroid immunitydebug 0` disables it;
- keep it independent from existing `/cleveroid debug`;
- a bare `/cleveroid immunitydebug` may toggle if convenient.

### Compact mob-centric line

Desired shape:

```text
Blackwing Spellbinder [spell icon] | Stun, Spell, Holy
```

The message is mob-centric, not a raw combat-log dump. Use the actual spell
icon inline in chat **instead of the spell name**. The addon already resolves
spell textures with `C_Spell.GetSpellTexture(spellID)`; use WoW inline texture
markup at a small chat-readable size.

Keep the localized NPC name as the readable label.

Presentation does not need to mirror SavedVariables. Existing real storage
remains category-first, for example:

```lua
CleveRoids_ImmunityData["cc_stun"][npcName] = true
CleveRoids_ImmunityData["holy"][npcName] = true
```

Do not rewrite that storage for immunitydebug.

### Color semantics

Color is the state language:

- **green** = positively disproved immunity: authoritative evidence proves the
  mob accepts that category/effect;
- **yellow** = suspect immunity: an authoritative observation is compatible
  with that category, but it is not currently persisted as immune;
- **red** = current existing SCRM immunity data actually records that category
  as immune.

Do not use green merely for unknown/not-recorded. Green requires positive
counter-evidence. Unobserved/irrelevant categories should normally be omitted.
No strikethrough is required; color replaces it.

Example:

1. Hammer of Justice returns authoritative `IMMUNE/IMMUNE2`:

   ```text
   Blackwing Spellbinder [HoJ icon] | Stun, Spell, Holy
   ```

   Stun/Spell/Holy are yellow display suspects unless current existing data
   already records one, in which case that category is red.

2. Later authoritative evidence proves the mob can be stunned:

   ```text
   Blackwing Spellbinder [stun spell icon] | Stun, Spell, Holy
   ```

   Stun becomes green. Unresolved Spell/Holy remain yellow; persisted
   categories remain red.

### Runtime-only mob debug state

A small transient table is allowed to remember yellow suspects and green
disprovals for the current session so later evidence can update the mob-centric
line.

It must not be a SavedVariable and must have no effect on conditionals or
learning.

Prefer a stable runtime identity such as GUID/Mob ID when available, with the
localized NPC name retained for display. This does **not** authorize a Mob-ID
migration of the real immunity SavedVariables.

Reload/logout may discard yellow/green debug state. Existing persisted immunity
data remains the sole source of red state.

### Suspect derivation

For authoritative `IMMUNE/IMMUNE2`, build display-only hypotheses from the
existing classifiers/facts already used by immunity code. Depending on the
spell, candidates may include:

- exact CC type, such as Stun/Fear/Root;
- specific school, such as Holy/Fire/Frost;
- an appropriate broad family such as Spell or Physical.

Reuse existing CC/school/split-spell classification. Do not create a competing
classification system. A yellow suspect must never cause an immunity write.

### Green/disproved derivation

Only turn a displayed category green when an existing authoritative success
path positively contradicts immunity to that category.

Attach observation to current success paths; do not introduce gameplay side
effects to manufacture green evidence.

If existing logic already removes a recorded immunity when the relevant effect
lands, preserve that behavior exactly.

### Red/confirmed derivation

Red is not a new confidence tier. It simply means the category is present in
the current existing persisted immunity data/query model.

Read red state from the framework; do not maintain a second confirmed database.

### Spam control

This should be far quieter than `/cleveroid debug 1`.

Print only on meaningful rendered-state changes:

- new `IMMUNE/IMMUNE2` introduces/changes suspects;
- a relevant suspect becomes green from positive contrary evidence;
- current learner persistence makes a category red;
- existing removal logic changes a previously red category.

Do not repeat an identical line for events that leave the rendered state
unchanged. Ordinary successful hits/casts should not print unless they
materially change a currently relevant immunitydebug state.

Existing skip reasons (temporary aura, dead target, DR, reflect, inconclusive)
may be represented compactly if useful, but do not recreate the general debug
firehose.

### Source landmarks

Primary authoritative path in `Utility.lua`:

- `ProcessSpellMissSelf(spellId, targetGuid, missInfo)`;
- `IMMUNE=7`, `IMMUNE2=8`;
- current safeguards run before `RecordCCImmunity()` / `RecordImmunity()`.

Existing persistence/removal functions:

- `RecordCCImmunity(npcName, ccType, conditionalBuff, spellName)`;
- `RemoveCCImmunity(npcName, ccType)`;
- `RecordImmunity(npcName, spellName, conditionalBuff, spellID)`;
- `RemoveSpellImmunity(npcName, school)`.

Slash handling is in `Core.lua` beside `/cleveroid debug [0|1]` and
`/cleveroid immunities`.

### Acceptance test

Do not mark these live-passed until the user reports them:

1. `/cleveroid immunitydebug 1` enables the compact stream without enabling
   general debug output.
2. `IMMUNE/IMMUNE2` prints one mob-first line with spell icon and yellow
   display suspects.
3. If the existing learner persists a category, that category renders red.
4. Positive contrary evidence can make an applicable runtime suspect green.
5. Identical repeated observations do not spam duplicate lines.
6. `/cleveroid immunitydebug 0` stops the stream.
7. Reload clears transient yellow/green display state.
8. No immunitydebug SavedVariables are created and existing immunity
   conditionals behave exactly as before.

### Deferred / out of scope for immunitydebug

- generalized observation/comparative learner;
- persistent candidate/disproved/confirmed evidence;
- Mob-ID SavedVariables migration / locale-storage redesign;
- inferred broad-immunity persistence;
- new public `[immune:*]` grammar.

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
        [13874] = true,
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

### Step 8 — route existing public checks through dimensions — DONE

Implemented in `d5216f6a`.

Added internal action resolver:

```lua
CheckSpellImmunityDimensions(unitId, spellID)
```

It consumes the ordered list from `GetSpellImmunityDimensions` and checks each
dimension exactly once with `CheckExactImmunityType`.

Current spell-name / bare-action behaviour:

```text
Hammer of Justice
    holy -> spell -> stun -> cc -> all

Cheap Shot
    physical -> stun -> cc -> all

Charge Stun
    physical -> stun -> cc -> all

Fireball
    fire -> spell -> all
```

The first matching dimension wins, which preserves narrow-to-broad provenance
for Step 9.

Explicit typed queries are unchanged:

- `[immune:stun]` remains a typed stun query and uses Step 6 composition;
- `[immune:fire]` remains a typed fire query;
- no `[immune:spell]`, `[immune:cc]`, or `[immune:all]` grammar has been
  added yet;
- legacy `unknown` spell-specific storage remains on its compatibility path.

Banish continues to resolve as a special school source through the dimension
check. Reflection is absent from the dimension list and cannot become immunity.

No learning or SavedVariables schema changed.

Static diff review completed. Live validation remains deferred.

### Step 9 — add reason/debug visibility — DONE

Implemented in `2eb22cba`.

`CleveRoids.CheckImmunity` remains boolean-compatible but can now additionally
return:

```text
true, winningDimension, source, detail
```

Existing conditional callers remain safe because Lua ignores unused return
values. `Conditionals.lua` still consumes only the first boolean for
`[immune]` and `[noimmune]`.

Added an explicit on-demand diagnostic:

```lua
CleveRoids.DebugCheckImmunity(unitId, spellOrSchool)
```

This is intentionally **not** printed automatically during macro evaluation,
avoiding chat spam from frequently evaluated conditionals.

Example diagnostic quality:

```text
Hammer of Justice -> immune: spell [temporary_aura] (Anti-Magic Shield 7121)
Cheap Shot        -> immune: physical [temporary_aura] (Blessing of Protection 1022)
Hammer of Justice -> immune: stun [temporary_cc] (Whirlwind 26083)
Fireball          -> immune: fire [recorded]
```

Numeric aura IDs remain authoritative; localized names are display-only.

No learning, persistence, polling, or public macro grammar changed.

### Step 10 — regression validation — STATIC PASS COMPLETE / LIVE PENDING

A static regression pass was completed against the current framework.

- [x] existing recorded fire/frost/etc. immunity path still resolves through
  `SchoolImmune`
- [x] existing exact CC immunity path still resolves through
  `CheckCCImmunity`
- [x] CC aliases are unchanged: `sap/incap/incapacitate/incapacitated ->
  knockout`
- [x] Sartura remains exactly `15516 -> 26083 -> stun`
- [x] Divine Shield / Divine Protection / Ice Block are in `IMMUNITY_AURAS.all`
- [x] Anti-Magic Shield is only in `IMMUNITY_AURAS.spell`
- [x] Blessing of Protection is only in `IMMUNITY_AURAS.physical`
- [x] reflection IDs remain only in `IMMUNITY_AURAS.reflect` and never enter
  immunity dimensions
- [x] Banish remains a `special` exact-school source, not `all`
- [x] direct Nampower `SPELL_MISS -> IMMUNE` still checks TempCC, typed
  protection/reflection guard, and DR before permanent learning
- [x] delayed missing-CC verification still checks TempCC and the temporary
  protection/reflection guard before permanent learning
- [x] NPC stun DR classification remains Kidney / controlled / triggered
- [x] no new immunity SavedVariables schema was added
- [x] no new polling / high-frequency scan was added
- [x] pre-framework vs current `OnUpdate` handler count is unchanged: 5
- [x] pre-framework vs current `CleveRoids_ImmunityData` init/reset shape is
  unchanged
- [x] `Conditionals.lua` remains compatible with additional reason return
  values because it consumes only the first boolean

Live/in-game validation remains outstanding and cannot be replaced by static
inspection:

- [ ] Sartura Whirlwind toggles live `stun` exactly as expected
- [ ] forced HoJ during Whirlwind returns IMMUNE without writing permanent
  `cc_stun`
- [ ] aura 26083 is queryable through ClassicAPI on the target server/client
- [ ] live `all` aura checks behave for Divine Shield / Divine Protection /
  Ice Block
- [ ] live Anti-Magic Shield blocks six-school actions but not Physical actions
- [ ] live Blessing of Protection blocks Physical actions but not magic-school
  actions
- [ ] live reflection continues to suppress learning without reporting immunity
- [ ] Blackwing Spellbinder regression can eventually confirm HoJ IMMUNE while
  Cheap Shot/Charge remain eligible

Framework implementation may continue into the observation/learner stage while
these live checks remain explicit validation debt; do not treat the live matrix
as passed until it has actually been exercised in game.

---

## Immunities testing/management UI — NEXT

### Purpose

Add an in-game inspection/management surface specifically to unblock live
validation of the framework.

Slash command:

```text
/cleveroid immunities
```

The command opens/toggles the immunity UI. It should be a normal Vanilla-style
Lua-created frame; do not introduce a new XML dependency solely for this panel.

No learner/inference logic belongs in the UI. It reads the same canonical data
and query helpers used by the runtime.

### Main window

Header:

```text
SCRM Immunities
```

The main window is intentionally large. Prefer readable fixed-width columns plus
horizontal scrolling over squeezing every mechanic/school into narrow columns.

#### CC Immunities

Sub-header:

```text
CC Immunities
```

Display a horizontal set of immunity columns. Include the broad `CC` dimension
when/if recorded broad data exists, followed by the exact Vanilla mechanic ID
and canonical display name, for example:

```text
CC
1 Charm
2 Disorient
3 Disarm
4 Distract
5 Fear
6 Fumble
7 Root
8 Pacify
9 Silence
10 Sleep
11 Snare
12 Stun
13 Freeze
14 Knockout (Sap)
17 Polymorph
18 Banish
20 Shackle
23 Turn
24 Horror
26 Interrupt
27 Daze
```

Do not invent rows for unused/non-exposed mechanics. Mechanic 14 remains
canonical `Knockout`; show `Sap` as a user-facing clarification/alias.

Each mechanic column contains a vertically scrollable text/list area of mobs
currently recorded for that immunity. Show a count in the column header where
practical, e.g. `12 Stun (27)`.

The CC section itself may scroll horizontally.

#### Spell Immunities

Sub-header:

```text
Spell Immunities
```

Display the canonical broad/general and school dimensions as columns:

```text
All
Spell
Physical
Holy
Fire
Nature
Frost
Shadow
Arcane
Bleed
```

Each column contains a vertically scrollable list of recorded mobs and may show
its count in the header.

`unknown` is a legacy/storage fallback rather than a canonical immunity
dimension. Do not present it as an ordinary immunity column. If old `unknown`
records exist, expose them separately as diagnostic/legacy data rather than
pretending they are a real immunity type.

The Spell Immunities section may scroll horizontally.

### Current Target companion window

Attach a second, narrower window to the **right** of the main SCRM Immunities
window. It should be approximately the same height as the main window and move
with it.

Layout:

```text
Current Target

Blackwing Spellbinder (12457)

CC Immunities        Spell Immunities
12 Stun              Fire
14 Knockout (Sap)    Frost
CC                    Spell
                      All
```

Use the current target's real name and creature entry ID when available.

The two columns must distinguish **recorded/learned** immunity from **live
temporary/current-state** immunity. Live entries should expose enough provenance
for testing, for example:

```text
LIVE
Stun — Whirlwind 26083
Spell — Anti-Magic Shield 7121
All — Divine Shield 13874
Physical — Blessing of Protection 1022
```

Reflection must remain visibly a non-immunity explanation. It may be shown in a
small live/explanation area for debugging, but must never appear as learned
`Spell`, `CC`, or `All` immunity.

The target panel should update from existing target/aura/data-change event paths.
Do not add an always-running poll or high-frequency `OnUpdate`.

### Management controls

The panel is also the replacement for repeatedly typing the immunity management
slash commands while testing.

Support clearing:

- one exact CC immunity type;
- all CC immunity data;
- one school/general immunity type where stored;
- all school/general immunity data;
- all learned immunity data.

Prefer compact `Clear CC...` / `Clear Spell...` selection dialogs or
equivalent controls rather than putting a large reset button under every
column.

Every destructive/reset control must have a **manual Backup** control directly
beside it.

### Manual backup history

Backups are **manual only**. Do not automatically create a snapshot before every
clear/restore; silent automatic snapshots can bloat SavedVariables.

A backup always copies the complete current `CleveRoids_ImmunityData`, even
when the adjacent reset only clears one category.

Keep dated/time-labelled historical snapshots until the user explicitly deletes
them. WoW addons cannot create arbitrary runtime files such as
`immunitydata-2026-09-22-1200.lua`, so store the archive inside an existing
SCRM SavedVariables container (preferred: an isolated
`CleveRoidMacros.immunityBackups` field) rather than adding a file-writing
scheme.

Each snapshot should retain at least:

```text
timestamp / display label
immunity data version
complete immunity data copy
optional reason/label
```

Provide a compact backup-history view/dialog with explicit Restore and Delete
actions. Restoring a snapshot must be an explicit user action.

This backup archive is a management-data exception to the framework's
"no learner SavedVariables schema" rule: it must not change the format or
meaning of `CleveRoids_ImmunityData`, and it must not store learner evidence,
candidates, or inferred state.

### Testing role

Once implemented, use this UI to complete the outstanding live regression
matrix before beginning generalized learner work:

- Sartura: live `Stun` appears only during Whirlwind 26083;
- forced HoJ during Whirlwind does not create permanent `cc_stun`;
- Divine Shield / Divine Protection / Ice Block appear as live `All`;
- Anti-Magic Shield appears as live `Spell`;
- Blessing of Protection appears as live `Physical`;
- reflection is visible only as an explanation/guard, never immunity;
- Blackwing Spellbinder can be inspected as the permanent broad-spell
  regression case without falsely becoming Stun immune.


## Invariants

Do not break these while refactoring:

1. **No false permanent learning from temporary state.**
2. **TempCC is mechanic-specific.**
3. **Reflection is not immunity.**
4. **Broad spell immunity is not the same as any single-school immunity.**
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

The Step 7 classifier research is complete: broad `spell` is the six
non-physical Vanilla schools. Comparative inference from observations remains
deferred to the learner stage.

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

**Build the Immunities testing/management UI before learner work.**

First implementation milestone:

```text
/cleveroid immunities
 -> SCRM Immunities main window
 -> attached Current Target companion window
```

Minimum first-pass requirements:

- CC and Spell Immunities sections render existing recorded data;
- horizontal scrolling keeps columns readable;
- each column has a vertically scrollable mob list;
- current target shows name + creature ID;
- current target separates recorded immunity from live temporary/current-state
  immunity;
- current target consumes the framework's existing dimension/source/detail
  information rather than duplicating classification logic;
- manual Backup controls sit beside destructive reset controls;
- backups are full, dated historical snapshots and are never auto-pruned;
- no automatic backup-on-clear;
- no new polling;
- no comparative learner/inference;
- no public conditional grammar changes.

After the UI is usable, complete the Step 10 live regression matrix with it.
Only then resume the observation-only learner milestone
`ObserveImmunity(target, spellID, result)`.

Before coding in a new chat, use this document as the recovery source of truth.


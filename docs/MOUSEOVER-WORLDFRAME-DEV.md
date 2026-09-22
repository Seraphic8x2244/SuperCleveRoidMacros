# Mouseover WorldFrame Sidequest

Focused design / recovery document for the SCRM `@mouseover` camera-drag issue.

This work is intentionally separate from the immunity framework. The active
branch is still `design/temp-cc-immunity`; this sidequest should remain narrow
and must not disturb immunity-learning behavior.

## Recovery snapshot

- Branch: `design/temp-cc-immunity`
- Base: `main`
- Recovery handoff head before implementation: `9e3574c2ae1c6a88d432e7d97343ac582194b688`
- Branch relation at that handoff: 107 ahead / 0 behind `main`
- TOC version: `@project-version@`
- Status: investigation/design agreed; runtime behavior not changed yet.
- Runtime implementation commits:
  - `2be9746ba3504fad01236a5a0d4365211f6f18e6` — suspend mouseover during WorldFrame actions and add the canonical resolver;
  - `49da070200b2a1fbbd8e9d7f707c63cfcdbcc67e` — route `IsValidTarget()` through the canonical resolver;
  - `ed7776329379853db1d32aea0d6b76e9e8305bed` — route normal execution, conditional `/target`, and `/pfcast` through the canonical resolver.
- Failed runtime implementation head: `ed7776329379853db1d32aea0d6b76e9e8305bed`
- Protected-hook removal commit: `93f1f69a664907a67d37d78413738e69b3585dd3`
- Status after protected-hook removal: canonical resolver/consolidation retained.
- Safe WorldFrame script implementation: `532802577f2b5d56b9a9ad88318abe0e58a83170`
  — tracks left/right state from `WorldFrame:HookScript("OnMouseDown")` and
  `WorldFrame:HookScript("OnMouseUp")`.
- Branch relation after that runtime commit: 120 ahead / 0 behind `main`.
- Active next step: live-test the matrix below, with special attention to whether
  `WorldFrame:OnMouseUp` fires reliably after camera/mouselook cursor capture;
  immunity behavior remains frozen while its separate clean-dataset testing continues.

## User-visible problem

SCRM's `@mouseover` support is deliberately more capable than stock Vanilla:
it bridges pfUI and other unit frames, native world hover, tooltip fallback, and
synthetic `SetMouseoverUnit` state.

That compatibility layer can outlive the player's actual targeting intent.

Observed failure case:

1. Player has a normal target.
2. Cursor had previously been over another unit.
3. Player holds left or right mouse in the 3D world to manipulate the camera /
   perform WoW's WorldFrame mouse action.
4. WoW hides the cursor and no longer presents that old hover as an intentional
   mouseover.
5. SCRM can still resolve the old/synthetic mouseover.
6. A macro such as `[@mouseover,...] Spell; Spell` can therefore cast on the
   wrong unit instead of falling through to the current target.

Desired player semantics:

- ordinary visible-cursor mouseover remains fully supported;
- hovering/clicking pfUI or other unit frames remains fully supported;
- while WoW's left/right **3D-world mouse action** is active, SCRM treats
  `@mouseover` as temporarily unavailable;
- the macro then naturally falls through to its next clause/current target;
- on release, normal mouseover resolution resumes immediately.

## Important terminology

Do not describe the tracked state as merely "camera movement".

The relevant Vanilla WorldFrame actions are broader than camera rotation:

- `CameraOrSelectOrMoveStart` / `CameraOrSelectOrMoveStop`
  - left-button 3D-world action;
  - can cover camera orbit plus select/move behavior.
- `TurnOrActionStart` / `TurnOrActionStop`
  - right-button 3D-world action;
  - can cover mouse turning plus normal right-click world action.

The useful semantic boundary is therefore:

> **WorldFrame mouse action active** versus **ordinary visible-cursor hover**.

This matches the actual intent better than testing raw LMB/RMB state.

## Explicitly rejected design

Do **not** implement this as:

```lua
if IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton") then
    return nil
end
```

ClassicAPI exposes held-button state, but that signal is too broad.

A player can legitimately hold/click left or right mouse on:

- pfUI raid frames;
- Blizzard unit frames;
- action buttons;
- bags/inventory;
- other UI elements.

Those interactions do not imply that mouseover targeting intent vanished.
The cursor remains visible and the unit frame under it should continue to be a
valid `@mouseover`.

The fix must observe the actual WoW WorldFrame action functions instead.

## Current SCRM mouseover architecture

### Shared source aggregate

`Utility.lua` owns `CleveRoids.__mo`:

```lua
CleveRoids.__mo = CleveRoids.__mo or {
    sources = {},
    current = nil,
    selfTriggered = false,
}
```

Sources have priorities:

- unit-frame integrations, including pfUI / Blizzard / other supported frames:
  priority 3;
- native `UPDATE_MOUSEOVER_UNIT`: priority 2;
- tooltip fallback: priority 1.

`SetMouseoverFrom(source, unit)` and
`ClearMouseoverFrom(source, unitIfMatch)` choose the best remaining source.

When `SetMouseoverUnit` is available, SCRM can apply the chosen source back to
the game's `mouseover` token. This is useful compatibility behavior, but it
also means `UnitExists("mouseover")` does not necessarily prove that the
player currently intends to mouseover that unit.

### Native / tooltip bridge

`Extensions/Mouseover/GameTooltip.lua`:

- records native `UPDATE_MOUSEOVER_UNIT` as source `"native"`;
- records tooltip units as source `"tooltip"`;
- contains self-trigger protection because SCRM's own `SetMouseoverUnit` calls
  can fire `UPDATE_MOUSEOVER_UNIT`.

The native event is not sufficient by itself to represent "cursor intent has
ended" across the old 1.12 world-hover behavior, so stale compatibility state
can survive longer than desired.

### pfUI bridge

`Extensions/Mouseover/pfUI.lua` hooks legacy/non-native pfUI frame paths and
registers per-frame source keys such as `pfui:party3`.

Those sources are useful and should **not** be destroyed when a WorldFrame mouse
action starts.

## Current duplicated consumer pipelines

SCRM does not currently have one canonical answer to "what unit does
`@mouseover` resolve to?"

### Normal conditional execution

`Core.lua` / `DoWithConditionals()` currently prefers:

1. native `UnitExists("mouseover")`;
2. `CleveRoids.mouseoverUnit`;
3. otherwise leaves `"mouseover"` for the clause to fail naturally.

### `IsValidTarget()`

`Utility.lua` has separate mouseover logic:

1. native `"mouseover"`;
2. pfUI's internal `pfUI.uf.mouseover.unit` fallback.

### Conditional `/target`

`Core.lua` contains another resolver:

1. native `"mouseover"`;
2. `CleveRoids.mouseoverUnit`;
3. `pfUI.uf.mouseover.unit`;
4. otherwise nil.

### `/pfcast`

`ResolvePfCastUnit()` uses:

1. native `"mouseover"`;
2. `GetMouseFocus()` frame label/id;
3. `CleveRoids.mouseoverUnit`;
4. current target;
5. player when auto-self-cast is enabled.

Only items 1-3 are really "mouseover resolution". Target/player are pfcast
fallback semantics and should stay outside the canonical mouseover resolver.

## Agreed design

### 1. Track WorldFrame mouse-action state

Post-hook the four WoW global action functions:

```text
CameraOrSelectOrMoveStart
CameraOrSelectOrMoveStop
TurnOrActionStart
TurnOrActionStop
```

Maintain narrow state such as:

```lua
CleveRoids.worldMouseAction = {
    left = false,
    right = false,
}
```

Semantics:

- left Start -> `left = true`
- left Stop -> `left = false`
- right Start -> `right = true`
- right Stop -> `right = false`
- suppressed if either flag is true.

Use post-hooks / `hooksecurefunc`; do not replace the original WoW functions.

### 2. Suspend mouseover; do not erase it

Starting a WorldFrame mouse action must **not** clear:

- `CleveRoids.__mo.sources`;
- `CleveRoids.__mo.current`;
- pfUI source keys;
- tooltip/native source history.

It should also not call `SetMouseoverUnit("")` merely because camera/world
action began.

Instead, the canonical resolver returns nil while the action is active:

```lua
if CleveRoids.IsWorldMouseActionActive() then
    return nil
end

return normalMouseoverResolution()
```

This is suspension, not deletion.

Reason: clearing source state would require mouse-enter/native events to rebuild
it after release and could create new missing/sticky-hover bugs. Suspension lets
normal state resume immediately.

### 3. Add one canonical resolver

Introduce one central helper, conceptually:

```lua
CleveRoids.ResolveMouseoverUnit()
```

Required behavior:

```text
WorldFrame mouse action active?
  yes -> nil

native "mouseover" valid?
  yes -> "mouseover"

valid SCRM compatibility mouseover?
  yes -> stored unit

valid pfUI fallback where still required?
  yes -> pfUI unit

otherwise -> nil
```

Exact pfUI fallback details should be decided from the current integration code
during implementation; do not duplicate another resolver merely to preserve an
old ordering accident.

Also expose a small predicate if useful:

```lua
CleveRoids.IsWorldMouseActionActive()
```

### 4. Route all mouseover consumers through it

At minimum audit and convert:

- `DoWithConditionals()` / normal `/cast` and related conditional commands;
- `CleveRoids.IsValidTarget()`;
- conditional `/target`;
- `ResolvePfCastUnit()`.

For `/pfcast`, only the mouseover portion should use the central resolver.
Its normal target/player fallback remains:

```text
resolved mouseover
  -> if none, current target
  -> if none and autoSelfCast, player
```

### 5. Preserve unit-frame behavior

Clicking or holding LMB/RMB on a unit frame must continue to allow
`@mouseover` if the WorldFrame Start function was not invoked.

This is the main reason to hook WoW's WorldFrame actions rather than raw input.

### 6. Do not alter macro grammar

No new conditional syntax is needed.

Existing macros such as:

```text
/cast [@mouseover,help] Flash Heal; Flash Heal
```

simply become safer.

## Expected behavior matrix

| Situation | World action active | `@mouseover` result |
| --- | --- | --- |
| Cursor over world unit, no mouse button action | no | hovered unit |
| Cursor over pfUI raid frame | no | hovered raid unit |
| LMB held on pfUI unit frame | no, assuming WoW does not invoke WorldFrame Start | hovered frame unit |
| RMB held on pfUI unit frame | no, assuming WoW does not invoke WorldFrame Start | hovered frame unit |
| LMB 3D-world action / camera orbit | left | nil |
| RMB 3D-world turn/action on empty world | right | nil |
| RMB 3D-world action on NPC which WoW targets | right | nil; fallback clause may use the newly selected target |
| Either WorldFrame action released | no | normal mouseover resolution resumes |

## Live-test matrix

Use a simple macro with an unmistakable target effect or benign spell suitable
for the test character.

### Normal mouseover

- hover a world unit and cast -> mouseover wins;
- hover a pfUI party/raid frame and cast -> frame unit wins;
- hover no unit and cast -> fallback/current target wins.

### Left WorldFrame action

- establish a mouseover on unit A;
- target unit B;
- hold LMB in the 3D world so WoW enters its left WorldFrame action;
- while held, cast the mouseover/fallback macro;
- expected: unit A does not intercept; unit B/fallback wins;
- release LMB;
- expected: normal mouseover is immediately eligible again.

### Right WorldFrame action

- establish a mouseover on unit A;
- target unit B;
- hold RMB in the 3D world;
- while held, cast;
- expected: stale/hidden-cursor unit A does not intercept;
- when RMB on NPC causes WoW to target that NPC, fallback may naturally cast on
  that newly selected target;
- release RMB;
- expected: normal mouseover resumes.

### Unit-frame clicks

- hover pfUI party/raid unit;
- hold/click LMB on the frame and cast if practical;
- hold/click RMB on the frame and cast if practical;
- expected: no WorldFrame suppression; frame remains valid mouseover.

### Pipeline parity

Repeat representative checks through:

- normal `/cast`;
- explicit `/target [@mouseover,...]`;
- a path using `IsValidTarget("mouseover", ...)`;
- `/pfcast` if enabled.

Expected: all agree on whether mouseover exists during WorldFrame action.

## Static verification checklist

Before presenting a build for live testing:

- no raw LMB/RMB polling added;
- no new high-frequency `OnUpdate`;
- original WorldFrame functions are post-hooked, not replaced;
- both Start and Stop paths are covered;
- mouseover source tables are suspended, not cleared;
- `DoWithConditionals`, `IsValidTarget`, `/target`, and `/pfcast` no
  longer carry materially different mouseover-resolution logic;
- `/pfcast` keeps target/player fallback outside the resolver;
- no immunity framework or SavedVariables behavior changed;
- Vanilla Lua compatibility preserved.

## Non-goals

This sidequest does not include:

- generalized mouse cursor tracking;
- polling `GetMouseFocus()` every frame;
- changing the behavior of `[button:*]`;
- modifying ClassicAPI;
- changing pfUI itself;
- changing mouseover source priorities unless consolidation proves one is
  objectively redundant;
- altering immunity logic;
- adding new public macro syntax.

## Implementation status

Completed / implemented:

- investigation and desired semantics documented;
- current divergent mouseover pipelines identified;
- WorldFrame action suspension strategy agreed;
- raw LMB/RMB gating explicitly rejected;
- initially attempted `hooksecurefunc` post-hooks on
  `CameraOrSelectOrMoveStart/Stop` and `TurnOrActionStart/Stop`, but the
  first live test proved this unsafe on 1.12 because ClassicAPI implements the
  hook by replacing the protected global with a wrapper;
- removed those four protected-global hooks in `93f1f69a`;
- added narrow left/right WorldFrame action state and
  `CleveRoids.IsWorldMouseActionActive()`;
- added canonical `CleveRoids.ResolveMouseoverUnit()`;
- the resolver returns nil while either WorldFrame action is active but does
  not clear `CleveRoids.__mo.sources`, `CleveRoids.__mo.current`,
  `CleveRoids.mouseoverUnit`, pfUI state, or call `SetMouseoverUnit("")`
  because of the WorldFrame action;
- normal `DoWithConditionals()` now fails an explicit `@mouseover` clause
  when the canonical resolver returns nil, allowing the next clause/current
  target fallback to run even if the synthetic native `mouseover` token still
  exists;
- `CleveRoids.IsValidTarget()` now delegates mouseover resolution to the
  canonical helper;
- conditional `/target` uses the canonical helper for explicit
  `@mouseover` and for its implicit mouseover candidate;
- `/pfcast` uses the canonical helper only for mouseover resolution and keeps
  its separate target/player fallback afterward;
- the existing pfUI frame-under-cursor fallback was folded into the canonical
  resolver rather than left as a `/pfcast`-only pipeline.

Static-checked:

- no raw LMB/RMB polling was added;
- no new `OnUpdate` loop or polling path was added;
- the four protected WorldFrame movement/action globals are no longer wrapped;
- `53280257` observes only `WorldFrame`'s own `OnMouseDown` /
  `OnMouseUp` scripts through ClassicAPI's `Frame:HookScript` backport;
- only left/right clicks delivered to `WorldFrame` flip the suspension flags;
  clicks handled by pfUI/unit/UI frames do not enter this path;
- no raw `IsMouseButtonDown()` polling was added;
- stored mouseover sources are still never erased merely because of this
  sidequest;
- branch source audit found normal execution, `IsValidTarget`, conditional
  `/target`, and `/pfcast` resolving through
  `CleveRoids.ResolveMouseoverUnit()`;
- the remaining direct `UnitExists("mouseover")` in
  `Extensions/Mouseover/GameTooltip.lua` is the native source/event bridge,
  not a macro-resolution consumer; its explicit `SetMouseoverUnit("")`
  remains limited to existing non-unit tooltip cleanup and is not invoked by
  WorldFrame suspension;
- the branch-wide audit found no other direct macro mouseover resolver using
  `CleveRoids.mouseoverUnit`, `pfUI.uf.mouseover`, or `GetMouseFocus()`
  outside the canonical helper;
- compare from handoff `9e3574c2` through runtime head `ed777632` shows
  only `Utility.lua`, `Conditionals.lua`, `Core.lua`, and the two handoff
  docs changed;
- no immunity-learning, immunity SavedVariables, or public macro grammar code
  was changed;
- compare from handoff head `5a7388cd` to `53280257` changes only
  `Utility.lua` (+27/-5);
- no GitHub CI workflow/status is attached to `53280257`; verification of the
  replacement is source/static review only.

Live-tested:

- user reports the pre-fix bug: hidden-cursor camera/world mouse action can
  allow an unintended old mouseover to intercept a macro;
- first post-implementation client test failed immediately: ClassicAPI was
  reported as "blocked from an action only available to the Blizzard UI" after
  the new WorldFrame action hooks were installed;
- diagnosis: Vanilla 1.10+ protects
  `CameraOrSelectOrMoveStart/Stop` and `TurnOrActionStart/Stop`; ClassicAPI's
  1.12 `hooksecurefunc` implementation installs a wrapper back into the
  target global, so these protected movement/action globals must not be hooked
  this way.
- `53280257` LMB WorldFrame-script path passed live: normal mouseover works
  before the click, mouseover is suppressed while LMB is held even when camera
  movement would place the hidden cursor over a unit, and mouseover works again
  after release. This confirms LMB `WorldFrame:OnMouseUp` release/resume on the
  target client.


Untested:

- the new `WorldFrame:OnMouseDown/OnMouseUp` observation mechanism in WoW;
- RMB mouselook release/resume remains untested; LMB camera-orbit
  `OnMouseUp` delivery is now live-confirmed;
- unified resolver behavior under normal world hover and pfUI/unit-frame hover;
- left/right unit-frame click preservation;
- left/right WorldFrame hold suppression;
- release/resume semantics;
- parity across `/cast`, conditional `/target`, `IsValidTarget`, and
  `/pfcast`.

## Exact next step

Live-test `53280257` without expanding scope. The replacement signal is now
WorldFrame-local: `OnMouseDown` starts left/right suspension and
`OnMouseUp` ends it. Do not resume the failed protected-global hook approach.

LMB WorldFrame suppression and release/resume are now live-confirmed. Next,
repeat the same hold/move/release check with RMB mouselook. If RMB release is
reliable, continue the remaining unit-frame and pipeline-parity checks. If release is not
reliable, retain WorldFrame-origin detection and add a narrowly-scoped release
fallback only while that known WorldFrame action is active.

Live-test the matrix above without expanding scope:

1. verify normal world and pfUI mouseover still win when no WorldFrame action is active;
2. verify held left and right 3D-world actions suppress the old/stale mouseover and allow fallback/current target to win;
3. release each button and verify normal mouseover eligibility resumes immediately;
4. verify LMB/RMB interaction on pfUI/unit frames does not suppress mouseover when the WorldFrame Start functions are not invoked;
5. repeat representative checks through normal `/cast`, conditional
   `/target`, an `IsValidTarget("mouseover", ...)` path, and `/pfcast`.

Do not broaden this sidequest or start the generalized immunity learner while
the separate immunity live-testing period is in progress.

# Development Handoff

Updated: 2026-09-19

## Current state

- Repository: `Seraphic8x2244/SuperCleveRoidMacros`
- Branch: `design/temp-cc-immunity`
- Base: `main` at `37ca7cef4012cc0d76b7e559ac9517c785dbae79`
- Upstream `brues-code/SuperCleveRoidMacros:main`: also `37ca7cef4012cc0d76b7e559ac9517c785dbae79`
- TOC version: `@project-version@` (repository has no published GitHub release/version tag to record here)
- Latest branch commit before this handoff: `52da56262580c51dd6a9688c42284eb133c8dd34`
- Branch relation before this handoff: 12 commits ahead, 0 behind `main`

## Recent branch commits

- `52da5626` — Document temp CC audit findings
- `af406a80` — Curate temporary immunity guard auras
- `b56b2529` — Correct Vanilla Sap mechanic documentation
- `98531032` — Canonicalize Sap to Vanilla incapacitate mechanic
- `2884149a` — Correct Vanilla Sap mechanic alias
- `bc4a4811` — Use ClassicAPI creature identity in temp CC design
- `3dee891e` — Use ClassicAPI creature IDs for temp CC immunity
- Earlier commits on this branch add and implement `docs/TEMP-CC-IMMUNITY.md`.

## Completed

### TempCCImmune microsystem

- Added a curated `TEMP_CC_IMMUNITIES` table in `Utility.lua`.
- First rule: creature entry 15516 (Battleguard Sartura), aura 26083
  (Whirlwind), mechanic `stun`.
- Creature identity uses ClassicAPI `UnitCreatureID(unit)`.
- Aura identity uses `C_UnitAuras.GetUnitAuraBySpellID(unit, auraID)`.
- `CheckCCImmunity` treats a matching temporary immunity as live state.
- Explicit Nampower `SPELL_MISS -> IMMUNE` learning skips a matching
  temporary CC immunity.
- Delayed missing-debuff CC learning has the same matching-mechanic guard.
- No TempCC state is persisted to SavedVariables.
- No new runtime Lua module was added.

### Audit corrections

- Removed manual F130/F530 GUID parsing in favor of `UnitCreatureID`.
- Corrected Vanilla 1.12 Sap handling: client `SpellMechanic.dbc` reports
  Sap as mechanic 14 (incapacitated), so `sap` is now a compatibility alias
  of `knockout`; the incorrect client mechanic-30 distinction was removed.
- Corrected `docs/CC-IMMUNITY-DR.md` to distinguish the Vanilla client DBC
  from vMaNGOS' broader server-side mechanic enum.
- Replaced the misleading `INVULNERABILITY_SPELL_IDS` table with curated
  `IMMUNITY_GUARD_AURA_IDS`.
- Removed unrelated effects (including Sap, Forbearance, food/poison/etc.)
  from that broad guard and added genuine Ice Block immunity.
- Kept protection/reflection auras as conservative guards against poisoning
  learned immunity data.

### Locale audit

The new TempCC logic is locale-independent: all decisions use numeric creature
and aura IDs plus SCRM's canonical mechanic tokens. Encounter/spell names are
comments or debug/display output only.

## Untested

- No in-game Sartura validation yet because the character is AQ40-locked and
  the encounter is awkward to reproduce.
- Planned next-reset test:
  1. `/cleveroid removeccimmune Battleguard Sartura stun`
  2. normal HoJ macro should refuse during Whirlwind;
  3. force a plain HoJ during Whirlwind and observe server `IMMUNE`;
  4. SCRM must not learn permanent stun immunity;
  5. after Whirlwind, the normal HoJ macro should become eligible again.

## Deferred / audit follow-ups

- Legacy `ParseAfflictedCombatLog()` still parses the English phrase
  `"is afflicted by"` and uses an English spell-name lookup table for
  hidden-Pounce/bleed landing confirmation. This predates TempCC but is the
  remaining immunity-verification localization issue identified by this audit.
- Other older combat-log fallback parsers also contain English text patterns,
  but they are outside the TempCC change and many are superseded by exact
  Nampower events.
- Decide whether any historical `cc_sap` SavedVariables need migration to
  `cc_knockout`; automatic current-client learning should use mechanic 14.
- Low-priority follow-up: review whether reflect handling should explicitly
  cancel pending verification even though Nampower miss state already prevents
  the CC delayed learner from recording.
- Low-risk edge case: delayed verification checks the live TempCC aura; if a
  very short immunity aura ended before the delayed check and the direct miss
  path were unavailable, the explanation could be missed. Sartura's Whirlwind
  is long enough that this does not affect the current case.

## Exact next step

Make `ParseAfflictedCombatLog()` locale-safe by deriving its parse pattern
from the client's localized aura combat-message GlobalStrings and classify the
resolved spell numerically (hidden CC spell IDs / DBC bleed school) instead of
using English spell-name keys. Then run a final branch-delta/static audit and
leave the branch ready for the next AQ40 live test.

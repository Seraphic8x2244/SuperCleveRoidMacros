# Development Handoff

Updated: 2026-09-20

## Current state

- Repository: `Seraphic8x2244/SuperCleveRoidMacros`
- Branch: `design/temp-cc-immunity`
- Base: `main` at `37ca7cef4012cc0d76b7e559ac9517c785dbae79`
- Upstream `brues-code/SuperCleveRoidMacros:main`: also `37ca7cef4012cc0d76b7e559ac9517c785dbae79` at last verification
- TOC version: `@project-version@` (repository has no fixed source-tree version string)
- Latest functional/documentation commit before this handoff refresh:
  `e4dac9b24fd0b305fbd1dd7208564cee8b6dba44`
- Branch relation before this handoff refresh: 23 commits ahead, 0 behind `main`
- Branch delta: `Conditionals.lua`, `Utility.lua`,
  `docs/CC-IMMUNITY-DR.md`, `docs/DEVELOPMENT-HANDOFF.md`,
  and `docs/TEMP-CC-IMMUNITY.md`

## Recent branch commits

- `e4dac9b2` — Record Anti-Magic Shield guard update
- `9201d451` — Document Anti-Magic Shield immunity guard
- `20d2e9ce` — Guard Anti-Magic Shield immunity variants
- `013df0ea` — Refresh temp CC development handoff
- `dc3c3263` — Document temporary CC immunity implementation audit
- `5f0af64a` — Localize split CC name fallback
- `af5a8869` — Harden immunity guard and locale pattern lookup
- `c5a71898` — Document locale-safe aura verification
- `dff206db` — Avoid duplicate localized aura parsing
- `a74578b6` — Localize aura-landed immunity verification
- `5a29a222` — Add temporary CC development handoff
- `52da5626` — Document temp CC audit findings
- `af406a80` — Curate temporary immunity guard auras
- `b56b2529` — Correct Vanilla Sap mechanic documentation
- `98531032` — Canonicalize Sap to Vanilla incapacitate mechanic
- `2884149a` — Correct Vanilla Sap mechanic alias
- `bc4a4811` — Use ClassicAPI creature identity in temp CC design
- `3dee891e` — Use ClassicAPI creature IDs for temp CC immunity

## Completed

### TempCCImmune microsystem

- Added curated `TEMP_CC_IMMUNITIES` data in `Utility.lua`.
- First rule: creature entry 15516 (Battleguard Sartura), aura 26083
  (Whirlwind), mechanic `stun`.
- Creature identity uses ClassicAPI `UnitCreatureID(unit)`; manual GUID parsing
  was removed.
- Aura identity uses `C_UnitAuras.GetUnitAuraBySpellID(unit, auraID)`.
- `CheckCCImmunity` treats matching temporary immunity as live state.
- Explicit Nampower `SPELL_MISS -> IMMUNE` learning skips a matching
  temporary CC immunity.
- Delayed missing-debuff CC learning uses the same matching-mechanic guard.
- TempCC state is never persisted to SavedVariables.
- No new runtime Lua module was added.

### CC / immunity audit corrections

- Corrected Vanilla 1.12 Sap handling. Client `SpellMechanic.dbc` reports Sap
  as mechanic 14, so `sap` is a compatibility alias of `knockout`.
- Removed the incorrect client mechanic-30 distinction while documenting why
  vMaNGOS can still contain the broader server-side `MECHANIC_SAPPED = 30`
  enum.
- Replaced broad mechanic-25/invulnerability reasoning with the curated
  `IMMUNITY_GUARD_AURA_IDS` table.
- Removed unrelated effects from the broad immunity guard and retained explicit
  known protection/reflection auras.
- Added genuine Ice Block protection to that guard.
- Added the Vanilla Anti-Magic Shield immunity family (7121, 19645, 24021) to
  the general immunity guard so magic IMMUNE results while those auras are
  active cannot poison permanent learned immunity.
- Kept same-name-but-non-immune shields out of the guard; notably TBC Spell
  Shield 33054 is damage reduction rather than immunity, and absorb shields do
  not qualify.

### Locale audit and corrections

- TempCC decisions are fully ID/mechanic based; English encounter/spell names
  are comments or debug/display text only.
- Aura-landed immunity verification no longer parses a hard-coded English
  `"is afflicted by"` phrase. It derives patterns from Blizzard's localized
  combat-message GlobalStrings.
- Hidden-CC/bleed classification uses numeric spell IDs/mechanics rather than
  English spell-name keys.
- Duplicate localized aura parsing was removed/hardened.
- Split-CC name fallback was localized.
- Locale-safe aura verification and the TempCC implementation audit are
  documented in the branch docs.

## Untested

No in-game Sartura validation has been performed because the current character
is AQ40-locked and the encounter is awkward to reproduce.

Planned next-reset validation:

1. Remove any stale learned test record:
   `/cleveroid removeccimmune Battleguard Sartura stun`
2. During Whirlwind, the normal HoJ macro using `[noimmune:stun]` should refuse
   to cast.
3. During that same Whirlwind, force a plain HoJ without the immunity
   conditional.
4. The server should return `IMMUNE`.
5. SCRM must not create a permanent learned stun immunity for Sartura.
6. After Whirlwind ends, the normal HoJ macro should become eligible again.
7. After the encounter, confirm Sartura has not gained a permanent
   `cc_stun` record.

This single live test covers both live conditional behaviour and the explicit
IMMUNE learning-suppression path.

## Deferred / low-priority follow-ups

- Historical SavedVariables may theoretically contain a legacy `cc_sap` key.
  Current-client learning now canonicalizes Sap to `cc_knockout`. No automatic
  migration has been added because silently rewriting user immunity data was
  intentionally avoided.
- Reflect handling records exact Nampower reflect state. A future cleanup could
  explicitly cancel matching pending verification at the reflect handler too;
  current miss/reason handling already prevents reflect from becoming permanent
  immunity in the normal path.
- Some older, non-TempCC combat-log fallback parsers elsewhere in `Utility.lua`
  still contain English phrases (for example fade/resist tracking). They predate
  this work and are not part of the TempCC/immunity-learning decision path now
  under test.
- The delayed verification fallback checks TempCC live state. If a hypothetical
  very short temporary-immunity aura ended before delayed verification and no
  explicit Nampower miss event were available, the explanation could be missed.
  Sartura's Whirlwind duration makes this irrelevant to the current rule.

## Exact next step

No further code change is required before the next chat.

Resume from `design/temp-cc-immunity` at `e4dac9b2`. `main` was re-verified on
2026-09-20 and remains at `37ca7cef`, so the branch is 23 commits ahead and 0
behind. Before changing runtime code, reproduce/identify the newly reported
immunity issue and trace it through `CheckCCImmunity`, the explicit Nampower
`SPELL_MISS -> IMMUNE` path, the delayed missing-debuff verifier, the curated
general immunity guard, and `TempCCImmune`. Keep the branch unmerged until the
planned Sartura live validation is completed.

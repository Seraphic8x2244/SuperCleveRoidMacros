# CC, DR, Immunities and Temporary Immunities Rework

> Review draft created from:
> `docs/CC-IMMUNITY-DR.md`,
> `docs/TEMP-CC-IMMUNITY.md`,
> `docs/DEVELOPMENT-HANDOFF.md`, and
> `docs/CLASSICAPI-TODO.md`.
>
> Do not delete the source documents until this draft has been compared against
> all four and approved.

## Status

- Repository: `Seraphic8x2244/SuperCleveRoidMacros`
- Branch: `design/temp-cc-immunity`
- Base `main`: `37ca7cef4012cc0d76b7e559ac9517c785dbae79`
- Latest runtime-related commit: `e4dac9b24fd0b305fbd1dd7208564cee8b6dba44`
- TOC version remains `@project-version@`.
- Runtime work is currently in `Utility.lua` plus the small conditional changes
  already present in `Conditionals.lua`.
- The generalized immunity learner described below is design only. It has not
  been implemented.
- Sartura TempCCImmune is implemented but still needs live validation.

---

## 1. Why this branch exists

This started as a CC/immunity correctness pass and widened as each fix exposed a
different identity that had previously been conflated.

The useful history is:

1. Exact CC mechanics were collapsed too aggressively. A Gouge/Sap-style
   immunity could be learned as stun immunity and suppress unrelated stuns.
2. Nampower `SPELL_MISS` argument order was wrong, so direct miss-based
   immunity learning could silently miss the spell ID.
3. DR protection used the wrong grouping and an effectively permanent counter,
   so later real immunities could stop being learned.
4. Sartura showed that a real `IMMUNE` can be temporary and
   encounter-specific, not a permanent NPC fact.
5. The general protection guard was too broad and was replaced with curated
   aura IDs.
6. Anti-Magic Shield showed that temporary broad magic immunity is not the same
   thing as CC immunity.
7. Blackwing Spellbinder showed that even a permanent-looking `IMMUNE` can
   have several plausible causes: HoJ can fail while Cheap Shot/Charge can
   still stun. That requires separating exact CC, school immunity, broad spell
   immunity, broad CC immunity, and absolute immunity.

The resulting scope is now one coherent rework:

```text
CC classification
DR protection
permanent immunity learning
temporary immunity explanations
broad immunity inference
```

---

## 2. Core model

### 2.1 Identities that must stay separate

```text
ccType
    Exact DBC mechanic.
    Used by [cc:*] and CC landing checks.

immunityType
    Exact DBC mechanic recorded for learned NPC CC immunity.

DR type
    Vanilla diminishing-return pool.
    Internal only.

school
    fire / frost / nature / shadow / arcane / holy
    plus existing physical / bleed handling.

spellimmune
    Broad magical/spell immunity.
    Must not mean "has a Spell.dbc record".

ccimmune
    Broad immunity to all relevant CC mechanics.

immune
    Absolute/broad immunity state.

temporary explanation
    A live aura/DR/death/reflection/etc. that explains IMMUNE now but must not
    become permanent learned data.
```

These are overlapping axes, not a hierarchy.

Examples:

```text
Blackwing Spellbinder:
    spellimmune = true
    stunimmune  = false

Sartura during Whirlwind:
    stunimmune  = true temporarily
    spellimmune = false
    ccimmune    = false

Fire-immune NPC:
    fireimmune  = true
    spellimmune = false
```

### 2.2 Exact CC taxonomy

`[cc:*]` follows the Vanilla client DBC mechanic exactly. Aliases may share a
mechanic; one conditional name must not span several mechanics.

| DBC mechanic | ID | Canonical CC type |
|---|---:|---|
| Charm | 1 | `charm` |
| Disoriented | 2 | `disorient` |
| Disarm | 3 | `disarm` |
| Distract | 4 | `distract` |
| Fear | 5 | `fear` |
| Fumble | 6 | `fumble` |
| Root | 7 | `root` |
| Pacify | 8 | `pacify` |
| Silence | 9 | `silence` |
| Sleep | 10 | `sleep` |
| Snare | 11 | `snare` |
| Stun | 12 | `stun` |
| Freeze | 13 | `freeze` |
| Knockout | 14 | `knockout` |
| Bleed | 15 | `bleed` |
| Polymorph | 17 | `polymorph` |
| Banish | 18 | `banish` |
| Shackle | 20 | `shackle` |
| Turn | 23 | `turn` |
| Horror | 24 | `horror` |
| Interrupt | 26 | `interrupt` |
| Daze | 27 | `daze` |

Current aliases:

```text
slow                                  -> snare
disoriented                           -> disorient
grip                                  -> fumble
sap                                   -> knockout
incap / incapacitate / incapacitated  -> knockout (immunity input)
```

Important Vanilla detail: the 1.12 client `SpellMechanic.dbc` has 27 rows.
Player Sap reports mechanic 14. The later/broader server enum
`MECHANIC_SAPPED = 30` must not be treated as a Vanilla client DBC mechanic.

Mechanics 16, 19, 21, 22 and 25 are not CC for SCRM purposes.

Bare `[cc]` / `[cc:any]` remain aggregate loss-of-control checks through
`CCTypesLossOfControl`; that aggregate is separate from the exact mechanic
table.

### 2.3 DR is only a learning safeguard

DR matters here only because a DR-immune result must not become permanent NPC
immunity.

For NPC targets, vMaNGOS applies staged DR to exactly three
`DRTYPE_ALL` groups:

```text
DIMINISHING_CONTROL_STUN
DIMINISHING_TRIGGER_STUN
DIMINISHING_KIDNEYSHOT
```

All other staged groups are `DRTYPE_PLAYER`, so they cannot explain an NPC
`IMMUNE` and must not suppress NPC immunity learning.

Current classification:

```text
Kidney Shot                    -> stun_kidneyshot
Charge / Intercept stun        -> stun_control
other mechanic-12 client cast  -> stun_control
other mechanic-12 proc         -> stun_trigger
```

Implementation notes:

- Kidney Shot uses rogue family bit 21 (`0x00200000`) rather than only IDs.
- Charge 7922 and Intercept 20253/20614/20615 are the explicit triggered
  exceptions classified as controlled stun.
- Client-initiated vs triggered is reconstructed from Nampower
  `SPELL_CAST_EVENT` correlation.
- `recentCCHits[targetGUID][drType]` resets after
  `DR_RESET_WINDOW = 20s`.
- An `IMMUNE` is discarded as DR only when that same pool has three or more
  landed hits inside the window.

Relevant vMaNGOS sources retained from the original design:

- `SpellEntry.h:52-79` — DR type by group.
- `SpellEntry.cpp:281-432` — group classification.
- `Unit.cpp:7881` — player-only DR application.
- `SpellClassMask.h:228` — Kidney Shot family bit.

### 2.4 Nampower miss payload

`TriggerSpellMissEvent` sends both `SPELL_MISS_SELF` and
`SPELL_MISS_OTHER` as:

```text
arg1 = casterGuid
arg2 = targetGuid
arg3 = spellId
arg4 = missInfo
```

Source retained from the original audit:
`nampower/spellevents.cpp:888-917`.

This matters because reading arg1 as the spell ID silently destroys direct
immunity learning.

### 2.5 Current learned immunity storage

SCRM already stores school and exact CC immunity in
`CleveRoids_ImmunityData`.

Existing school buckets:

```text
fire
frost
nature
shadow
arcane
holy
physical
bleed
unknown
```

Existing learned CC buckets are canonical `cc_<mechanic>` keys.

Manual/buff-based entries remain supported. Existing user data is not silently
rewritten by this branch.

---

## 3. Temporary immunity handling

### 3.1 TempCCImmune contract

TempCCImmune answers one narrow question:

```text
Is this creature temporarily immune to this exact CC mechanic because this
curated encounter aura is active right now?
```

Rules are keyed by:

```text
creature entry -> aura spell ID -> CC mechanic
```

Current rule:

```lua
local TEMP_CC_IMMUNITIES = {
    [15516] = { -- Battleguard Sartura
        [26083] = { stun = true }, -- Whirlwind
    },
}
```

Therefore:

```text
15516 + 26083 + stun -> true
15516 + 26083 + fear -> false
15516 + other aura + stun -> false
other creature + 26083 + stun -> false
```

Admission rule: only add an entry when creature ID, aura ID, affected mechanic,
and the temporary relationship are all verified.

Do not infer TempCC rules from arbitrary DBC aura mechanics or NPC names.

### 3.2 Identity and lookup

- Creature identity uses ClassicAPI `UnitCreatureID(unit)`.
- Aura identity uses `C_UnitAuras.GetUnitAuraBySpellID(unit, auraID)`.
- Only curated aura IDs for the matched creature are queried.
- NPC/aura names are comments/debug only.
- No full aura scan or localized-name matching is required.

ClassicAPI encapsulates the normal creature GUID forms; pet GUID forms are not
used as creature-template identities for these rules.

### 3.3 Live conditional behaviour

`CheckCCImmunity(unit, ccType)` checks live TempCCImmune before learned
permanent/conditional immunity.

Expected Sartura behaviour with no stale permanent record:

```text
outside Whirlwind -> [immune:stun] false
during Whirlwind  -> [immune:stun] true
after Whirlwind   -> [immune:stun] false
```

### 3.4 Learning guards

Both automatic CC-learning paths use the same temporary check:

1. Nampower `SPELL_MISS -> IMMUNE`;
2. delayed missing-debuff verification.

While Sartura is Whirlwinding:

```text
stun IMMUNE -> explained by TempCCImmune -> do not learn
fear IMMUNE -> normal fear logic
root IMMUNE -> normal root logic
school IMMUNE -> normal school logic
```

TempCC state is never persisted.

### 3.5 General immunity guard

`IMMUNITY_GUARD_AURA_IDS` is a separate curated learning guard for temporary
protection/reflection that makes an `IMMUNE` observation inconclusive.

Current categories include:

```text
Full protection:
    Divine Protection 498, 5573
    Divine Shield     642, 1020
    Ice Block         11958, 27619

Magic immunity:
    Anti-Magic Shield 7121, 19645, 24021

Physical protection:
    Blessing of Protection 1022, 5599, 10278

Reflection:
    explicit spell-reflection, school-reflector and NPC reflection auras
```

This table was deliberately curated after removing broad DBC-mechanic
assumptions and unrelated effects.

Same-name effects are not enough evidence. Absorb/damage-reduction shields are
excluded; TBC Spell Shield 33054 is not a Vanilla immunity rule.

The current table means only:

```text
do not learn this failure as permanent while this aura explains it
```

It is not yet a typed live `spellimmune` / `immune` provider.

### 3.6 Temporary explanations must run first

Before permanent inference, an `IMMUNE` observation must first be checked
against live explanations such as:

- curated TempCCImmune;
- full protection;
- magic immunity;
- physical protection;
- reflection;
- DR;
- recent death;
- debuff-cap ambiguity.

Explained events must not reinforce permanent immunity candidates.

---

## 4. Generalized immunity learner direction

### 4.1 Vocabulary

The proposed model needs these independent categories:

```text
School:
    fireimmune
    frostimmune
    natureimmune
    shadowimmune
    arcaneimmune
    holyimmune

Broad delivery:
    spellimmune

Broad CC:
    ccimmune

Exact mechanic:
    stunimmune
    fearimmune
    rootimmune
    knockoutimmune
    ...

Absolute:
    immune
```

`physical` and `bleed` remain existing immunity dimensions even though they
are not part of the six magical schools.

Whether the new names become user-visible syntax is still undecided. Do not
change macro syntax until that is settled.

### 4.2 Observation -> inference -> confirmed fact

The learner should stop treating one `IMMUNE` as one immediate permanent
answer.

Conceptual states:

```text
unknown
candidate
confirmed
```

Example:

```text
HoJ -> IMMUNE

possible:
    holyimmune
    spellimmune
    stunimmune
    ccimmune
    immune
```

Then:

```text
Charge Stun -> LANDS

eliminate:
    stunimmune
    ccimmune
    immune

HoJ now means:
    holyimmune OR spellimmune
```

Then:

```text
Fireball -> IMMUNE

possible:
    fireimmune
    spellimmune

common explanation with HoJ:
    spellimmune
```

A Frostbolt `IMMUNE` strengthens that hypothesis.

However:

```text
holyimmune + fireimmune
```

can mimic `spellimmune` for only those observations. Therefore multiple
`IMMUNE` events are evidence, not automatic proof.

### 4.3 Successful hits are negative evidence

Successful observations can cheaply disprove broad candidates:

```text
Frostbolt HITS
    -> not spellimmune
    -> not frostimmune
    -> not immune

Cheap Shot HITS
    -> not stunimmune
    -> not ccimmune
    -> not immune

Fear HITS
    -> not fearimmune
    -> not ccimmune
    -> not immune
```

Negative inference must not silently delete explicit/manual user records until
that interaction is designed.

### 4.4 Blackwing Spellbinder is the main broad-immunity regression case

Creature entry 12457 is annotated by vMaNGOS migration
`20231216221145_world.sql` as:

```text
Blackwing Spellbinder (HAS AURAS: Spell Immunity)
```

The same migration removes broad mechanic-immunity bits and records the
important stun distinction:

```text
physical/melee stuns can work
HoJ / grenade-style magical stun attempts can return IMMUNE
```

Required model:

```text
spellimmune = true
stunimmune  = false

HoJ        -> blocked
Cheap Shot -> can stun
Charge     -> can stun
```

Therefore an HoJ `IMMUNE` must not automatically create permanent
`cc_stun`.

The exact Vanilla Spell Immunity aura/effect used by this NPC still needs to be
identified before a generic detector is implemented.

### 4.5 Spell Shield / Anti-Magic cases

The discussed ZG and Stratholme Spell Shield NPCs may be further examples of
temporary broad spell immunity rather than CC immunity.

Before adding them:

- identify exact creature IDs;
- identify exact Vanilla spell/aura IDs;
- verify the actual aura/effect semantics;
- distinguish true immunity from absorb or damage reduction.

The already-verified Anti-Magic Shield IDs 7121/19645/24021 remain the current
known broad magic-immunity guard family.

### 4.6 `spellimmune` cannot mean "spell ID exists"

WoW represents many physical/melee abilities in Spell.dbc.

The classifier must reproduce game behaviour, not use the existence of a spell
record.

Required distinction:

```text
HoJ / magical spell effect -> blocked by spellimmune
Cheap Shot / physical stun -> not blocked by spellimmune
Charge Stun / physical stun -> not blocked by spellimmune
```

The exact primitive could be school mask, immunity aura type, spell attributes,
or another server/DBC concept. Verify before coding.

### 4.7 Proposed event footprint

No new scanner should be required.

The current paths already provide:

- Nampower `SPELL_MISS -> IMMUNE`;
- successful `SPELL_GO`;
- confirmed CC/debuff application;
- spell ID;
- DBC school;
- exact CC mechanic;
- target GUID/name;
- DR group;
- temporary guard state.

Preferred entry point:

```lua
ObserveImmunity(target, spellID, result)
```

The additional cost should be small table/bit operations at existing event
points.

Explicit non-goals:

- no new aura scanning frame;
- no target polling loop;
- no high-frequency `OnUpdate`;
- no duplicate combat-log parser;
- no whole-aura DBC classification pass.

### 4.8 Current guard should eventually become typed

The current boolean `IMMUNITY_GUARD_AURA_IDS` is sufficient to stop bad
learning but loses cause.

Likely direction:

```text
FULL_IMMUNITY_AURAS
SPELL_IMMUNITY_AURAS
PHYSICAL_IMMUNITY_AURAS
REFLECTION_AURAS
```

or one equivalent typed table.

Requirements:

- reflection is not immunity;
- magic protection is not absolute immunity;
- physical protection is not spell immunity;
- TempCC remains creature+aura+mechanic specific;
- matching remains numeric and curated.

---

## 5. Done on this branch

### CC / DR corrections

- Exact CC mechanic learning instead of a coarse stun bucket.
- Sap corrected to Vanilla mechanic 14 with compatibility aliases.
- DR safeguard limited to the three NPC-applicable stun pools.
- DR counts reset across the 20s window.
- Kidney/controlled/triggered stun pools stay separate.
- Nampower `SPELL_MISS` argument order corrected.
- Bare immunity checks resolve mechanic immunity as well as school immunity.

### Temporary immunity

- `TEMP_CC_IMMUNITIES`.
- Sartura 15516 / Whirlwind 26083 / stun rule.
- `UnitCreatureID` creature identity.
- by-ID aura lookup.
- live `CheckCCImmunity` integration.
- Nampower direct miss learning guard.
- delayed missing-debuff learning guard.
- no TempCC persistence or SavedVariables schema change.

### General protection audit

- Broad mechanic-25/invulnerability reasoning removed.
- `IMMUNITY_GUARD_AURA_IDS` curated.
- Ice Block added as real full protection.
- Anti-Magic Shield 7121/19645/24021 added as broad magic-immunity guards.
- absorb/damage-reduction lookalikes excluded.

### Locale/portability corrections

- TempCC decisions use numeric IDs/internal mechanic tokens.
- Aura-landed verifier uses Blizzard localized GlobalStrings rather than a
  hard-coded English `"is afflicted by"`.
- Hidden-CC/bleed classification uses IDs/mechanics.
- duplicate localized aura parsing hardened/removed.
- split-CC fallback localized.

---

## 6. Validation still required

### 6.1 Sartura

Before testing:

```text
/cleveroid removeccimmune Battleguard Sartura stun
```

Checklist:

- [ ] Before Whirlwind: `[immune:stun]` false.
- [ ] During Whirlwind: `[immune:stun]` true.
- [ ] Normal `[noimmune:stun]` HoJ refuses during Whirlwind.
- [ ] Forced plain HoJ returns `IMMUNE`.
- [ ] No permanent `cc_stun` is written.
- [ ] After Whirlwind: `[immune:stun]` false / HoJ eligible.
- [ ] Later stun can land normally.
- [ ] Unrelated CC immunity learning is not suppressed by Whirlwind.
- [ ] Direct Nampower miss and delayed verifier obey the same rule.
- [ ] Existing DR/protection guards remain unchanged.
- [ ] TempCC writes nothing to SavedVariables.
- [ ] Confirm aura 26083 is visible through the client aura API.

### 6.2 Generalized learner matrix

#### Blackwing Spellbinder

- [ ] Verify entry 12457 on the target server.
- [ ] HoJ returns `IMMUNE`.
- [ ] Cheap Shot can land.
- [ ] Charge Stun can land.
- [ ] At least one non-Holy magical school returns `IMMUNE`.
- [ ] No false permanent `cc_stun`.
- [ ] Broad spell immunity is confirmed only when evidence is sufficient.

#### Single-school immunity

- [ ] One magical school returns `IMMUNE`.
- [ ] Another magical school lands.
- [ ] `spellimmune` is disproved.
- [ ] Only the demonstrated school is learned.

#### Broad CC immunity

- [ ] Different delivery methods/mechanics fail.
- [ ] Ordinary non-CC spells can still land.
- [ ] `ccimmune` remains distinct from `spellimmune`.

#### Absolute immunity

- [ ] Physical and magical effects fail while active.
- [ ] Live `immune` is true.
- [ ] Temporary absolute protection does not become permanent learned immunity.

#### Temporary spell immunity

- [ ] Verify one Vanilla Spell Shield/Anti-Magic-style aura.
- [ ] Magical effects fail while active.
- [ ] Physical effects still work where appropriate.
- [ ] No permanent school/`spellimmune` record is created solely from that
      temporary state.

---

## 7. Design decisions still open

### Immediate blockers before runtime implementation

1. Identify the exact Vanilla basis of broad `spellimmune`, starting with:
   - Blackwing Spellbinder;
   - the discussed ZG Spell Shield mobs;
   - the discussed Stratholme undead Spell Shield mobs.
2. Define conservative candidate -> confirmed promotion rules so several
   narrow school immunities cannot masquerade as `spellimmune`.

### Remaining decisions

- [ ] Exact semantics of `fireimmune`, `frostimmune`, `natureimmune`,
      `shadowimmune`, `arcaneimmune`, `holyimmune`.
- [ ] Exact semantics of `spellimmune`, `ccimmune`, absolute `immune`.
- [ ] Whether these become user-visible tokens or remain internal categories.
- [ ] Query precedence for school + spell + CC + exact mechanic + temporary
      state.
- [ ] Whether broad categories can ever be confirmed from outcomes alone or
      require direct typed-aura evidence.
- [ ] Exact candidate/evidence structure and target keying.
- [ ] Persistence policy:
      - confirmed facts only?
      - unresolved candidates?
      - negative evidence?
      - evidence counts?
      - direct aura classifications?
- [ ] Manual/user records must remain distinguishable from inferred facts.
- [ ] SavedVariables migration must be explicit before schema changes.

Preferred rule: use the narrowest explanation that accounts for the evidence,
and do not promote a broad category while narrower confirmed facts explain the
same observations.

---

## 8. Known limitations and deferred cleanup

- Mouseover casts: `ProcessSpellMissSelf` does not learn when it cannot resolve
  a queryable unit because temporary aura checks would be unsafe. Keep this
  conservative behaviour unless a real reproduction justifies changing it.
- Historical SavedVariables may contain legacy `cc_sap`; current learning
  canonicalizes to `cc_knockout`. No automatic migration exists.
- Reflect handling could explicitly cancel matching pending verification;
  current miss/reason handling already prevents normal reflection from becoming
  permanent immunity.
- Some unrelated old combat-log fallbacks still contain English phrases.
- A very short temporary aura could end before delayed verification when no
  direct Nampower miss event is available. Sartura's Whirlwind is not affected
  by this timing risk.
- Do not extract a new Lua module unless the generalized learner becomes large
  enough to justify it.

---

## 9. Current implementation target

Keep the existing TempCC footprint small:

```text
TEMP_CC_IMMUNITIES
GetCreatureEntry
IsTemporarilyCCImmune
CheckCCImmunity integration
one guard in each automatic CC-learning route
```

Add the generalized learner as the smallest practical extension:

```text
existing event
    -> reject known temporary explanation
    -> classify observation
    -> update compact per-NPC evidence
    -> confirm only when rules are satisfied
    -> existing immunity query consumes confirmed facts
```

No runtime code change should be made until the `spellimmune` primitive and
confirmation rules are settled.

---

# Appendix A — ClassicAPI facts relevant to this rework

ClassicAPI is a hard requirement of this fork. Do not maintain alternate
non-ClassicAPI implementations. Light runtime guards are fine.

## C_UnitAuras

Useful APIs include:

```text
GetAuraDataBySpellName
GetUnitAuraBySpellID
GetAuraDataByIndex
```

Current capabilities important here:

- numeric aura matching;
- dispel type;
- applications/stacks;
- duration;
- non-player `expirationTime` and caster timing through the newer
  `Aura::Source` cache;
- caster-modified duration;
- combo-point finisher duration;
- Carnage refresh support in the DLL.

Remaining documented caveats:

- auras observed before login can lack source/timing;
- max-stack 5->5 refresh can be invisible;
- out-of-range group aura data is reduced.

The immunity rework should prefer by-ID aura queries and avoid rebuilding aura
state in Lua.

## Creature identity

Use `UnitCreatureID(unit)` for curated creature-template identity.

## Locale

Use numeric IDs and DBC/internal tokens for decisions. Localized names remain
display/debug material.

---

# Appendix B — Preserved ClassicAPI backlog outside this rework

This appendix preserves the unrelated information from
`CLASSICAPI-TODO.md` so that file can eventually be removed without losing
its backlog.

## Policy

ClassicAPI is mandatory for this fork; no fallback implementation should be
maintained for ClassicAPI-backed features.

## C_UnitAuras / aura features

Already done:

- `[magic]`, `[curse]`, `[disease]`, `[poison]`, `[dispellable]`
  and negations using debuff `dispelName`;
- `[magicbuff]` / `[dispellablebuff]` and negations for offensive dispel.

Still useful:

- spell-ID fast path for aura matching;
- better cross-unit stacks through `applications`;
- class-aware `[dispellable]`;
- optional type+name filters such as `[magic:Polymorph]`.

## Weapon enchant

Done:

- `C_Item.GetWeaponEnchantInfo`;
- `[mhenchant]` / `[ohenchant]` plus negations;
- ID or localized-name matching;
- `ClassicAPI.GetWeaponEnchant` / `GetEnchantName`.

Optional:

- route old `[mhimbue:Name]` matching through `GetEnchantName` and retire
  the tooltip name scan.

## Movement

Done:

- `GetUnitSpeed` / `IsFalling`;
- ClassicAPI-only `[moving]`;
- MonkeySpeed, Nampower movement fallback and the 100 Hz position-history
  buffer removed.

Do not use `IsSwimming` to mean moving; treading water is stationary.

## Action slots

Done:

- `GetActionInfo` wrapper;
- tooltip/texture action-slot heuristic replaced;
- dead SuperWoW `GetActionText` copy removed.

Known limitation:

- bag-instance items may return nil ID; current consumers only need spells.

Optional:

- migrate remaining macro-slot `GetActionText` use in `Core.lua` /
  `ComboPointTracker.lua`.

## C_Spell

Potentially useful for spellbook/cooldown/range plumbing, including
`GetSpellCooldown`, `SpellHasRange`, `GetSpellSchool`,
`FindSpellBookSlotByID`.

Do **not** blindly replace:

- `[known]`: current name/rank/talent semantics are richer;
- `[usable]`/reactive: existing Nampower semantics already match needs;
- cast-time tooltip scans: DBC time is base only and misses runtime modifiers.

## Timers

`C_Timer.After` / `NewTicker` can replace selected manual `OnUpdate`
timers and the old UnitXP aura-cleanup timer where semantics match.

## GUIDs

`UnitGUID` / `UnitTokenFromGUID` may replace SuperWoW GUID use in
`ComboPointTracker`, but verify string-format compatibility first.

## Focus

Done:

- native `focus` token;
- `GetFocusUnitId` / `TryTargetFocus`;
- `[focus]` / `[nofocus]`;
- `/focus` supplied by ClassicAPI companion addon.

## Nameplates

Done:

- `CountEnemiesMatching` uses `C_NamePlate.GetNamePlateGUIDs()`.

## Other situational APIs

Possible:

- `CastSpellNoToggle` / numeric spell-ID casting;
- `UnitStandState` / simple state helpers;
- `GetShapeshiftFormID` only where DBC form ID is actually desired.

Trap:

- `GetShapeshiftFormID` is not the 1-based action-bar form index used by
  existing `[stance:N]` / `[form:N]`.

## Keep existing non-ClassicAPI implementations where they are better

- cast-time tooltip scans;
- UnitXP distance/facing/behind;
- Nampower `FindPlayerItemSlot`;
- current rich `[known]`;
- current `[usable]` / reactive logic;
- `[rooted]` remains Nampower-backed.

## Conditionals audit already completed

Migrated:

- item cooldowns -> ClassicAPI `GetItemCooldown`;
- stealth conditionals / rogue form branch -> `IsStealthed`;
- enemy nameplate counting -> ClassicAPI nameplate GUIDs;
- focus -> native focus token.

## libdebuff retirement

ClassicAPI's `Aura::Source` cache now covers much of the reason libdebuff
exists. Treat this as a staged re-base, not a blind delete.

Current recorded footprint from the original backlog:

```text
28 public lib: methods
~726 internal Utility.lua references
consumers in 8 files
Conditionals.lua: 45 references
Compatibility/pfUI.lua: 39
Core.lua: 9
```

pfUI itself still retains libdebuff-style code while rebasing aura reads on
`C_UnitAuras`; that is the safer precedent.

Replaceable group:

```text
GetDuration
GetDebuffCaster
IsOurDebuff
UnitBuff / UnitDebuff
FindPlayerDebuff / FindPlayerBuff
GetAllDebuffsOnTarget
GetCachedIcon
ApplyCarnageRefresh
Dark Harvest start/end/reduction/time-remaining helpers
```

Keep group:

```text
ShouldApplyDebuffRank
DidSpellFail
WasSpellReflected
DidTargetEvade
ProcessMissReason
IsPersonalDebuff
GetSpellRank / GetSpellBaseName
HasPendingCast
```

Before removing the replaceable group, compare a difficult live case such as
Rip under Carnage:

```text
libdebuff:GetDuration(spellID)
vs
C_UnitAuras.GetUnitAuraBySpellID(...).duration
and
expirationTime - GetTime()
```

Also test the known pre-login-aura and max-stack-refresh gaps.

## Marginal follow-ups

- `[swimming]` could move to `IsSwimming()` and drop its Nampower version
  gate if desired.
- `[rooted]` has no ClassicAPI equivalent.
- Weapon imbue name matching can be simplified now that enchant ID -> localized
  name exists.

---

## 10. Review/delete procedure

Before replacing the four source docs with this file:

1. Compare this draft against all four originals.
2. Add anything materially missing.
3. Remove any remaining duplicated wording.
4. Confirm branch status, runtime head, untested work and exact next step are
   represented here.
5. Only then delete:
   - `docs/CC-IMMUNITY-DR.md`
   - `docs/TEMP-CC-IMMUNITY.md`
   - `docs/DEVELOPMENT-HANDOFF.md`
   - `docs/CLASSICAPI-TODO.md`
6. After deletion, this file becomes the handoff/status/design source of truth.

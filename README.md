# SuperCleveRoid Macros

Enhanced macro addon for World of Warcraft 1.12.1 (Vanilla/Turtle WoW) with dynamic tooltips, conditional execution, and extended syntax.

**[Full Documentation on the Wiki](https://github.com/brues-code/SuperCleveRoidMacros/wiki)**

## Requirements

| Mod | Required | Purpose |
|-----|:--------:|---------|
| [Nampower](https://github.com/brues-code/nampower/releases) (v3.0.0+) | ✅ | Spell queueing, DBC data, auto-attack events |
| [UnitXP_SP3](https://codeberg.org/konaka/UnitXP_SP3/releases) | ✅ | Distance checks, `[multiscan]` enemy scanning |
| [ClassicAPI](https://github.com/brues-code/ClassicAPI/releases) (v1.15.8+) | ✅ | Modern `C_*` API: dispel-type conditionals (`[magic]`, `[curse]`, …), `[moving]` speed, unit-filtered events |

## Installation

1. Download and extract to `Interface/AddOns/SuperCleveRoidMacros`
2. **Recommended pfUI:** Use [brues-code/pfUI](https://github.com/brues-code/pfUI) for full compatibility with macro spell scanning and action bar features

## Quick Start

```lua
#showtooltip
/cast [mod:alt] Frostbolt; [mod:ctrl] Fire Blast; Blink
```
- **Conditionals** in `[]` brackets, space or comma separated
- **Arguments** use colon: `[mod:alt]`, `[hp:>50]`
- **Negation** with `no` prefix: `[nobuff]`, `[nomod:alt]`
- **Target** with `@`: `[@mouseover,help]`, `[@party1,hp:<50]`
- **Fallback groups**, Blizzard-style: `[@mouseover,help][@focus,help][] Rejuvenation` tries each `[...]` in order and the first that passes casts the shared spell; `[]` always passes. Mixes freely with `;`
- **Spell names** with spaces: `"Mark of the Wild"` or `Mark_of_the_Wild`

**Multi-value logic:**

| Syntax | Logic | Example |
|--------|-------|---------|
| `[buff:X/Y]` | OR | Has X **or** Y |
| `[buff:X&Y]` | AND | Has X **and** Y |
| `[nobuff:X/Y]` | NOR | Missing **both** |
| `[nobuff:X&Y]` | NAND | Missing **at least one** |

**Comparisons:** `[hp:>50]`, `[hp:>20&<50]`, `[buff:"Name"<5]` (time), `[debuff:"Name">#3]` (stacks)

## Wiki

See the **[Wiki](https://github.com/brues-code/SuperCleveRoidMacros/wiki)** for complete documentation:

- **[Quick Start](https://github.com/brues-code/SuperCleveRoidMacros/wiki/Quick-Start)** — Syntax, multi-value logic, comparisons, special prefixes
- **[Slash Commands](https://github.com/brues-code/SuperCleveRoidMacros/wiki/Slash-Commands)** — All 35+ commands, priority macros, UnitXP scanning
- **[Conditionals](https://github.com/brues-code/SuperCleveRoidMacros/wiki/Conditionals)** — 150+ conditionals (player & target), short aliases, extended unit tokens, multiscan
- **[Reference Tables](https://github.com/brues-code/SuperCleveRoidMacros/wiki/Reference-Tables)** — CC types, damage schools, stat types, swing types
- **[Features](https://github.com/brues-code/SuperCleveRoidMacros/wiki/Features)** — Debuff timers, combo tracking, talent modifiers, TWoW mechanics
- **[Overflow Buff Frame](https://github.com/brues-code/SuperCleveRoidMacros/wiki/Overflow-Buff-Frame)** — Hidden buff display for 32+ buffs
- **[Immunity Tracking](https://github.com/brues-code/SuperCleveRoidMacros/wiki/Immunity-Tracking)** — Auto-learned NPC immunities
- **[Settings](https://github.com/brues-code/SuperCleveRoidMacros/wiki/Settings)** — Configuration and console commands
- **[Supported Addons](https://github.com/brues-code/SuperCleveRoidMacros/wiki/Supported-Addons)** — Compatible addons and integrations

## Optional Immunity Providers

SCRM's built-in immunity tracking remains the default. Companion addons can register an
alternative immunity checker without replacing or changing SCRM's saved immunity data.

```lua
CleveRoids.RegisterImmunityProvider("myaddon", "My Immunity Addon",
    function(unitId, spellOrSchool)
        -- true = immune, false = vulnerable, nil = unknown (more evidence needed).
        return MyAddon.IsImmune(unitId, spellOrSchool)
    end)
```

Each provider ID must be a unique nonempty string other than `"builtin"`.
The name must be a nonempty display string. The callback returns true for
known immunity, false for known vulnerability, or nil when evidence is
insufficient. Registration returns false for invalid or duplicate registrations.
Addons may register after SCRM loads.

The Blizzard macro window always shows an **Immunity Provider** dropdown row
above Delete / New / Exit, even with no external provider installed. It
allows selecting **SCRM Built-in** or one registered addon. The choice is
account-wide in `CleveRoidMacros.immunityProvider` and survives reloads.
Only the selected provider supplies immunity knowledge. The host neither
infers missing evidence nor mixes its own stored facts with external answers.

If a selected provider is missing, the selection is retained and its queries
remain unknown. A callback error or invalid return type raises a warning once;
it remains unavailable for the session until explicitly reselected. This
operational failure is distinct from nil, which is a normal unknown result.
In external mode, unknown makes both [immune] and [noimmune] fail. The built-in
learner and all automatic writes remain dormant even on provider failure.
Users must explicitly select SCRM Built-in to restore original behaviour.
Manual management commands still work and legacy `CleveRoids_ImmunityData`
is neither migrated nor cleared by provider switching or startup while an
external provider is selected.

## Known Issues

- Action-bar macros are identified by slot, so blank or duplicate macro names are fine. Only macros referenced *by name* (`{MacroName}` nesting, `/runmacro "Name"`) still need a unique name to disambiguate.
- Reactive abilities must be on action bars for detection
- Debuff time-left conditionals only work on own debuffs unless pfUI libdebuff or Cursive has data
- Macro line length: 261 characters max (MacroLengthWarn extension prevents crashes)

## Supported Addons

**Unit Frames:** [pfUI](https://github.com/brues-code/pfUI), LunaUnitFrames, XPerl, Grid, CT_UnitFrames, agUnitFrames, and more

**Action Bars:** Blizzard, [pfUI](https://github.com/brues-code/pfUI), Bongos, Discord Action Bars

**Integrations:** [SP_SwingTimer](https://github.com/jrc13245/SP_SwingTimer), [TWThreat](https://github.com/MarcelineVQ/TWThreat), [TimeToKill](https://github.com/jrc13245/TimeToKill), [QuickHeal](https://github.com/jrc13245/QuickHeal), [Cursive](https://github.com/pepopo978/Cursive), [ClassicFocus](https://github.com/wtfcolt/Addons-for-Vanilla-1.12.1-CFM/tree/master/ClassicFocus), [SuperMacro](https://github.com/jrc13245/SuperMacro-turtle-SuperWoW)

> **Note:** For pfUI users, the [brues-code/pfUI fork](https://github.com/brues-code/pfUI) includes native SuperCleveRoidMacros integration for proper cooldown, icon, and tooltip display on conditional macros.

## Credits

Based on [CleverMacro](https://github.com/DanielAdolfsson/CleverMacro) and [Roid-Macros](https://github.com/DennisWG/Roid-Macros).

MIT License

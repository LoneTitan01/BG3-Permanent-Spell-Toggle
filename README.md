# Permanent Spell

A Baldur's Gate 3 mod that gives every party member a toggleable **Permanent Spell** passive. While it's on, spells that character casts that would normally last **Until Long Rest** last permanently instead.

## Features

- **Permanent Spell toggle:** added automatically to every playable character. While it's on, Until Long Rest spells you cast (Mage Armor, Aid, Longstrider and so on) don't end on a long rest.
- **End Permanent Spells cantrip:** given to any character carrying a permanent spell from this mod. Casting it removes those spells from yourself. Permanent effects from the base game or other mods are not touched. The cantrip costs nothing and disappears once you have no permanent spells left.
- **Only affects new casts:** the toggle decides what happens when you cast. Turning it on doesn't make spells you already cast permanent, and turning it off doesn't end permanent spells you already have. Use the cantrip to remove those.

Only non-concentration spells that last Until Long Rest are affected. Spells from other mods are supported if they follow the same pattern.

## Requirements

- [BG3 Script Extender](https://github.com/Norbyte/bg3se) (v29 or newer)

## Installation

1. Install the Script Extender.
2. Install `PermanentSpell.zip` with your mod manager (Vortex or BG3 Mod Manager), or put `PermanentSpell.pak` in `%LOCALAPPDATA%\Larian Studios\Baldur's Gate 3\Mods`.
3. Enable the mod in your load order.

You can add it to an existing save. To uninstall, cast End Permanent Spells on every character that has it, then save before removing the mod.

## How it works

When the game loads, the mod makes a copy of every Until Long Rest spell status, named `PERMSPELL_<original name>`, and marks the copy to survive long rests. When a character with the toggle on casts one of these spells on a party member, the mod swaps the normal status for its permanent copy. The cantrip only ever removes `PERMSPELL_` statuses.

## Known limitations

- **Checks by status name:** the permanent copy has a different name from the original. Game logic or other mods that look for the original status by name won't see the permanent version.
- **Recasting:** recasting the spell normally, with the toggle off, replaces the permanent version with a normal one.
- **On-apply effects:** swapping the status removes and re-applies it, so effects that trigger when a status starts or ends fire one extra time.
- **Party only:** only spells cast on party members become permanent.

## Building from source

The source is in `PermanentSpell/`. Building needs Python 3 with PyYAML, and [LSLib](https://github.com/Norbyte/lslib)'s `Divine.exe`.

1. Set `divine_path` in `build_config.yaml` to your `Divine.exe`.
2. Run:

   ```
   python build.py
   ```

This converts the text file in `Localization/` to `.loca`, packs the mod, and writes `PermanentSpell.pak` and `PermanentSpell.zip` to `Packages/`.

## Author

LoneTitan01

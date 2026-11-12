# Persistent Stalkers

Your character, kept on your own computer and taken into every game you play or join, like a character in an MMO. For S.T.A.L.K.E.R. Anomaly / G.A.M.M.A., solo and xrRazom co-op.

The profile holds what you carry and where (weapon slots, outfit, helmet, backpack, artefact belt, the active weapon), with each item's condition, upgrades, ammo, uses and part wear, plus your money, rank, reputation, each faction's goodwill toward you, hunger, thirst, sleepiness, skill levels, your Skill tree class, perks and XP (when Skill tree is installed) and learned crafting recipes. Quest items stay with the world they came from. Health, bleeding, every body part, radiation and psy health stay with the save: when a save loads, that state is remembered and put back onto you after the profile's gear is applied. 

**Requires Master Core** (shared code for DANTE, Private Backrooms, and Persistent Stalkers). Install and enable it too; its place in the load order does not matter. Without it the mod turns itself off.

## Save mode

Pick it in MCM (Mod Configuration Menu, "Persistent Stalkers"). It is **Off** until you do, so installing the mod changes nothing.

- **Character follows the save** (recommended). Your character is written to the profile each time you save. Loading a save you played with that profile gives you the character from that save, as usual: die and reload, and you have the ammo and medkits you had at that save. Taking the profile into another game (a new game, someone else's world) gives you the character from your last save.
- **Character lives in the profile.** Your character is written whenever anything changes - equipment, state, goodwill. Every game you load or join with that profile gives you that character, whatever its state is. Loading an older save rolls back the world, not you. Things you picked up since that save are in the world again (think of it as the world respawning). Health and bleeding are the save's, read off the loaded character and put back after your gear is, so dying of a bleed and reloading does not put that death back on you. If you die and the game reloads, you come back with the gear you had a moment before death, unless you tick **Death takes the carried gear**. With DANTE installed, its death rule applies instead.
In co-op each player picks their own mode and profile. The host should have the mod too: it tells everyone which save was loaded.

## The profile menu

Nothing is loaded onto your character, and nothing is written to a profile, unless you choose it here. The menu lists every profile, and for the one you click it shows its money, rank and the rest, and its loadout laid out like a small inventory: what's equipped, the artefact belt, and the backpack. Hover an item to see its card.

- **After loading a save**, the menu opens on its own when that save wasn't last played with your current profile: a new game, an old save, a save from another profile, or someone else's world. Choose a profile, or **None** to play the save's character without any profile. A save you played with your current profile loads straight through, so dying and reloading needs no clicks.
- **During play**, press **F8** (change it in MCM) to switch: your current profile is saved first, then the one you pick replaces your character. Health and bleeding stay. Save the game afterwards, so your saves follow the new profile. **None** stops using a profile and keeps your character.
- **New profile**: type a name and press **Create and play**. It starts as a copy of the character you have now: on a new game that's the starting character, and in a playthrough it lets you take the same character two ways.

Each profile is one character, stored in `D:\Anomaly\appdata\persistent_stalkers_profile_<name>.txt`. It is not tied to your nickname. The menu remembers your choice for the next game. MCM can create profiles and remove them, but never the one in use or `default`. You type the name to confirm, and a backup file is kept.

## What is carried

Gear is always carried. The rest can be turned off in MCM: money, rank and reputation, faction goodwill, faction (off by default, experimental), hunger/thirst/sleep, skills, class and perks, recipes. Health is not one of these: it stays with the save.

# Persistent Stalkers (main menu version)

Your character, kept on your own computer and taken into every game you play or join, like a character in an MMO. You choose it at the main menu, before starting, loading or joining a game. For S.T.A.L.K.E.R. Anomaly / G.A.M.M.A., solo and xrRazom co-op.

This is the `menu_load` branch: the main menu version of Persistent Stalkers, still being tried out. The first version, on `master`, asks which character to play after a save has loaded, and lets you switch with a key during play. This one moves the choice to the main menu. Use one or the other, not both (this one installs as `PS_v2` in Mod Organizer, the first as `Persistent_stalkers`): they share their profile files, so your characters carry over.

The profile holds what you carry and where (weapon slots, outfit, helmet, backpack, artefact belt, the active weapon), with each item's condition, upgrades, ammo, uses and part wear, plus your money, rank, reputation, each faction's goodwill toward you, hunger, thirst, sleepiness, skill levels, your Skill tree class, perks and XP (when Skill tree is installed) and learned crafting recipes. Quest items stay with the world they came from. Health, bleeding, every body part, radiation and psy health stay with the save: when a save loads, that state is remembered and put back onto you after the profile's gear is applied.

**Requires Master Core** (shared code for DANTE, Private Backrooms, and Persistent Stalkers). Install and enable it too; its place in the load order does not matter. Without it the mod turns itself off. This mod replaces the main menu script, so it must be above MCM (Mod Configuration Menu) in Mod Organizer's priority; `tools\install.ps1` puts it there.

## The main menu

The game's options (New game, Load game, Options, and Connect in co-op) are on the right. The left and middle of the screen show your characters:

- **The list** has every profile, and **None** first. Click one to select it. The selected one is what you play in any game you start, load or join from here. It is remembered between sessions.
- **Next to the list** you see the selected profile: its money, rank, faction, class, and its loadout laid out like a small inventory: what is equipped, the artefact belt, and the backpack. Hover an item to see its card.
- **New profile** asks for a name. A new profile is empty: it takes the character of the first game you play with it. Start a new game for a fresh character, or load a save to get a copy of that save's character. **Remove profile** removes the selected one, after a warning (see below).
- **None** plays every save with its own character, as without this mod. Nothing is read or written.

To play another character, quit to the main menu and select it. The pause menu during a game shows the one you are playing, and cannot change it. (For testing: with the game started with `-dbg`, F8 during play opens the list and switches profiles on the spot.)

Each profile is one character, stored in `D:\Anomaly\appdata\persistent_stalkers_profile_<name>.txt`. It is not tied to your nickname.

**Remove profile** (at the main menu, under New profile) removes the selected profile after a warning. `default` cannot be removed. A backup file is kept in the same folder (`…removed-<time>.txt`). To play a removed character again, create a new profile, select it, and load a save you played with the old one: a new profile takes the character of the first game played with it, so it becomes the character as that save holds it. Anything the old profile gained after that save is only in the backup file.

## Constant saves

The mod works from the moment it is installed: the `default` profile is selected and takes the character of your first game. To play without it, select **None** at the main menu.

How the profile relates to your saves is one checkbox at the bottom of MCM ("Persistent Stalkers"): **Enable constant saves (Warning: may break the game)**.

- **Off (the default): your character follows the save.** Your character is written to the profile each time you save. Loading a save you played with that profile gives you the character from that save, as usual: die and reload, and you have the ammo and medkits you had at that save. Any other game (a new game, someone else's world, a save you played with another profile) gives you the character from your last save.
- **On: your character lives in the profile.** Your character is written whenever anything changes. Every game you load or join gives you that character, whatever its state is. Loading an older save rolls back the world, not you. Things you picked up since that save are in the world again (think of it as the world respawning). If you die and the game reloads, you come back with the gear you had a moment before death, unless you tick **Death takes the carried gear**. With DANTE installed, its death rule applies instead.

Loading a save while a different profile is selected replaces that save's character with the profile's. The save file itself does not change until you save over it.

The checkbox takes effect at once, even in a game. In co-op each player picks their own setting and profile. The host should have the mod too: it tells everyone which save was loaded.

## What is carried

Gear is always carried. The rest can be turned off in MCM: money, rank and reputation, faction goodwill, faction (off by default, experimental), hunger/thirst/sleep, skills, class and perks, recipes. Health is not one of these: it stays with the save.

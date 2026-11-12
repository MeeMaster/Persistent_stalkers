# Persistent Stalkers agent spec

This file is the implementation spec. `README.md` is the player summary. If they disagree, this file wins on behavior, and the README should be updated to match.

## What this is

A character profile for G.A.M.M.A. (Anomaly 1.5.3), solo and xrRazom co-op, like a character in an MMO: what the player carries and where (slots, belt), money, rank, reputation, needs, skills and recipes live in a file on the player's own machine, and travel with them into any world they play or join. Health, bleeding, body parts, radiation and psy health stay with the save.

It is its own mod, developed and installed on its own, like DANTE (`D:\Code\DANTE`) and Private Backrooms (`D:\Code\Private_backrooms`). It does not depend on either. It depends on Master Core (`D:\Code\Stalker mods\Master_core`) for the text form and files (`master_core_text`: the profile files and events), the xrRazom session and events (`master_core_net`), the profile list with create and remove and the MCM profile controls (`master_core_profiles`, with the spec from `persistent_stalkers_profile.profile_spec()`), and the dev reload. A fix to those goes into Master Core (its `AGENTS.md`), not here. Without Master Core, `on_game_start` logs that it is not installed and the mod is off. GEM is not considered here (user's choice, 2026-10-21: GEM's own player profile, GEM `AGENTS.md`, is decided later).

Written 2026-10-21 from the design conversation (options A, B and C below). Checked in fengari against a fake engine (see Checks). Not yet run in game.

## Machine

- Mod Organizer: `D:\GAMMA`. Game: `D:\Anomaly`, launched as `D:\Anomaly\bin\AnomalyDX11AVX.exe` from the `GEM` profile. Logs: `D:\Anomaly\appdata\logs`.
- Write only this repo. Read `D:\GAMMA\mods` and `D:\Anomaly`, never edit them. Do not copy other mods' files in.
- Installed as a real directory of hardlinks at `D:\GAMMA\mods\Persistent_stalkers` by `tools\install.ps1` (DANTE's, renamed). The user runs it.
- This environment cannot launch the game. The user runs it and brings back the logs.
- Keep every `.ltx`, `.xml`, `.script`, and `.ps1` in CRLF. Check with a byte count (`tr -cd '\r' < f | wc -c` against `\n`).

## The design (decided 2026-10-21)

Two stores, the world save and the profiles, with items crossing between them (pickups, drops, trades, stashes, gifts). Loading an older save rolls back one store and not the other, so every crossing since that save is either doubled or lost. It cannot be fully reconciled. Two answers, both built, picked per machine in MCM (`persistent_stalkers/mode`, a dropdown):

- **A, "Character lives in the profile"** (`profile`, the MMO model). The profile is written continuously; a save stores only the world. Every load or join makes the actor match the profile, whatever the save or xrRazom restored. Reloading never undoes anything for the character. Duplication on reload is accepted as "the world respawned". A crash loses at most the last few seconds of one player, and no world save is needed on leave, so save restrictions (YACS and the like) don't matter.
- **B, "Character follows the save"** (`save`). The profile is written at each save. Loading a save takes that save's character. Solo behaves as usual. In co-op each client keeps a snapshot of its character per save key, which the host sends. Moving to another world still works (the profile is the last save's character), but loading an older save of the first world brings that save's character back.
- `off` (default): the mod reads and writes nothing. Installing it changes nothing until a mode is picked.

Not built: **C** (A plus a host ledger of object ids taken by players, released on loading an older save). Kept in reserve if A's duplication matters in play.

Rejected: writing the profile on disconnect (one side of a transfer without the other: duplication or loss), and saving the world on every leave (overkill, and it fights save-restricting mods).

### Choosing the profile: the profile menu (decided 2026-11-11)

Until 2026-11-11 every load or join applied the MCM-selected profile, and an empty profile silently adopted. That made unintended loads and writes possible: the wrong profile active, or a bad read written away. Now a game is connected to a profile only by a choice, made in the profile menu (`persistent_stalkers_menu.script`). The user's decisions, in order: B ("on save") is the more stable mode and stays the main one, since a death reload should bring back both the fight and the resources you had for it; the choice is a full window listing every profile with its loadout drawn like a scaled-down inventory, not interactable; switching happens through that window, opened by a key; a new profile is always a **copy** of the character you have (a fresh start takes the starting character, a playthrough can branch); no blocking of switches in danger (god mode and the debug console are available to everyone, so it would prevent nothing).

- **Every save records what it was played with**: the profile in use, `none`, or nothing (never played with this mod on). Host and solo: `m_data.persistent_stalkers.profile`. Client: `persistent_stalkers_worlds.txt` under the host's save key (`set_world_profile`, at `pst_saved`, 100 keys kept).
- **Arrival**: once the world has settled (Timing), a save whose record equals the selected profile goes straight through: `target()` as before (B keeps the save's character or the client's snapshot, A applies the profile), or nothing at all for `none`. Anything else (a new game, a save from before the mod, another profile's save, a client without a key) opens the menu (phase `choosing`). It cannot be closed without a choice; if something else closes it (a death, another dialog), it opens again after 1 s.
- **Choosing on arrival**: a profile sets the selection (`use_profile`, and `set_selected`, so the next game starts from it) and runs `target()` for it; an empty one adopts. None plays the save's character, writes nothing (phase `none`).
- **Switching** (the menu key or MCM's button, phase `live` or `none`): the profile in use is written first (when one is), then the new one's **file** replaces the actor (`apply_character`, the `carry_*` boxes, health kept), or an empty one adopts. None stops using a profile and keeps the character. A tip suggests saving so the saves follow the new profile; until then an older save is still recorded with the old one, so loading it asks.
- **New profile** (the menu's box): `create_profile`, then chosen as above, so it adopts: a copy.
- MCM has no profile list (user's request, 2026-11-11: the menu made it unnecessary). Choosing happens only in the profile menu; MCM keeps the status line, creating and removing.

## Profiles

From Private Backrooms (`private_backrooms_rooms.script`, "Profiles"), lifted almost as it is (`persistent_stalkers_profile.script`):

- Named profiles, chosen in the profile menu (above). The choice is remembered for the next game in `persistent_stalkers_selected.txt` (`{ profile }`, `set_selected` / `selected_profile`). Until 2026-11-11 it was MCM's `persistent_stalkers/active`; when the file is not there yet, that value is read once straight from `axr_options` (`axr_main.config:r_value("mcm", …)`: MCM's `ui_mcm.get` refuses a key with no option on the page). The choice is the machine's, not the save's, and not tied to the nickname. With none chosen, or a removed one, `default`.
- Files in `$app_data_root$` (`D:\Anomaly\appdata`): `persistent_stalkers_profile_<name>.txt` (the character), `persistent_stalkers_profile_<name>.saves.txt` (B's snapshots), `persistent_stalkers_profiles.txt` (the list, `default` implied), `persistent_stalkers_selected.txt` (the choice), `persistent_stalkers_worlds.txt` (a client's record of which profile each host save was played with). Names: letters, digits, `_`, `-`, up to 32.
- Text is a Lua-like table, written and read by the script's own encoder (no `loadstring`: the same reader takes events). Keys are sorted, so the same character always gives the same text, and a write is skipped when nothing changed. Numbers to 4 decimals; userdata (CTime) is dropped.
- No `os.remove` / `os.rename` in the engine: a write goes to `<file>.tmp`, then `<file>`; a load takes `<file>`, else `<file>.tmp`; an unreadable file is copied to `.bad`.
- **Shrink backups.** A write that leaves fewer than half of the items (of at least 6) first copies the old file to `.bak1` (`.bak2`, `.bak3` rotate). A wrong read, or a death with `death_strip`, can then be undone by hand.
- **Creating** writes an empty profile (`revision 0`, no `character`). An empty profile **adopts**: the first time it is chosen in the menu, it takes the character as it is (a copy). A file of that name not on the list is listed as it is.
- **Removing**: never `default` or the active profile, only with the name typed again. Both files are copied to `…<name>.removed-<time>.txt` / `….saves.removed-<time>.txt` and emptied.
- **None** (user's request, 2026-10-21): the first entry of the profile menu, value `none`. No profile: the effective mode is `off`, nothing is read or written, and the save's character is played (phase `none`). Saves made then are recorded as `none`, so reloading them goes straight through. No file is ever made for it, and `none` cannot be created as a profile name (any case). `write()` refuses whenever the effective mode is `off`.
- **Only the profile menu switches.** MCM's list was limited to the main menu on 2026-10-21 (a pick there in a game replaced the character and, in A, overwrote the old profile, so a misclick could lose a character), and removed on 2026-11-11 with `set_profile`. The profile is pinned for the session on each map's first update (`persistent_stalkers_profile.pin`); only the menu (`use_profile`) changes it.
- A "load this profile onto the current character" MCM button with a yes/no box (2026-11-11, copying a profile into the active one) was built and replaced the same day by the profile menu.
- File: `{ version, revision, written, character }`; `revision` counts writes. Snapshots: `{ version, order = { newest key first }, by_key = { [key] = { character, t } } }`, 40 kept.

## The character

`persistent_stalkers_state.read()`:

- `items`: every carried item except **world items**, each `{ section, cond, uses, ammo, mag, ammo_type, addons, silencer, launcher, upgrades, parts, mag_data, mag_carried, slot, belt }` (Master Core's item record, `master_core_items.read`, plus where it sits; in grenade mode `grenades` replaces `mag` and `ammo_type`). World items (`is_world_item`): `quest_item` sections, DANTE's story-item patterns (`strelok`, `docuuments`, `intel`, `quest`, `notes`, `instruction`, `good_psy_helmet`, `bad_psy_helmet`), and `xrr_*`. The list is Master Core's (`master_core_world.is_story_item`, shared with DANTE). They belong to the world's tasks: never stored, never released or created.
- `slot`: `item_in_slot(1..13)` (G.A.M.M.A. `ui_inventory`: 1 knife, 2 pistol, 3 rifle, 4 grenade, 5 binoculars, 6 bolt, 7 outfit, 8 PDA, 9 detector, 10 torch, 11 artefact, 12 helmet, 13 backpack). `belt`: `item_on_belt(0..belt_count-1)`. `active`: `active_slot()`.
- `addons`: the packet's `addon_flags` bits (1 scope, 2 grenade launcher, 4 silencer), read from the game object (`weapon_*_status` 2: `weapon_is_scope` / `weapon_is_grenadelauncher` / `weapon_is_silencer`; otherwise the packet's bit). The server object's copy lags: a silencer screwed on was not stored (2026-10-27, as Private Backrooms 2026-10-26). `silencer` / `launcher`: the attached addon's item section (`silencer_name` / `grenade_launcher_name` through `utils_item.get_param`, so an upgrade's override counts). G.A.M.M.A. gives each weapon one silencer section. A created weapon whose addons differ once online (after the attach in step 2) is logged (`addons N, the profile has M`).
- `upgrades`: `iterate_installed_upgrades`, else the server packet (a client's mirror may list none live, DANTE probe). `parts`: the `parts` se var. `mag_data`: Mags Redux' `magazine_binder.get_data(id)` when that mod is loaded (it is disabled in the GEM profile; its data is keyed by object id, so a new item needs it moved: see Plan). `mag_carried`: the "ready" mark (`is_carried_mag`), set back with `toggle_carried_mag`.
- `money`, `rank`, `reputation`; `faction`: the true faction (`gameplay_disguise.get_default_comm()`, else the community without `actor_`).
- `goodwill`: each faction's community goodwill toward this player (`relation_registry.community_goodwill(faction, actor id)`), a map of faction name to a whole number, zeros included. Factions are `game_relations.factions_table`, else army, bandit, csky, dolg, ecolog, freedom, greh, isg, killer, monolith, renegade, stalker. This is the faction's attitude toward this one character. Faction-to-faction relations are the world's and are not stored. A profile written before this field has none: the first apply leaves the world's goodwill, and the next write stores it.
- `needs`: `satiety` (`cast_Actor():conditions():GetSatiety()`; the `satiety` property reads 1.0 per xrRazom), `thirst` (`actor_status_thirst.get_last_drink`), `sleep` (`actor_status_sleep.get_last_sleep`).
- Health is not stored. A profile used to keep `vitals` (`health`, `radiation`, `psy`, Body Health `limbs` / `timed`); that field is ignored. On an apply, `read_body()` memorizes the actor as the save or xrRazom left it: those vitals plus bleeding wounds (`conditions():WoundForEach`, one `{ bone, size }` per bone). After the gear is on, `apply_vitals` puts that back: wounds with `ClearWounds`, `AddWound(0, hit.wound, bone)`, `AddHit(size)` (xrRazom's restore; `AddWound` randomizes a non-zero size), limbs with `utils_obj.save_var` as DANTE does, `arszi_psy.set_psy_health`, radiation through `vital()`, then `set_health_ex`. A character written while bleeding out is not what the reload comes back as.
- `mod_state`: other mods' per-actor m_data, from the `MOD_STATE` list: each key names the module that owns it. Now only `skills_levels` (`haru_skills`). Read from the module's global when it keeps one, else `alife_storage_manager.get_state()` (the last save's). xrRazom's peer manifest (`xrr_peer_mdata.script`) lists more per-player keys; those that are world state (`visited_campfires`, garrison anger), keyed by object id (`carried_mags`), or campaign-timed (perk cooldowns) are left out on purpose. Add a key only with its owning module and a check that its `load_state` reads nothing else.
- `skill_tree`: Skill tree's character (own repo, `D:CodeStalker modsSkill_tree`; `spec_core.get_state()`, saved there as `m_data.spec_skill_tree`), only when that mod is enabled (`spec_core` loaded): `class`, `perks` (each bought perk's paid record), `xp` and `total` (general and per class, unspent and ever earned), `craft2` (secondary craft), `respecs`, `version`, and any field it adds later. Left with the world: `xp_seen` / `xp_seq` (a peer's record of the host's task award numbers), `boosted` (artifact object ids), `rolled` (the host's anomaly rolls). Not a `MOD_STATE` entry: Skill tree's `load_state` is local. Without the mod nothing is read, nothing is set, and a write keeps the profile's stored `skill_tree` (`KEEP_WHEN_ABSENT` in the profile script), so playing a world without Skill tree does not lose it. Added 2026-11-11 (user's request).
- `recipes`: every `recipe_*` section whose note `encyclopedia__notes_<recipe>` is unlocked (`ui_pda_encyclopedia_tab.is_unlocked_note`; G.A.M.M.A.'s workshop counts a recipe as known that way).

### Making the actor match (`apply`)

Reconcile, not wipe. xrRazom's avatar and the actor stay; only what they carry changes (releasing the avatar made clients invisible, Private Backrooms `clearable`).

1. **Plan.** Carried items and stored ones are keyed by section, sorted upgrades and addon flags. Within a key, pairs go by nearest condition. Paired items are **kept** and get the stored condition, uses, ammo and magazine in place. Carried items left over are **released** (`alife_release_id`; a client can release what it carries, DANTE probe `test_release`; a host-owned id is refused and logged). Stored items left over are **created**: `alife_create_item(section, db.actor)`. On a client that is xrRazom's client spawn (`xrr_spawn_actor_item`), which returns the server object and is recorded by the host like quest rewards. Its Mags Redux data goes to the new id with `magazine_binder.set_data` right after `alife_create_item`, before it comes online: online, the binder makes default data for an id with none, and a magazine came back empty and a weapon with its default magazine (DANTE `move_tree`, 2026-10-30, as Mags Redux's `alife_clone_weapon`). On the host and in solo, a weapon's addon flags and ammo type go into its packet before it comes online. A stored section that no longer exists stays in the profile and is not created.
2. **Item state**, once each new item is online on this machine (DANTE probe method `full`): weapons unloaded, upgrades installed with `inventory_upgrades.force_upgrade` set, then `set_condition`, `set_remaining_uses`, `ammo_set_count`, or `unload_magazine` + `set_ammo_type` + `set_ammo_elapsed`; Mags Redux data with `set_data`. A new weapon that came online without a stored silencer or launcher (always on a client) gets that item created in the backpack and, once online, `weapon_addon_attach`ed, as G.A.M.M.A.'s silencer toggle does (`item_weapon.toggle_silencer`). 1 s later an addon item still there (the engine destroys it only on the server) is released; one that did not attach stays in the backpack, logged `did not attach`. `parts` 1 s later (writing it in the creation frame crashed DANTE). Direct setters, not `alife_process_item`: G.A.M.M.A.'s `Process_Item` applies only one of `uses` / `cond` / `ammo` per call. Items not online within 30 s are counted missing. Since 2026-11-04 all of this is Master Core's (`master_core_items.create` / `queue` with `attach`, `wait` 30 s and a `done` callback; `cancel` forgets the entries). The packet now also gets condition and upgrades (outside a session), and a weapon stored in grenade mode comes back in the normal mode with its grenades beside it.
3. **Placement**, 1.5 s later: stored-in-backpack items out of slots and off the belt, then slots in the order 7 (outfit: equipping one empties the belt and can push helmet and backpack out), 12, 13, then the rest (`move_to_slot(obj, slot, true)`), then the belt (`move_to_belt`). Checked 1 s later and redone once; what is still wrong is counted misplaced. Then `activate_slot(active)`.
4. **Stats**, each per MCM checkbox (items always): money (`give_money(difference)`), rank and reputation (`set_character_rank`, `set_character_reputation`), goodwill (`relation_registry.set_community_goodwill` for each stored faction; not `inc_faction_goodwill_to_actor`, which also shifts a random enemy and a random ally), faction (`gameplay_disguise.update_default(comm, true)`, else `set_character_community`; off by default), needs (`actor_status_thirst.load_state({drink = …})` and `actor_status_sleep.load_state({sleep = …})`, as Soulslike and xrRazom do; `change_satiety(difference)`), mod state (the owner's `load_state({[key] = value})`, then `after`: `haru_skills.on_game_load` recomputes skill bonuses), skill tree (the character's fields of `spec_core.get_state()` replaced in place, the world's kept, then `spec_core.migrate`, `spec_core.changed()`: effects re-applied and the perk summary sent to teammates; with no class, `notify("no_class")` opens the class picker; a perk id that Skill tree does not know is logged and left for its `load_state` to refund at the next load), recipes (`unlock_note` for each one not yet known; known ones are never taken away). Then the memorized health (see above) is put back, after the outfit is equipped, so the save's health and bleeding land on the profile's gear.
   - Radiation: the actor's property setters may add (`CActor::Change*`) rather than set. `vital()` assigns the difference, reads back, and assigns the value if that did not land. Which one is true is unconfirmed. It is used only to put the save's radiation back.

The log gives `applying: N kept, N released (N refused), N created` and `applied: … missing, … misplaced, … recipes`, and a tip says the character is restored, with counts when something went wrong.

## Timing

- **Arrival** (each map's first update, `persistent_stalkers.script`): nothing is read or written until the world has settled. Host and solo: 3 s. Client: until `XrrNet():JoinSettling()` is false (xrRazom's gear restore; its own `kill_actor` waits on it), at most 90 s, plus 5 s, because xrRazom's `OnPeerConditionRestore` sets satiety, radiation and wounds again 1 and 3 s after its restore. A client also waits up to 20 s for the save's key (any mode: whether to ask depends on it).
- **Whether to ask** (`decide()`): the loaded save's record (`world_tag()`) equal to the selected profile goes straight to `target()` (or to phase `none` for `none`); anything else opens the profile menu, and the choice runs `target()` for the chosen profile. A client waits for the host's key in every mode (`WORLD_WAIT`), since the record is kept under it.
- **Which character** (`target()`):
  - A: the profile; an empty profile adopts.
  - B, host or solo: the save's own character when the save says it was last played with this profile (`m_data.persistent_stalkers.profile`). A save names the profile only when it is made while live (the world's character is the profile's), `none` while playing without one (phase `none`); before that (arriving, the menu open, an apply) it keeps the loaded save's name, or nothing (`played_with()`). A new game's first autosave is made on `fake_start` before the arrival settles: it used to name the profile, and loading it followed the new game's starting kit instead of applying the profile (2026-11-11). Otherwise (new game, a save from before the mod, from another profile) the profile, as a client with no snapshot. An empty profile adopts.
  - B, client: the snapshot stored under the loaded save's key, else the profile, else adopt.
- Then the profile is written from the actor ("live"). Until then, and while dead, during a death rule's handling of a death (DANTE's return; Master Core's `master_core_world.death_busy()`, where DANTE registers), or during an apply, nothing is written. Whether another rule keeps the player alive through a death (DANTE, Azazel, Soulslike) is `master_core_world.death_rule()`; until 2026-11-04 this mod read `zzz_dante` and the two modes itself.
- **A writes** every 5 s when the character changed, 1 s after an item is taken, dropped, used, put in or taken from a box, or a menu closes (trade), at every host save, and on `on_level_changing`.
- **B writes** at every save: the host's `save_state`, and on a client the host's `pst_saved` (current character and a snapshot under that key). Also once on arrival (the loaded character).
- **Level change.** On `on_level_changing` a marker file (`persistent_stalkers_level_change.txt`: profile, mode, time) is written: Lua restarts on a client after a map change (DANTE). The next first update with a marker under 180 s old for the same profile and mode keeps the character as it is (no restore). Whether `on_level_changing` fires on an xrRazom client is untested: without it, a client's map change is a normal arrival, restored from a profile at most 5 s old (A).
- **MCM Apply** on the mode: switched on mid-game, nothing happens until the next load or join (a tip says so); starting at once would replace the character in front of the player. Switched off, the mod stops at once and a restore in progress is dropped.

## Co-op (xrRazom)

- The mode and profile are each machine's: each player picks their own, for their own character.
- **Save keys.** The host (any mode, `off` included, so clients can use B) gives every save a key: `<session>-<counter>`, kept in the save (`m_data.persistent_stalkers = { session, counter, key, profile, mode }`). The session id is made at the first save of a world (time plus a random number) and the counter goes on from the loaded save. Every save sends `pst_saved {key}` to everyone. A client in arrival sends `pst_hello` to the host every 3 s until `pst_world {key}` answers (`""`: a new game, nothing saved).
- A client's `save_state` / `load_state` are xrRazom's surrogate (`xrr_peer_mdata_prime` / `apply`), not saves: ignored.
- What xrRazom already keeps per player in the host's save sidecar (`<save>.xrr_peers`, keyed by nickname): gear, money, rank, reputation, faction, satiety, thirst, sleep, radiation, wounds, actor pstor (Body Health limbs), and its peer m_data manifest (skills). In B, for a client who was in the loaded save, xrRazom's restore is already that save's character, so the reconcile keeps nearly everything.
- A host save made while a client is still restoring gives that client no snapshot (`host saved (<key>); not live here`). The next save does.

## Death

- DANTE active, Azazel, or Soulslike: nothing here; their rule keeps the player alive and the profile follows (A writes once DANTE's return is done).
- Otherwise (the game's death: death screen, reload), in A only: writing stops at `actor_on_before_death`, so the reload brings back the gear as it was just before death (the world rolls back). Health, bleeding, body parts, radiation and psy health are the save's, memorized when the save has loaded and put back after the profile's gear. MCM `death_strip` (off by default): the profile loses every carried item except what is equipped in slots 5, 8 and 10 (binoculars, PDA, torch, as DANTE keeps). A death cancelled after all (`flags.ret_value == false`, or the actor alive again) goes back to writing.
- B needs no rule: the reload's character is the save's.

## MCM

`persistent_stalkers_mcm.script` (strings `configs\text\eng\ui_st_persistent_stalkers_mcm.xml`), id `persistent_stalkers`:

- `mode`: list (dropdown) `off` / `profile` / `save`, default `off`; texts `ui_mcm_lst_pst_*`.
- What is carried: `carry_money`, `carry_rank`, `carry_goodwill` (on), `carry_faction` (off: xrRazom may set a client's faction back: `OnHostFactionSet`, `OnDisguiseRestore` at every proxy respawn), `carry_needs`, `carry_mod_state` ("Skills"), `carry_skill_tree` ("Class and perks", Skill tree), `carry_recipes`. Items are always carried. Health is not a checkbox: it is read from the loaded character and put back after the gear. Everything else is read either way; the boxes only decide what is set.
- `death_strip`.
- Profile menu: `menu_key` (`key_bind`, default `DIK_F8`, unbound in the user's `user.ltx`), `pause_menu` (off: pausing solo play with `device():pause` while the menu is open is untested), `open_menu` (a button, in a game only: `request_menu()`, opened on the first update with MCM closed).
- Profiles: `status` (desc with `ui_hook_functor`), `new_name` + `create`, `remove_target` + `remove_confirm` + `remove`. No profile list: choosing is the profile menu's. Creating and removing are available in a game too: neither touches the profile in use. The same controls as Private Backrooms, from Master Core (`master_core_profiles.page`; its `active` list is filtered out of the options here, so Master Core is unchanged; MCM 1.7 `button` with `functor_ui`, inputs read from the controls). Without Master Core the page has no profile controls. Master Core is looked up as a plain global (`master_core_profiles`), never `rawget`: MCM builds its pages at the main menu before the engine has loaded Master Core's scripts, and only a plain global loads a script on first use (with `rawget` the page showed only its Profiles header, 2026-11-10).

## The profile menu window

`persistent_stalkers_menu.script`, layout `configs\ui\ui_persistent_stalkers.xml` (one file: no `_16` variant; widths are corrected in script by `utils_xml.screen_ratio()`). Modelled on Skill tree's `spec_ui.script` (1024x768 units, `CScriptXmlInit`, `Init3tButton` callbacks, `HideDialog`; the key's release must not reopen what its press closed). Placeholder look: stock frame, buttons, edit box, fonts.

- Left: the rows (15 shown, Up / Down page through more): None first ("None: this save's character" on arrival, "None: keep my character" when switching), then every profile, with its Skill tree class after a dash when it has one (`class_name`: the class name translated, else the id), marked `(in use)` or `(empty)`. The row chosen first is the selected profile. Rows are check buttons (`InitCheck`, `ui_button_ordinary`) with a text window on top, as MCM's own list (`elements:btn_list`); the chosen row is kept checked, so it stays pressed, and its text is gold (user's request, 2026-11-11; `SetCheck` on a check button with that texture is unverified in game). Under them: a name box and "Create and play" (`create_profile`, then chosen: a copy).
- Right: the chosen row's name, when it was written, revision, nickname; money, rank, reputation, faction; item, recipe and skill-level counts; Skill tree's class, perk count and unspent XP (general and the class's) when the profile has them. None shows the actor as it is now (`state().read()`). Then the loadout, not interactable:
  - Equipped (user's request, 2026-11-11: the same layout as the inventory): G.A.M.M.A.'s equipment column (G.A.M.M.A. UI's `ui_inventory_16.xml`, `equipment`, which G.A.M.M.A. uses at every aspect ratio; its 273 x 768 units are made for 16:9, ratio 0.75). Shown from the top to y 566 (slots, quick slots, belt), scaled to the panel's height `s`, widths times `k = screen_ratio / 0.75`. Background `ui_inGame2_inventory_back`, cut with `GetTextureRect` / `SetTextureRect` to the same 566/768; if that fails, the background is hidden and the cells get plain boxes (logged). Every cell at its `cont_equ` position (slots 1–10, 12, 13; 11 is off screen there, so its item goes to the backpack), the pistol and rifle icons turned 90° (`EnableHeading` / `SetHeading`, sized as G.A.M.M.A.'s `utils_ui` does: the ratio on the height), each cell's grey condition bar (`ui_inGame2_inventory_status_bar`) at its place. Blockers as the inventory: helmet and backpack when the stored outfit's `helmet_avaliable` / `backpack_avaliable` is false, a belt cell (`cont_belt`, 5 at y 510) beyond the outfit's `artefact_count` plus what its upgrades' property sections add (never fewer than the stored belt items). Belt items past 5 go to the backpack. Quick slots are not stored: their cells stay empty.
  - Backpack (right panel): everything else, stacked by section (weapons, upgraded, loaded items alone; a count `xN`), packed first fit on a grid by each item's `inv_grid_width` / `height`, with the largest cell height (30 down to 10 units) that fits all of it.
  - Icons: the section's `inv_grid_x/y/width/height` cell of its `icons_texture` (else `ui\ui_icon_equipment`), 50 px a cell (as Med bag's `item_icon`), fitted into its box keeping its shape on screen. In the backpack, a coloured condition bar under items with a stored condition below 100 % (weapons, `use_condition`). Hovering an icon shows G.A.M.M.A.'s item card (`utils_ui.UIInfoItem(self):Update(nil, section)`, as `item_cooking` does); if that fails it is dropped for the window. Not drawn yet: attached scopes and silencers on weapon icons, upgrade icons.
- Bottom: `describe_choice(name, how)` (what the button does), then "Play as <name>" / "Play this character" / "Stop using a profile" (disabled for what is already in use), and Close (switch only; also Esc and the menu key).

## Repo layout

```
meta.ini
gamedata/configs/text/eng/ui_st_persistent_stalkers_mcm.xml  MCM page texts
gamedata/configs/ui/ui_persistent_stalkers.xml       profile menu layout
gamedata/scripts/persistent_stalkers.script          mode, arrival timing and choice, switching, writing, save keys, events, death, console
gamedata/scripts/persistent_stalkers_menu.script     the profile menu window, its key
gamedata/scripts/persistent_stalkers_state.script    reading the character, reconciling the actor to one
gamedata/scripts/persistent_stalkers_profile.script  profile files, list, snapshots, encoder
gamedata/scripts/persistent_stalkers_mcm.script      MCM page
gamedata/scripts/persistent_stalkers_dev.script      reload() for development
tools/install.ps1                                    links the mod into Mod Organizer, enables it
```

## Console

`run_string persistent_stalkers.status()`: mode, profile and revision, phase (`idle`, `waiting`, `choosing`, `applying`, `live`, `none`, `dead`, `off`), host or client, the save key, what the loaded world was played with, snapshot count, the file, and the stored and carried character in one line each. `write()` writes now (when live). `restore()` makes the actor match the profile now. `run_string persistent_stalkers_menu.open("switch")` opens the profile menu. `run_string persistent_stalkers_dev.reload()` re-reads the scripts (repo first: `D:\Code\Stalker mods\Persistent_stalkers\gamedata\scripts\`, through Master Core's `master_core_dev.reload`), carrying each module's state. Log lines start with `[PersistentStalkers]`. `run_string` needs `-dbg`.

## Checks

Fengari (Lua 5.3) with a fake engine: actor, inventory, slots, belt, items coming online a frame after creation, in-memory files, xrRazom events (2026-10-21, all passed):

1. Mode off writes nothing.
2. A, solo, empty profile: after 3 s the character is adopted; the quest item is left out; weapon slot, magazine, ammo type and upgrade stored; skills and recipes stored.
3. A: an item taken is written 1 s later.
4. A: loading an older save: 5 items kept, the save's extra PDA released, the missing bread created, the medkit's uses, money, skills (bonuses recomputed) and a forgotten recipe set back, rifle in slot 3, outfit in 7, artefact on the belt, the quest item untouched.
5. A created weapon gets its upgrades (installed, not from the packet), magazine and ammo type, and goes to its slot.
6. Level change: no restore.
7. Death with `death_strip`: only the equipped PDA stays; no writes while dead.
8. B, host: a save with no copy for this profile gets the profile; the save holds key and profile; no writes between saves; loading that save follows it.
9. B, a save from another profile with an empty profile: adopts.
10. B, client: waits while `JoinSettling`; no key gives the profile; `pst_saved` stores a snapshot; a rejoin into that save's key restores the snapshot over what xrRazom gave.
11. Profiles: bad names, wrong confirm and `default` refused; removing keeps a backup; a shrinking write keeps `.bak1`; 40 snapshots kept; a broken file is read from `.tmp` and copied to `.bad`.
12. A profile switch in a game is refused, MCM's value goes back to the profile in use, and later writes still go to it.
13. At the main menu None is taken; `none` cannot be created; with None nothing is restored or written, and a host save gets a key but no profile.
14. Save mode switched on in a game: no restore until the next load, which restores.
The 2026-10-21 harness is gone; checks 1–14 predate the profile menu and would need it rebuilt. The menu was checked on 2026-11-11 with a smaller stub run (the build session's scratchpad `t2.lua` / `run2.js`: real Master Core text and profiles, this mod's profile, core, menu and MCM scripts, the state module faked, a fake UI that records the window's controls; all passed):

15. A new game's autosave made while arriving names no profile. The MCM page builds, with no profile list. B, host, a new game: the menu opens on arrival, Close does nothing there, None is the first row and shows the current character (bread stacked: 3 icons), the empty `default` shows none; Play adopts it, live. A save made then is recorded `default`.
16. Reloading that save: no menu, the save's character kept (B).
17. Menu key: a switch menu; "Create and play" `alt`: a copy of the character, `default` written first, the selection remembered in `persistent_stalkers_selected.txt` (nothing in MCM).
18. Switching back to `default`: the line says `alt is saved now`; `alt` written, `default`'s file applied.
19. Esc closes the switch menu; the key closes it and its release does not reopen it.
20. None: phase `none`, nothing written, a save recorded `none`, and reloading it with None selected goes straight through.
21. An older save recorded `default` while None is selected: the menu; its line says the save's own character is kept; chosen: kept, live.
22. A save recorded `alt` with `default` selected: the menu; closed by something else, it opens again; `default` chosen: its file applied (B, another profile's save).
23. A, a matching save: the profile applied without a menu.
24. Mode off: no menu, the key does nothing (a tip).
25. Client: no key yet: the menu; a host save records the key as `default` and stores a snapshot; a rejoin into that key: no menu, the snapshot applied.
26. The selection after a restart (a fresh profile module) is the last one chosen; with no selection file, MCM's old `persistent_stalkers/active` is taken (`alt`), an unknown one gives `default`; None is remembered.
27. The equipment column (2026-11-11): 273 x 566 units scaled to the 536-unit panel (258.5 wide on 16:9); the background's rect cut to 566/768 of its height; the rifle's icon turned and centred in G.A.M.M.A.'s rifle cell; an outfit with `artefact_count` 2 gives 3 belt blockers, one without helmet room the helmet blocker; grey bars for the rifle and the outfit; no plain boxes when the background is there.

## In game, to check (solo first)

1. Install (`tools\install.ps1`), start with `-dbg`, MCM → Persistent Stalkers → Save mode: Character lives in the profile, Apply. Log: after 3 s `a new profile takes the character as it is`, `default written (revision 1, N items …)`. `D:\Anomaly\appdata\persistent_stalkers_profile_default.txt` exists. `status()`.
2. Pick up, drop, use a medkit, buy something: each shows `written` within about a second.
3. Save, change the inventory a lot (drop half, take other things), wait 5 s, load the save: `making the character match default`, `applied: …`, and the inventory, slots, belt, active weapon, money, hunger/thirst/sleep, faction goodwill, and skill levels are as before the load. Health, bleeding, body parts, radiation and psy health are the save's (`health … and N wounds kept from the loaded character`). Check an upgraded weapon (upgrades, scope, magazine and ammo type), a half-used medkit, a part-worn weapon (`parts`), an artefact on the belt. The log line `goodwill set:` names each faction whose number changed.
4. Bleed hard, die, reload the last save: the character comes back with the save's health and bleeding, not the health from just before death. A save made while healthy does not bleed out on load.
5. Recipes: learn one, wait, load an older save: it is known again.
5a. Skill tree (A): buy a perk, earn XP (finish a task), wait, load an older save: `skill tree set: class …, N perks, N general XP`, and the Skill tree window shows the perk and the XP. Switch to a profile with another class in the profile menu: the class and its perks change. With Skill tree disabled in MO2, play and let the profile write: the file still holds `skill_tree`.
6. Level change through a transition: `level change: the character carries on`, no restore.
7. Save mode: switch to Character follows the save, save, change things, load: `the character follows it`, nothing restored. Then a save made with another profile: the profile is applied.
8. Co-op, client in A: join a host. Log: arrival waits for `JoinSettling`, then `applied`. Check that the host sees the client's gear (the created items) and that nothing doubled after a host save and a rejoin. A `could not release` line names a host-owned item.
9. Co-op, client in B: host saves (`snapshot for save <key>` on the client), the client changes things, the host loads that save, the client rejoins: `the copy kept for save <key>`.
10. Co-op: a host map change. Does the client log `level change` (does `on_level_changing` fire there)?
11. MCM, at the main menu and in a game: no profile list; status, create and remove work. After a restart the menu preselects the profile chosen last (an existing install keeps its old MCM choice).
12. **The profile menu** (Save mode: Character follows the save). Start a new game: after about 3 s `asking`, the menu opens and cannot be closed. Look at it, and send a screenshot: the rows, the stats, the equipment column next to the real inventory's (same background, same cells, pistol and rifle turned the same way, blockers matching the outfit; no `background could not be cut` line in the log), the backpack grid (icons the right shape, not stretched; stacks with `xN`; condition bars), the item card on hover (or a `no item card` line in the log). Choose `default`: `a new profile takes the character as it is`, `default written`.
13. Save, die (or change things), reload: no menu, the save's character. `status()`: `played with default`.
14. F8: the switch menu. Type a name, "Create and play": a copy, `default written` first. F8, choose `default`: `<new> written`, then `making the character match default`. F8 closes it again; Esc too.
15. F8, None: `no profile`; save; reload: no menu, nothing written. Load an older save made with `default`: the menu, with `default` chosen.
16. MCM → "Open the profile menu": it opens once MCM is closed. MCM "Pause the game…" on: does the menu still react, and does the game unpause after? (If it freezes, turn it off.)
17. Co-op client: join: the menu after xrRazom's restore; choose; host saves; rejoin: no menu.

## Open

- **A's reload duplication** (accepted): pick up, reload, it is there again. C (the ledger) if it matters.
- **Radiation setter** semantics, and whether `change_satiety` exists on this exe (`pcall`ed; logged nothing if it fails). `vital()` still puts the save's radiation back onto the profile's gear.
- **Addons on a client-created weapon**: the packet route only runs on the host and in solo; silencers and launchers are attached as items instead (untested in game, including whether a client's attach reaches the host). Detachable scopes are not: in G.A.M.M.A. they are mostly their own weapon sections (the probe's "scope attached by hand" was kept by every method).
- **Hardlinks**: an edit that replaces a repo file breaks its link into `D:\GAMMA\mods` (2026-10-28: the game ran the 2026-10-22 state script). Rerun `tools\install.ps1` after edits.
- **Faction** in co-op: xrRazom may set it back. Off by default.
- **The profile menu is unverified in game**: the window's look and layout, `InitEditBox`, `IsCursorOverWindow` on the icons (on a turned icon it tests the unturned rectangle), the background cut (`SetTextureRect` on a texture-description id taking file pixels), `SetHeading` turning about the window's centre, the outfit fields read through `ini_sys` (`helmet_avaliable`, `backpack_avaliable`, upgrade property sections' `artefact_count`), G.A.M.M.A.'s `UIInfoItem` driven by a section, icons from `icons_texture` (GAMMA's overrides), `utils_xml.screen_ratio`, `device():pause` while a script window is open (MCM `pause_menu`, off by default), a key `on_key_release` while xrRazom is connected, MCM `key_bind` returning the DIK code. Second pass: scopes and silencers drawn on weapon icons.
- **Arrival menu in a live world**: without the pause, the world runs while the player chooses (3 s after the load). If that is a problem in play, the pause or making the choice before the settle are the options.
- **Room info** from Private Backrooms could become one section of the character (its `room_info` / `set_room_info`); not done.

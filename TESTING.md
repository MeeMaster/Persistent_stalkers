# Testing Persistent Stalkers

The mod's console commands and debug keys, grouped by what they test.

## Before you start

- Start the game with `-dbg` (debug mode). Without it, `run_string` and the debug keys do nothing.
- Type each command into the console (`~`) as shown, including `run_string`.
- Output goes to the log (`D:\Anomaly\appdata\logs`); `status()` also shows it as tips on screen. Every line starts with `[PersistentStalkers]`, and a line with `!` after the tag is a problem.
- Commands that return a value print nothing. To see the result, wrap them in `printf`, as shown below.

## Profile

### In a game

| Command | What it does |
|---|---|
| `run_string persistent_stalkers.status()` | Prints the mode (constant saves or not), the profile and its revision, the phase (`idle`, `waiting`, `applying`, `live`, `none`, `dead`), host or client, the save key, the world, what the loaded save was played with, the snapshot count, the profile file, and the stored and carried character on one line each. |
| `run_string persistent_stalkers.write()` | Writes the profile from the actor now. Only works when the phase is `live`; it does nothing in the lobby or with None. |
| `run_string persistent_stalkers.restore()` | Makes the actor match the profile file now: the full reconcile, as on a load. |
| `run_string persistent_stalkers.switch_to("name")` | Plays another profile without quitting. The profile in use is written first, then the new one's character replaces the actor; an empty profile takes the current character. `switch_to("none")` stops using a profile. Refused while arriving, applying, dead or in DANTE's return. |

### Profile files (main menu or game)

| Command | What it does |
|---|---|
| `run_string printf("%s %s", persistent_stalkers_profile.create_profile("name"))` | Creates an empty profile. Prints `true` or `false` and the reason. |
| `run_string printf("%s %s", persistent_stalkers_profile.remove_profile("name", "name"))` | Removes a profile; the name is typed twice to confirm. The files are kept as `….removed-<time>.txt`. Refuses `default` and the profile in use. The main menu's Remove selects `default` first; this does not. |
| `run_string printf("%s %s", persistent_stalkers_profile.set_faction("name", "dolg", false))` | Changes a profile's faction, as the lobby's Keep does. `true` instead of `false` is Reset: every goodwill becomes 0. Applied at the next arrival; the file is backed up to `.bak1` first. |
| `run_string printf("%s", persistent_stalkers_profile.selected_profile())` | The profile selected at the main menu. |

### Debug keys

| Key | Where | What it does |
|---|---|---|
| F8 | In a game | Opens the switch window: every profile, a click shows it, "Switch to" switches as `switch_to` does. F8, Esc or Close shuts it. |

## Lobby

The lobby is entered from the main menu's **Start the lobby**. These commands work while it runs, unless noted.

### State

| Command | What it does |
|---|---|
| `run_string persistent_stalkers_lobby.status()` | Logs whether the lobby is active, the level, solo/host/client, this machine's spot, the camera state, the window, Change profile, the place and its cameras, the row's and the actor's position; then the load report: callbacks isolated and failures caught, mod scripts not started, MCM settings answered from `axr_options`, whether every MCM page is gathered; then every tuning value. |

### Tuning values

`run_string persistent_stalkers_lobby.tune("key", value)` sets one value for this lobby only (it is not saved).

| Key | Default | What it does |
|---|---|---|
| `npcs` | 0 | 1 puts a stand-in stalker on each empty spot; 0 removes them. |
| `spacing` | 1.1 | Metres between spots. A place's own `spacing` line, when it has one, replaces the default. |
| `side` | 1 | -1 mirrors the row (use it if the host shows up on the wrong side). |
| `face` | 0 | Radians added to the bodies' heading. |
| `cam_mode` | 2 | The engine camera for free look (used only when the place has no camera): 0 first person, 1 third person, 2 free look, 3 another. |
| `drift` | 0.25 | Metres off its spot before an actor is put back. |

`run_string persistent_stalkers_lobby.stop()` stops the lobby: camera, HUD and input back.

Shortcuts: `run_string persistent_stalkers_lobby.turn()` turns every body half round. `run_string persistent_stalkers_lobby.cam(3)` aims again with camera mode 3.

### Recording the camera

Fly the free camera (`demo_record`) to the view you want, then:

| Command | What it records into the place |
|---|---|
| `run_string persistent_stalkers_lobby.snapshot()` | The lineup camera (`camera`). |
| `run_string persistent_stalkers_lobby.snapshot("close")` | The Change profile close-up for every spot (`close`), framed on this machine's spot. |
| `run_string persistent_stalkers_lobby.snapshot("close", 3)` | Spot 3's own close-up (`close_3`). |

The lobby uses the new pose on the next update. The file is `gamedata\configs\mod_system_persistent_stalkers.ltx`.

### Places

`persistent_stalkers_place` works in any game, not only the lobby.

| Command | What it does |
|---|---|
| `run_string persistent_stalkers_place.here()` | Logs the map, your position and the way you face, and a ready place line with you as the host. |
| `run_string persistent_stalkers_place.add("name")` | Writes a place where you stand, facing where the camera should be, copies the selected place's cameras, and selects it. |
| `run_string persistent_stalkers_place.choose("name")` | Selects a place from the config (the same as editing `place =` in `[persistent_stalkers_lobby]`). The next lobby goes there, unless `random = 1`. |

With `random = 1` in `[persistent_stalkers_lobby]` (the default), each lobby picks one of the places at random (never one on `fake_start`) and logs `random place: <name>`; `place =` is then ignored. Set `random = 0` to always use `place =`, which you need when recording cameras or hand tuning a particular place.

One spawn serves every place. A place on another map than the spawn's start takes a level change before the lobby starts (the log says `place <name> is on <map>: changing level`), so it loads a bit longer. The engine saves `<name> - autosave` for every level change; the lobby sets your autosave aside first and puts it back on arrival (log: `the autosave set aside for the level change`, then `the level change's autosave: the lobby's deleted (…), yours back (…)`). `tools/build_lobby_spawn.sh` is needed only after a modpack update changes `all.spawn`; build it for the place you use most to skip that second load.

### Hand tuning the place

Each change logs the place as config lines; `(not saved: save_place())` means it is not written yet. Distances are in metres, angles in degrees; right, up and away are as the camera sees them.

| Command | What it moves |
|---|---|
| `run_string persistent_stalkers_lobby_tune.where()` | Nothing: logs the place as it is now. |
| `run_string persistent_stalkers_lobby_tune.host_move(right, up, away)` | The host's spot; the other spots and the cameras follow. |
| `run_string persistent_stalkers_lobby_tune.host_turn(deg)` | The row's facing (positive turns right). |
| `run_string persistent_stalkers_lobby_tune.cam_move(right, up, away)` | The lineup camera. |
| `run_string persistent_stalkers_lobby_tune.cam_turn(yaw, pitch)` | The lineup camera's aim. |
| `run_string persistent_stalkers_lobby_tune.close_move(right, up, away)` | This machine's close-up (open Change profile to see it). |
| `run_string persistent_stalkers_lobby_tune.close_turn(yaw, pitch)` | This machine's close-up's aim. |
| `run_string persistent_stalkers_lobby_tune.set_spacing(m)` | The space between spots at this place. |
| `run_string persistent_stalkers_lobby_tune.save_place()` | Writes the position, rotation, cameras and spacing into the place's own section. The actor is moved onto the host spot when the lobby starts. |

Unsaved changes are gone when the lobby stops.

### Debug keys in the lobby window

F7 turns hand tuning on and off. While it is on:

| Key | What it does |
|---|---|
| Arrows | Move left/right and away/toward. |
| Page Up / Page Down | Move up and down. |
| Q / E | Turn. |
| R / F | Tilt (cameras only). |
| [ / ] | Spacing. |
| - / = | The step: 0.01 to 1 m, ten times that in degrees. |
| Tab | The target: host, camera, close-up. |
| Enter | Save (as `save_place()`). |
| F7 | Off. |

The hint line shows the keys and the current target.

## Development

| Command | What it does |
|---|---|
| `run_string persistent_stalkers_dev.reload()` | Re-reads the profile, state and core scripts from the repo (`D:\Code\Stalker mods\Persistent_stalkers\gamedata\scripts\`), keeping their state. The main menu, its panel and the lobby scripts need a game restart. Refused while a restore is running. |

The offline checks run without the game: in `tools\check`, `npm i fengari` once, then `node run.js`.

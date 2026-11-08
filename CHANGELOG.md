# Changelog

All notable changes to this project are documented in this file.

## [Unreleased]

### Added
- On-screen controls rebuilt after the NTSD Android proposal and PPSSPP: the d-pad is one control (a cross of four arrow icons; a corner holds two directions) and attack, jump and defend are icons too, the F button, SET and the show/hide button too, all from the images under `scripts/base/onscreen` (32-bit BMP with alpha). The show/hide button hangs from the very top of the window and only slides left and right. Every control has its own place, size and opacity, from 0 (invisible, still working) to 10: the d-pad, attack, jump, defend, the F button (F1-F9 grid beside it, it follows the button), the button at the top centre that shows or hides the controls, and SET at the top right. SET opens the editor: drag a control to move it, choose its size and opacity, give it a keyboard key (the d-pad one per arrow), RESET and DONE. The settings are saved in config.json (`onscreen`). A finger that starts on a control never reaches the page behind it (no click-through, the pointer does not move there). The floating stick, the digipad, the chord buttons and the pause and fast-forward buttons of the old gamepad are gone (F1 and F5 of the grid replace the last two)
- New frame command `icon` (`context.icon(resource, x, y, w, h, alpha, tint)`): a whole image stretched to a size with an alpha (0-255) and a tint, smoothly scaled; images under `mods/` keep their alpha channel (`SpriteCommand::dest_width/dest_height/alpha`)
- LF2 Darkfiren background modes: `respond` filters a background's layers and `arest` its opoints. A layer or opoint is used when the chosen mode lists its value (none given = 0); a mode without the key lets everything through. The background's first mode stands when no other is chosen (also for Random and Stage). `bg.dat` `opoint:` blocks are read (up to 50); the ones the mode lets through put their object on the stage when the round begins (position, first frame, facing, team, hp, mp, blink time; join/reserve not done)
- Modes with `respond`/`arest` are choosable in the mode grid (`fall` and `wait` still are not)
- LF2 Darkfiren background modes: `hurtable` (1 friendly fire, 2 no damage with the summary box still counting it, 3 both) and `gain_mp_a`/`gain_mp_v` (percent of a hit's injury given as MP to the attacker and the victim, characters only, MP may pass 500; the MP bar is drawn clamped to its frame)

- LF2 Darkfiren's `data/mode/mode4.dat` now sets the positions of the wide character menu: the menu picture and slot grid (`<menu_control>`), the fighter roster (`<grid_char>`), the background grid (`<grid_bg>`) and the background mode grid (`<grid_bg_mode>`). A value the file lacks keeps the built-in one; the COM label on the roster follows the file's `com_x` (7) instead of the human's 12

- LF2 Darkfiren Stage mode: `data/stage.dat` as a level list (`<stage_information>`), each level's file read as stages numbered level id * 10 + stage id (up to 200 stages). A stage plays on its own `bg:`; `when_clear_goto_stage` jumps to another stage, `end: 1` shows the credits, `end: 2` returns to the menu, and without `end:` the next visible level follows. The Background row of the menu opens a level grid (`<grid_stage>` of mode4.dat) with the levels' `small` pictures. `team:` (-1 independent, 1 to 5; not for prisoners), `pic:` (skin offset), `mp:`, `z:` and `fx:` (fixed position, without the random draw) of a stage object work. Read but not used yet: phase `time:`, `type:`/`ptype:`/`next:`/`mode:`/`respond:`/`hex:`, `command:`, the lock values of `hidden:`

- LF2 Darkfiren time limit (`<time>` of mode4.dat): the wide options menu gets a Time limit row (Off, then the listed times). When the time is up the round ends at once, the fighters lose control, and the winner follows the list's `type` (1 highest hp, 2 highest dhp, 3 most damage, 4 most kills; a tie has no winner). The time left is drawn under the HP frames. Not in Stage mode; a match with a time limit is not recorded and is not played over the network

- LF2 Darkfiren cost mode (`<cost>` of mode4.dat): the wide options menu gets a Cost pool row (Off, then 200 to 9999). Every team has one pool; a beaten fighter costs its price (`kind:`, or the `cost:` groups) and comes back at once while the pool is above 0, with hp and mp cut down when the rest does not cover its price; at 0 the team is out and the other team wins. The pools are drawn under the clock; with a time limit the team with more cost left wins. Not in Stage mode; a match with a cost pool is not recorded and not played over the network. Respawning as another fighter of the `random:` list is not done

- LF2 Darkfiren Beat the Clock (Time Battle): a stage phase's `time:` is the seconds to beat it in. The clock runs while the phase's enemies are on the stage and is drawn under the HP frames; at 0 the stage is lost and the fighters stand without control

- LF2 Darkfiren `<misc>` of mode4.dat in the wide menu: the music line takes its position (`music_x/y`) and colours (`hexf`, `hexb`) from the file, and with `background_small: 1` the chosen background's small map picture is drawn in its frame (`frame_x/y`, `small_x/y`, `pic`). Random, Lee On Road and Stage mode show none

- LF2 Darkfiren `<battle>` of mode4.dat: in the wide layout the nine soldiers of Battle mode (troop picker order) come from the file's nine `id:` lines (30 31 33 34 39 32 35 36 37 as shipped); a soldier whose id the original does not know gets 500 hp. A file without exactly nine ids, or the classic layout, keeps the built-in soldiers

- LF2 Darkfiren More options (`<menu_small>` layers 8 to 10) in the wide options menu, under Time limit and Cost pool: **Item drops** (off: no random weapon drops, no F8 fill), **Transform** (off: Louis stays Louis at state 9995) and **Respawn shuffle** (with a cost pool: a fighter chosen with Random comes back as another id of the `<cost>` `random:` list, not its own and, if possible, not one a living fighter has). A match with any of them changed is not recorded and not played over the network. **TU mode** (every mode of the wide layout): 2tu (default) reads the keys every second time unit like the original, 1tu every one, for smoother input; a 1tu match is not recorded and not played over the network

- LF2 Darkfiren's options panel (`<menu_small>` of mode4.dat) in the wide menu, with its own pictures: rows `b1` to `b12` stacked from (3,3), the selected one lit by `n1` to `n12`, values written into the boxes (background, difficulty, bg mode, time limit, cost pool and its check marks, TU mode). Layers follow their `hidden` (1 to 3 need the cheat code, 4 never) and `mode:` tags; Bg Mode and Time Limit show their disabled pictures where they do not apply. Reset Random: jump closes the eye and hides what Random gave until the match. The cost row: attack changes the pool, jump turns Respawn shuffle on or off. The More options row (layer 10: drop, transform, shuffle) shows when its `hidden` is 0. Without the pictures the classic panel stays

- LF2 Darkfiren input tags: hit_f/hit_b/hit_uz/hit_dz and hold_a/d/j/f/b/uz/dz (computer fighters never hold), hit_Faj/Uaj/Daj as the jump-key sequences' fallback.
- LF2 Darkfiren frame effects: dx/dy/dz direct movement, hp/chp/cmp, caught, hit_g landing frame and next 13XX random jumps.
- LF2 Darkfiren flow states 80/81/82, 121-139, 62-66, 85/86, 20/21, 150-159, 364X, 4xxx, 17xxx, 404 and 405.

- LF2 Darkfiren: raised the object slot capacity from 400 to 1000 and spawn up to 20 opoints per frame.
- LF2 Darkfiren: itr tags dvz, drain, gain (17xxx heals HP), recover, dbdefend 1-4 and spark (-1 / image set index).

- UI: layout baru "wide 1018" (mode2.dat); pemilihan berkas mode dan lebar dari `data/mode/mode.dat` (`game/ui_modes.lua`).
- UI: HUD membaca gaya dari `data/frame.dat` (`game/ui_hud.lua`); bar dan flag per objek dari `record.display` bila ada.
- UI: tag frame `shadow`, `bound`, `amount`/`loop`, `center_z` dan state tak terlihat (`value.st.invisible`) digambar oleh `match_screen`.

- LF2 Darkfiren: generic `game/dat_text/<path>` and `game/mode_file/<k>` resources give scripts the decrypted text of data files.
- LF2 Darkfiren: system.dat lists and settings (`system_data`), hidden/unlock rules with saves keys (`unlock.allows`).
- LF2 Darkfiren: bgm.dat track list (hidden, boss, hex, mode, respond) and sound.dat sound list.
- LF2 Darkfiren: kind.dat, fusion.dat and stage damage modifier files parsed (`sd_global`).
- LF2 Darkfiren: background mode tags width, zboundary and dvy take effect; centery and attacking are exposed as `state.bg_area`.

- LF2 Darkfiren: `hold_*` frame tags now count the key held down (about 2 seconds) across frame changes instead of inside one frame.
- LF2 Darkfiren: `hit_g` and `9xxx` landing frames also work when the previous height was less than one unit above the ground.
- LF2 Darkfiren: a fighter whose lives were set by a `4xxx` frame blinks out and gets up again, using one life, when beaten.
- LF2 Darkfiren: `6XXX` charge frames forget a key tapped right after entering and wait for the key to be pressed and held.
- LF2 Darkfiren: `5XXYY` earthquake axes written `00` do not move (so `55200` shakes along x only).

- LF2 Darkfiren: bdy kinds 1xxx / 2xxx / 1xxyyyzzzw now also work in stage mode on ordinary objects (only the criminal keeps its protection).

- UI: layout "wide 1018" kini jalan di game nyata: berkas mode game dibaca dan didekode di Lua (`game/data_text.lua`), dengan salinan bawaan (`game/mode2_builtin.lua`) dan catatan di layar bila dipakai.
- UI: gempa layar (state 5XXYY) menggeser arena di `match_screen`; `center_z` mengikuti aturan Darkfiren (z + center_z - 20000).
- UI: judul mode digambar di layar pilih karakter (layout lebar); gaya HUD bisa dipilih di Opsi (`hud_style`).

- UI: gaya HUD yang dibuat khusus untuk satu lebar (mis. Widescreen_Radar, 1018) tidak lagi digeser ke tengah, sehingga kotak HUD tidak tertimpa radar.

- LF2 Darkfiren: itr reach on the x axis raised from 1000 to 10000.
- LF2 Darkfiren: time stop objects neither attack nor are attacked; a background mode's `attacking` scales hit damage and `centery` sets the height of random weapon drops.
- LF2 Darkfiren: per-object statistics fx.killed_by, fx.last_killer, fx.combo and fx.combo_age; lethal poison counts as a kill.

- UI: lebar jendela pertandingan (`background.set_window_width`) diatur dari layout tiap pertandingan dibuat; kunci buka stage diberikan di akhir stage; pilihan tim mengikuti `constants.teams.enemies`; radar memakai gambar hidden/clone/heal; mode background width, zboundary, dvy, centery ditandai didukung.

- LF2 Darkfiren: characters made by an opoint with the creator's own record id are marked as clones (fx.clone, fx.clone_owner).
- LF2 Darkfiren: the user of a time stop can hit frozen objects; frozen objects never attack.
- LF2 Darkfiren: combo rules (respond, caughtact, effect) read from mode.dat <combo>; kills made while catching are recorded; mimic keeps who applied it (fx.status.mimic_by).
- LF2 Darkfiren: victim states 70 / 75 defend from both sides; states 601 / 602 / 603 keep the victim out of the injured / falling frames; system.dat <henry_arrow> and <john_biscuit> lists; sound calls pass the object id.

- UI: `hidden:` pada mode, level stage, panel kecil, dan gaya HUD dinilai per entri lewat `unlock.allows`; minibar karakter (`<minibar>`) digambar di bawah karakter; mode background `attacking` ditandai didukung.

- AI 2: paket uji ponsel R7 (karakter uji AI2STAT, `PANDUAN_UJI_R7.md`) dan tes otomatis `st_testpack_r7_test`; tidak ada perubahan perilaku permainan.

- LF2 Darkfiren: `ppoint` makes an object follow its owner at an offset (x, y, z).
- LF2 Darkfiren: extended `cpoint` (daction/faction/baction/uzaction/dzaction while holding, `z`, drain/gain/recover) and itr `respond` as holding time for catch itrs.

- LF2 Darkfiren: `platform.plane_at` for itr kind 30-89 platforms (landing plane for kind X0; physics.lua must call it).

- AI 2: platform (itr kind 30-89, tahap 1 = X0): `physics.lua` memakai `platform.plane_at` sebagai bidang pendaratan (`value.floor_y`); pemeriksaan "di tanah" di control/animation/frame_rules/st_frame/ai/camera/match ikut. Tanpa platform perilaku identik. Tes baru `st_platform_test`.

- AI 2: `physics.lua` memakai parameter `current` dari `platform.plane_at` (rise_limit milik AI 3); trik kaki diturunkan 24 dibuang. Tanpa perubahan perilaku.

- LF2 Darkfiren: catching itr (kind 1) frames per side (catchingact/caughtact left, pickingact/pickedact right, negative = turn around); fixes a crash on negative frames.

### Changed
- The background layer limit is 1000 as in LF2 Darkfiren (was 30; Forbidden Tower has 37 layers and failed to load)

## [1.1.1] - 2026-10-18

### Added
- A fast-forward button in the top left corner of the on-screen gamepad, like the pause button on the right (it is F5)
- Escape or the back button during a fight asks "Leave the fight?" (a dialog like the exit question) and leaves like F4 on confirmation

### Changed
- Fast-forward always overlaps the simulation with rendering, whatever the draw time

### Fixed
- Typing into text fields (names, recording info, network address) on Android and iOS: Backspace and Enter taps of the soft keyboard are no longer lost, and typed characters keep their case
- Android: coming back to the app no longer leaves a black screen: the renderer is opened anew once the window surface is back (also after a lost graphics device on other platforms)

## [1.1.0] - 2026-10-17

### Added
- Windows installer (Inno Setup, English, German, Chinese) replaces the zip: optional download of the original game installer, `.lfr` file type registration, Start menu entry and uninstaller
- Language option (default, english, chinese, german): translated text is drawn with bundled TrueType fonts through SDL3_ttf, rendered once per text and cached; the default language keeps the bitmap font
- Font antialiasing option, shown when a translated language is selected
- Translation system for scripts (`i18n.tr`, one module per language) and a text draw command for the host
- Translated languages also replace the text baked into the original's menu bitmaps; `english` shows only the English part of the original's bilingual strings
- The open-file dialog for recordings, the desktop entry, the AppStream metadata and the MIME type description are translated (German, Traditional Chinese)
- Alt+Enter switches between fullscreen and window at any time (also in the setup dialogs), without any other action

### Changed
- The summary screen ends with a fresh attack or jump press of any player or a controller's south button, like the demo, so it also works in replays
- A window that leaves the maximized or fullscreen state returns to the original resolution instead of its previous size
- Without `--renderer`, xBRZ upscaling is looked for in the SDL_GPU renderer, then in OpenGL, before settling for the system's default renderer, so it is offered on Windows machines whose GPU renderer cannot run it
- Automatically overlap live simulation with rendering when the frame budget is exceeded, returning to current-frame rendering when there is enough headroom; fall back to synchronous execution when threads are unavailable
- Reduced Lua/C++ frame overhead by sending drawing, audio and control commands in one typed opcode batch
- Reduced sound scaling work with a bounded cache of volume/pan variants and faster sample rounding

## [1.0.0] - 2026-10-17

### Added
- Drag and drop `.lfr` recordings onto the launch or title menu to play them
- Open `.lfr` recordings directly from the command line or Linux file managers, with file type registration; F4 or leaving the result screen closes the application when opened this way
- Support for the alternative `lf2_v20a_Setup.exe` installer in native and browser builds, with SHA-256 verification and automatic discovery in the configuration directory
- Exit confirmation on Escape or Android's back button, controllable with keyboard, gamepad, mouse and touch
- Links to the original authors' sites in the launch menu credits
- HP bar flash while healing and remaining-lives labels above enemies, as in the original
- Demo can be ended at any time with attack from any controller or the on-screen controls

### Changed
- Reduced simulation work in crowded fights by skipping impossible collision pairs while preserving hit order and cooldown timing
- Reduced sound playback processing by reusing scaled audio buffers and bypassing scaling when no volume or pan adjustment is needed
- The expanded battlefield scrolls a window of the full screen width across the stage or the open stage section, so the stage edge is the screen edge; backgrounds continue past their pictures without scaling
- Web build uses SDL 3.4 and follows the screen size when entering fullscreen or rotating a phone
- Credits are shown on four lines
- Text colours of the scoreboard, stage and battle status lines, recording and volume messages, battle setup and control settings match the original; battle strategy lines use the team fonts

### Fixed
- Letterbox bars painted black over the picture's colours and the on-screen controls on the web
- Team order markers drawn away from the player in the expanded battlefield
- Status and text under bosses and the Stage mode scoreboard result

## [0.9.4] - 2026-10-12

### Added
- Subtle version and Git revision label on the launch menu

### Changed
- Reduced CPU work and allocations in battle simulation, collision detection, AI and rendering snapshots

### Fixed
- Weapon targeting after its holder is removed, preserving original replay behavior
- Julian and Firzen MP regeneration when HP is negative
- Stage reserve lives for recruited allies when all players are defeated
- Projectiles and effects drawing outside the battlefield

## [0.9.3] - 2026-10-11

### Added
- Optional expanded battlefield layout with support for parallax backgrounds
- Desktop window size, position and maximized state are saved and restored before showing the window; Wayland controls positioning

### Changed
- Semi-transparent on-screen controls, with no overlapping diagonal highlights on the digipad
- Options menu adjusts its layout to the available settings
- High-density rendering enabled across platforms
- Updated credits, website links and development notice
- TLS certificate verification disabled for installer downloads; installer SHA-256 verification remains enabled

### Fixed
- Keyboard and gamepad access to website links and the recording folder
- Recording help and special move links
- iOS pause button in widescreen, info bar and application exit
- Template background loading with incomplete BMP palettes
- Compiler signedness warnings; compiler warnings are now treated as errors

## [0.9.2] - 2026-10-10

### Fixed
- Black sprites with the OpenGL ES renderer
- On-screen gamepad is now also hidden when mouse force mode is active
- Launch script for ROCKNIX

## [0.9.1] - 2026-10-02

### Added
- On-screen gamepad (digipad): configurable, drawn as an overlay (also in the letterboxed area), enabled by default and larger
- On-screen special buttons and a pause button
- Touch tolerance for on-screen controls
- Support for multiple screen orientations
- Flatpak packaging
- Portmaster build

### Changed
- Linear filter is now the default (and fixed)
- All options are now shown in the config

## [0.9.0] - 2026-09-28

- Initial release
- LF2 Darkfiren: itr kinds 17 and 18, kind 14 respond 1-7; bdy zwidth, kinds 1xxx/2xxx/50-55 and 1xxyyyzzzw, weapon pickup respond.
- LF2 Darkfiren: opoint hp/team/z/mp/dvz/effect/centerx/centery/centerz/framea/reserve/attacking/pic, holding kinds 3/5/6/7 and wpoint cover 2.
- LF2 Darkfiren: itr status effects poison, manacle, delay, confus, weak, join, mimic, bound and facing (kind 0 and 9 only).
- LF2 Darkfiren: the blast and ground fires of `hit_Fa` 26 are placed on the ground even when the exploding object is in the air.
- LF2 Darkfiren: the Radar HUD style now draws the radar (base picture, one dot per object, blinking, camera frame) from the frame file's `<radar>` block.
- UI: HUD styles made for one specific width (e.g. Widescreen_Radar, 1018) are no longer shifted to the centre, so the HUD boxes are not covered by the radar.
- LF2 Darkfiren: `background.switch` and `switch_state` (states 9XX, 9XXYY, 7XX, 7XXYY) exist for background changing, and at most 20 sounds play per flush.
- LF2 Darkfiren: itr reach on the x axis raised from 1000 to 10000.
- LF2 Darkfiren: time stop objects neither attack nor are attacked; a background mode's `attacking` scales hit damage and `centery` sets the height of random weapon drops.
- LF2 Darkfiren: per-object statistics fx.killed_by, fx.last_killer, fx.combo and fx.combo_age; lethal poison counts as a kill.
- LF2 Darkfiren: weapon `<sound>` blocks are read one entry per `bound:` block (up to 100), with `bg:` and `mode:` as sets.
- LF2 Darkfiren: background mode tag `width: -1` uses the window width; mode areas also carry dicontrol, start_frame, reserve, dx, dvx, dz and dvz.
- LF2 Darkfiren: finishing a stage can unlock the next stage or level (respond key); the combo settings are read from `mode1.dat`.
- LF2 Darkfiren: sounds of items and effects outside the screen are still heard, played at the edge of the hearing area.
- LF2 Darkfiren: `sounds.weapon_path` picks a weapon sound per background and mode from the weapon `<sound>` blocks, falling back to the weapon default sound.
- UI: the match window width follows the layout, a stage's unlock key is granted when the stage ends, team choices follow the number of enemy teams, and the radar shows hidden, clone and healing marks.
- LF2 Darkfiren: background `state:` layers and `transparency: -1` paths are read; background modes can carry the team HP bar and quest settings (new module `sd_quest`).
- LF2 Darkfiren: characters made by an opoint with the creator's own record id are marked as clones (fx.clone, fx.clone_owner).
- LF2 Darkfiren: the user of a time stop can hit frozen objects; frozen objects never attack.
- LF2 Darkfiren: combo rules (respond, caughtact, effect) read from mode.dat <combo>; kills made while catching are recorded; mimic keeps who applied it (fx.status.mimic_by).
- LF2 Darkfiren: victim states 70 / 75 defend from both sides; states 601 / 602 / 603 keep the victim out of the injured / falling frames; system.dat <henry_arrow> and <john_biscuit> lists; sound calls pass the object id.
- LF2 Darkfiren: Darkfiren stages get a random stage id, and the stage unlock key is corrected.
- LF2 Darkfiren: the stage enemies are team 6 and team 5 is a normal team; ten player slots (0-9, computers picked at the menu at slot + 10).
- LF2 Darkfiren: `<stats>` caught, recmp, regen_hp, regen_dhp, regen_mp and reserve of a character's own data file now act.
- LF2 Darkfiren: itr status effects manacle, bound, facing, weak, confus and mimic now act on the control, mp and recovery code.
- LF2 Darkfiren: a player fighter takes its skin, start frame, reserve and start position (dx, dvx, dz, dvz) from its data and the background mode; the mode's centery sets the drop height of revived fighters and falling weapons.
- LF2 Darkfiren: `fx.reserve` of an opoint sets a fighter's lives; `fx.clone` marks clones (state 21); id_no_blink and the pdk control (dicontrol) are read from the data; the camera view width follows the layout (1333/1018).
- LF2 Darkfiren: stage tags `join_pic:`, `<protect>` and `max:` are read; a protected object dying ends the game at once.
- UI: `hidden:` of modes, stage levels, small panels and HUD styles is judged per entry through `unlock.allows`; character minibars (`<minibar>`) are drawn under the fighters; background mode `attacking` is marked as supported.
- LF2 Darkfiren: data-driven <armor> (types 0-4, ratio, decrease, mp, hp, recover, action, delay, spark, sounds, system.dat armor_s and defend lists); characters without it keep the original armor.
- LF2 Darkfiren: weapon strikes use the new <weapon_strength_list> keys (drain, gain, recover, dbdefend, spark, dvz, selfinjury).
- LF2 Darkfiren: the window title follows `name:` of `system.dat` (a no-op where the platform has no title bar), and the cheat words come from `cheat1:` and `cheat2:` of `system.dat` (defaults LF2.NET and HEROFIGHTER.COM).
- UI: the D key on the character select screen cycles the fighter skin (`options.slots[slot].skin`), and the face and small HUD face follow the skin.
- LF2 Darkfiren: background modes read `shadow` and `shadowsize`, and the frame interval comes from `fps_value` and `fps_value_f5` of `system.dat` (a 0 keeps the original value).
- LF2 Darkfiren: `ppoint` makes an object follow its owner at an offset (x, y, z).
- LF2 Darkfiren: extended `cpoint` (daction/faction/baction/uzaction/dzaction while holding, `z`, drain/gain/recover) and itr `respond` as holding time for catch itrs.
- UI: a combo counter ("N hit") is drawn above the attacker, read from the `<combo>` block of the mode file and `fx.combo`.
- Battle mode: the squad fall height uses the mode tag `centery` (below 0) when present; without the tag it stays -300.
- LF2 Darkfiren: itr kind 30-89 platforms (stage 1, kind X0) act as a landing plane through `platform.plane_at`, and every "on the ground" check follows that plane; without platforms nothing changes.
- LF2 Darkfiren: itr `catchingact:` and `caughtact:` read one or two numbers (LF2 2.0a writes two), and a platform keeps carrying an item standing on it when the platform rises (`physics.lua`).
- LF2 Darkfiren: combat and chase/projectile code treat the platform plane (`value.floor_y`) as the ground, and an item that starts on the ground with a `start_frame` keeps that frame instead of being replaced by the landing frame.
- LF2 Darkfiren: catching itr (kind 1) frames per side (catchingact/caughtact left, pickingact/pickedact right, negative = turn around); fixes a crash on negative frames.
- LF2 Darkfiren: team HP bars and background quests are filtered by the mode tags `wait` and `fall` (not `respond`), and a rising platform carries an item standing on it via `platform.plane_at(match, value, current)`.
- UI: the battle viewport takes the height of a taller background (`background.view_height`, at most 1000), so the whole picture and the floor are visible; the platform scales it to the window.
- LF2 Darkfiren: absolute-block platforms (itr kind X1, e.g. floor.dat frame 350 kind 31/61) push items out of the block box (`st_block.lua`).
- LF2 Darkfiren: itr bounce (`dx/dy/dz`) and per-side `pickingact`/`pickedact` for kind 1 catches.

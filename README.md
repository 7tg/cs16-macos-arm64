# CS 1.6 on Apple Silicon (native arm64)

[![Build DMG](https://github.com/7tg/cs16-macos-arm64/actions/workflows/build-dmg.yml/badge.svg)](https://github.com/7tg/cs16-macos-arm64/actions/workflows/build-dmg.yml)

Counter-Strike 1.6 running natively on M-series Macs, without Rosetta or Wine, via
[Xash3D FWGS](https://github.com/FWGS/xash3d-fwgs) (engine) + [CS16Client](https://github.com/Velaron/cs16-client)
(reverse-engineered client, ReGameDLL server code, YaPB bots).

Download **`CS16.dmg`** from [Releases](../../releases). It contains the engine, client and libraries, but **no Valve
game files**: you need your own copy of Counter-Strike. It needs macOS 15+ on Apple Silicon, with no Homebrew needed.

## Install
1. Open the DMG and drag **CS 1.6** to Applications.
2. First launch: **System Settings → Privacy & Security → Open Anyway** (the app is ad-hoc signed).
3. **Game files are imported once, on first launch.** You can provide them in either of two ways:
   - **Steam on this Mac:** install **Counter-Strike** in Steam. It downloads even though Steam can't run it, and
     the app finds it automatically.
   - **Any other copy:** choose a **Half-Life folder** (the one containing `valve` and `cstrike`) when the app asks.
     It can come from a Windows PC, another Mac or a USB stick. You can also launch from the terminal with
     `CS16_GAME_DATA=/path/to/Half-Life "/Applications/CS 1.6.app/Contents/MacOS/CS16"`.

   About 900 MB is copied to `~/Library/Application Support/CS16`. Valve's own game binaries are skipped, because
   the app brings native arm64 builds. After that, Steam and the source folder aren't needed.
4. To update, replace the app with a newer one. Settings and the imported game files live outside the app and are kept.

## Defaults shipped in the DMG
First-run defaults (`Contents/Resources/first-run.cfg`) are appended to the player's initial `config.cfg`, which is
the imported one, or the bundled one in personal builds. After that the engine keeps writing the player's own
`config.cfg`, so later changes are never overridden.

| Setting | Value | Why |
|---|---|---|
| `xhair_enable` / `xhair_dynamic_scale` / `xhair_dynamic_move` | `1` / `0` / `0` | static CS16Client crosshair |
| `cl_dynamiccrosshair` | `0` | no movement spread on the classic crosshair either |
| `hud_scale` | `1280` | in-game HUD laid out for 1280 px width, scaled up on bigger screens |
| `cl_advertise_engine_in_name` | `0` | keeps the nickname free of `[Xash3D]` (needed for name-based AMXX admin) |
| `cl_updaterate` / `cl_cmdrate` / `rate` | `101` / `100` / `100000` | 100-tick servers (engine caps: 102 / 100) |
| `ex_interp` / `fps_max` | `0.01` / `200` | 200 is the engine's soft cap (above it needs `fps_override 1`) |
| `F1` | `toggleconsole` | the key left of `1` is `§` on ISO keyboards (bundled `userconfig.cfg`) |

## Repository layout
| Path | What |
|---|---|
| `make-dmg.sh` | builds `dist/CS16.dmg` from scratch (see below); `--with-game-data` for a personal build |
| `play.sh` | runs the hand-built dev tree in `xash-build/` |
| `patches/` | local fixes applied to submodules by `make-dmg.sh` |
| `src/xash3d-fwgs`, `src/cs16-client`, `src/SDL3` | submodules pinned to the built commits |
| `dist/`, `xash-build/` | build output, git-ignored |

## Building the DMG
```sh
git clone --recursive git@github.com:7tg/cs16-macos-arm64.git ~/Games/CS16
brew install cmake pkgconf freetype libpng
~/Games/CS16/make-dmg.sh                    # → dist/CS16.dmg (public, no Valve files)
~/Games/CS16/make-dmg.sh --with-game-data   # → dist/CS16-with-game-data.dmg (personal, never publish)
```
What the script does:
1. Builds SDL3, the engine (SDL3 backend) and CS16Client with `MACOSX_DEPLOYMENT_TARGET=15.0`.
   Homebrew's own SDL builds require the build host's macOS version.
2. Applies `patches/`.
3. Copies SDL3, FreeType and libpng next to the engine and relinks them with `@loader_path`. It fails if anything
   still points into `/opt/homebrew` or `/Users`.
4. Writes the app bundle with the launcher, `first-run.cfg`, `import-excludes.txt` and an icon made from
   CS16Client's artwork, so there is no Valve art.
5. With `--with-game-data` only, copies `valve/` and `cstrike/` from Steam's Half-Life folder into the app, falling
   back to `xash-build/`, and appends the defaults to the bundled `config.cfg`.
6. Ad-hoc signs the app and creates the DMG with `hdiutil`.

## How the installed app runs
- **Game files:** the engine runs **read-only from inside the app** (`XASH3D_RODIR`), along with the game data in
  personal builds. Settings, screenshots, downloads and imported game data go to `~/Library/Application Support/CS16`
  (`XASH3D_BASEDIR`), which is also the engine's working directory.
- **Import:** if neither location has `valve/halflife.wad` and `cstrike/liblist.gam`, the launcher imports them. It
  uses `$CS16_GAME_DATA`, then Steam's Half-Life folder, then a folder picker, with `rsync --ignore-existing` and the
  bundled exclude list.
- **The `filesystem_stdio` symlink:** the CS server DLL (ReGameDLL) `dlopen`s `filesystem_stdio.dylib` from the
  *working directory*. The launcher therefore symlinks it into Application Support on every start. Without it,
  starting any map crashes in `BotPhraseManager::Initialize` on a null `g_pFileSystem`.
- **Player identity:** each Mac gets its own player ID, randomly generated and stored in `~/.config/.xash_id`. On
  ReUnion servers it appears as a stable `STEAM_2:0:…`.

## Patches
- `mainui_cpp-save-added-favorites.patch`: servers added with **Add server** were created with `favorited = false`,
  which `SaveServerListToFile` skips, so they never reached `favorite_servers.lst`.

## Playing on Steam-only servers
Xash can't produce Steam auth tickets, so stock HLDS servers reject it ("Steam validation"). The companion server
runs **ReHLDS + Metamod + ReUnion** so that non-Steam clients can join, while Steam players are still authenticated
normally. ReHLDS needs the `libsteam_api.so` / `steamclient.so` from the HLDS `steam_legacy` branch, because the
HL25 build lacks `SteamGameServer_Init`.

## Limitations
- Valve's Steam-style GameUI (VGUI2) is closed-source x86 code and can't be loaded. The menu is CS16Client's
  open-source recreation.
- VAC-only servers that don't run ReUnion won't accept this client.
- Counter-Strike and Half-Life content belongs to Valve. This project distributes none of it; the player supplies it.
  Builds made with `--with-game-data` contain that content and are for personal use only.
- The engine, client and libraries are third-party open-source projects (see each submodule's license). Released
  binaries are built from the pinned submodule commits plus `patches/`.

## License
The scripts, patches and docs in this repository are licensed under the [GNU GPL v3](LICENSE). The submodules keep
their own licenses, and Counter-Strike and Half-Life content remains Valve's.

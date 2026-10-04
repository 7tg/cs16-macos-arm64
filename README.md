# CS 1.6 on Apple Silicon (native arm64)

Counter-Strike 1.6 running natively on M-series Macs, without Rosetta or Wine, via
[Xash3D FWGS](https://github.com/FWGS/xash3d-fwgs) (engine) + [CS16Client](https://github.com/Velaron/cs16-client)
(reverse-engineered client, ReGameDLL server code, YaPB bots).

The ready-to-install **`CS16.dmg`** is attached to this repo's **Releases**. It is self-contained: engine, client,
libraries and the Valve game data. It needs macOS 15+ on Apple Silicon, with no Steam or Homebrew on the target Mac.

## Install
1. Open the DMG and drag **CS 1.6** to Applications.
2. First launch: **System Settings → Privacy & Security → Open Anyway** (the app is ad-hoc signed).
3. To update, replace the app with a newer one. Settings live outside the app and are kept.

## Defaults shipped in the DMG
First-run defaults are appended to the bundled `cstrike/config.cfg`. The engine reads that file only until it writes
the player's own `config.cfg` into Application Support, so later changes are never overridden.

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
| `make-dmg.sh` | builds `dist/CS16.dmg` from scratch (see below) |
| `play.sh` | runs the hand-built dev tree in `xash-build/` |
| `patches/` | local fixes applied to submodules by `make-dmg.sh` |
| `src/xash3d-fwgs`, `src/cs16-client`, `src/SDL3` | submodules pinned to the built commits |
| `dist/`, `xash-build/` | build output, git-ignored |

## Building the DMG
```sh
git clone --recursive git@github.com:7tg/cs16-macos-arm64.git ~/Games/CS16
brew install cmake pkgconf freetype libpng
~/Games/CS16/make-dmg.sh        # → dist/CS16.dmg
```
What the script does:
1. Builds SDL3, the engine (SDL3 backend) and CS16Client with `MACOSX_DEPLOYMENT_TARGET=15.0`.
   Homebrew's own SDL builds require the build host's macOS version.
2. Applies `patches/`.
3. Copies SDL3, FreeType and libpng next to the engine and relinks them with `@loader_path`. It fails if anything
   still points into `/opt/homebrew` or `/Users`.
4. Copies the Valve data (`valve/`, `cstrike/`) from Steam's Half-Life folder. If Counter-Strike isn't installed in
   Steam, it falls back to `xash-build/`, skipping per-machine state. Valve's own x86/Windows binaries are dropped.
5. Appends the first-run defaults, writes the app bundle, ad-hoc signs it and creates the DMG with `hdiutil`.

## How the installed app runs
- **Game files:** the engine and game data run **read-only from inside the app** (`XASH3D_RODIR`). Settings,
  screenshots and downloads go to `~/Library/Application Support/CS16` (`XASH3D_BASEDIR`), which is also the
  engine's working directory.
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
- The DMG contains Valve game data from the owner's Steam copy and is for personal use only.

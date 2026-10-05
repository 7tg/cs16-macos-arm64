# AGENTS.md

Guidance for coding agents working in this repo. Read `README.md` first for what the project is.

## Build & output
- `./make-dmg.sh` is the only build entry point for the shipped app. A public build takes about a minute when the
  submodules are already built; `--with-game-data` adds a few minutes copying ~850 MB and compressing the DMG. Engine and client builds are incremental (`build-dist/` dirs inside
  each submodule).
- Output: `dist/CS16.dmg` (public, no Valve files) or, with `--with-game-data`, `dist/CS16-with-game-data.dmg`
  (personal). The staged app of the last build is at `dist/stage/CS 1.6.app`. Both are git-ignored, and so is `xash-build/`
  (the hand-built dev tree used by `play.sh` and as a game-data fallback).
- Build deps: `cmake pkgconf freetype libpng` from Homebrew. SDL3 is built from `src/SDL3` on purpose, because
  Homebrew's SDL requires the build host's macOS version. Don't switch back to Homebrew SDL or `sdl2-compat`.
- Deployment target is macOS 15. After changing any build flags, check every binary's `minos` with
  `otool -l <file> | grep -A3 LC_BUILD_VERSION`, and check that `otool -L` shows nothing from `/opt/homebrew` or
  `/Users`. The script already fails on the latter.

## Rules
- **Never edit `make-dmg.sh` while it is running.** bash reads scripts incrementally, so editing mid-run corrupts the
  run. Wait for it to finish (`pgrep -f "bash ./make-dmg.sh"`).
- **Don't modify submodules in place as the fix of record.** Make the change, save it with
  `git -C <submodule> diff > patches/<submodule>-<what>.patch`, and let `make-dmg.sh` apply it. The apply step is
  idempotent: it skips a patch that is already applied.
- **First-run defaults** go in the `first-run.cfg` heredoc in `make-dmg.sh`, never in `userconfig.cfg`.
  `userconfig.cfg` runs on every launch and would override the player's own changes.
- **What gets skipped on import** lives in `import-excludes.txt` (heredoc in `make-dmg.sh`). The build and the in-app
  import share it, so edit it in one place.
- Keep the `filesystem_stdio.dylib` symlink line in the app launcher. Removing it brings back the map-load crash
  (see README, "How the installed app runs").
- **This repo is public.** Valve game data and Valve art must never be committed or published. Only the public DMG
  (built without flags) goes to Releases. Before uploading, run `find "dist/stage/CS 1.6.app/Contents/Resources/game" -type f`
  and confirm it lists only our binaries, `extras.pk3` and `userconfig.cfg`. `CS16-with-game-data.dmg` stays local.
- No secrets in the repo: server SSH/RCON/admin passwords stay out of commits, logs and docs.

## Testing the app
- The player's real settings live in `~/Library/Application Support/CS16`. To test a first launch, move that folder
  aside, run the test, then restore it, even if the test fails. Don't fake `HOME`: the engine stalls in a modal
  dialog with an empty home dir.
- Test the public import non-interactively with `CS16_GAME_DATA=<dir with valve/ + cstrike/>`. `xash-build/` works
  as a source.
- Launch for a test: `"dist/stage/CS 1.6.app/Contents/MacOS/CS16" +maxplayers 2 +map de_dust2 > log 2>&1 &`, then
  check the process is still alive after ~15 s and `grep -E "Crash|signal" log`.
- **Stop only the PID you started** (`kill $!`). Never use `pkill -f xash3d`, because it also kills the player's own
  running game. Before touching config files, check `pgrep -fl xash3d`: the engine rewrites `config.cfg` on exit
  and would discard your edit.
- For crashes, get a backtrace under lldb:
  `lldb --batch -o "process handle SIGSEGV -s true -p false" -o run -k "bt 15" -k kill -- ./xash3d -game cstrike ...`
  from the game dir, with `XASH3D_BASEDIR` and `XASH3D_RODIR` set as the launcher sets them.
- Screen capture is not available to agents here, so UI changes need the user to confirm visually.

## Useful facts
- Engine config precedence: base dir (Application Support) wins over the read-only dir (app bundle) for any file
  present in both.
- Engine limits: `cl_updaterate` ≤ 102, `cl_cmdrate` ≤ 100, `fps_max` ≤ 200 unless `fps_override 1`.
- `hud_scale` scales only the in-game HUD (HUD, buy menu, scoreboard), not the main menu.
- The companion server (ReHLDS + ReUnion in Docker) is not managed from this repo.

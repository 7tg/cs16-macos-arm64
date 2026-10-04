# CS 1.6 on Apple Silicon (native arm64)

Counter-Strike 1.6 running natively on M-series Macs, without Rosetta or Wine, via
[Xash3D FWGS](https://github.com/FWGS/xash3d-fwgs) (engine) + [CS16Client](https://github.com/Velaron/cs16-client) (game code, includes YaPB bots).

The ready-to-install DMG (game data included, macOS 15+) is attached to the **Releases** of this repo.

## Layout
- `make-dmg.sh` builds `dist/CS16.dmg`: SDL3 + engine + client built for macOS 15, Homebrew dylibs bundled
  and relinked, Valve data copied from the local Steam install, ad-hoc signed.
- `play.sh` runs the dev build in `xash-build/` (built by hand, see below).
- `src/` holds the engine, client and SDL3 as submodules, pinned to the commits that were built.

## Rebuild
```sh
git clone --recursive <this repo> ~/Games/CS16
brew install cmake pkgconf freetype libpng
# Counter-Strike must be installed in Steam (valve/ + cstrike/ data)
~/Games/CS16/make-dmg.sh
```

## Notes
- Installed app: game data runs read-only from inside the app, and settings go to `~/Library/Application Support/CS16`.
  The launcher symlinks `filesystem_stdio.dylib` there because the CS server DLL dlopens it from the cwd
  (without it, starting a map crashes in `BotPhraseManager::Initialize`).
- First launch on another Mac: System Settings → Privacy & Security → Open Anyway (ad-hoc signed).
- Console: F1 (or the backtick key).
- Steam-auth servers reject Xash. The own server runs ReHLDS + ReUnion (with the `steam_legacy` libsteam_api,
  since the HL25 one lacks `SteamGameServer_Init`) so non-Steam clients can join.

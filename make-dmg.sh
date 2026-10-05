#!/bin/bash
# Build "CS 1.6.app" (Xash3D FWGS + CS16Client, native arm64) and wrap it in a DMG.
#
#   ./make-dmg.sh                    public build, no Valve files -> dist/CS16.dmg
#                                    (the app imports valve/ + cstrike/ from the player's own copy on first launch)
#   ./make-dmg.sh --with-game-data   personal build with the game data baked in -> dist/CS16-with-game-data.dmg
#                                    (never publish this one)
set -euo pipefail

WITH_DATA=0
case "${1:-}" in
  --with-game-data) WITH_DATA=1 ;;
  "") ;;
  *) echo "usage: $0 [--with-game-data]"; exit 2 ;;
esac

ROOT="$(cd "$(dirname "$0")" && pwd)"
SRC="$ROOT/src"
DIST="$ROOT/dist"
DEPS="$DIST/deps"
PAYLOAD="$DIST/payload"
STAGE="$DIST/stage"
APP="$STAGE/CS 1.6.app"
RES="$APP/Contents/Resources"
SDL3_VER=3.4.18
export MACOSX_DEPLOYMENT_TARGET=15.0

rm -rf "$PAYLOAD" "$STAGE"
mkdir -p "$DEPS" "$PAYLOAD"

# --- SDL3, built for the deployment target (Homebrew's requires the build host's macOS) ---
if [ ! -f "$DEPS/lib/libSDL3.0.dylib" ]; then
  [ -d "$SRC/SDL3" ] || git clone --depth 1 --branch "release-$SDL3_VER" https://github.com/libsdl-org/SDL.git "$SRC/SDL3"
  cmake -S "$SRC/SDL3" -B "$SRC/SDL3/build-dist" -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=$MACOSX_DEPLOYMENT_TARGET -DCMAKE_INSTALL_PREFIX="$DEPS" \
    -DSDL_SHARED=ON -DSDL_STATIC=OFF -DSDL_TESTS=OFF -DSDL_EXAMPLES=OFF
  cmake --build "$SRC/SDL3/build-dist" -j8
  cmake --install "$SRC/SDL3/build-dist"
fi

# --- Engine (SDL3 backend) ---
cd "$SRC/xash3d-fwgs"
PKG_CONFIG_PATH="$DEPS/lib/pkgconfig" ./waf configure -o build-dist -T release --64bits -3 --sdl-use-pkgconfig --prefix=/
./waf -o build-dist build
./waf -o build-dist install --destdir="$PAYLOAD"

# --- CS16Client ---
# local fixes (see patches/), applied once
for p in "$ROOT"/patches/mainui_cpp-*.patch; do
  M="$SRC/cs16-client/3rdparty/mainui_cpp"
  git -C "$M" apply --reverse --check "$p" 2>/dev/null || git -C "$M" apply "$p"
done
cmake -S "$SRC/cs16-client" -B "$SRC/cs16-client/build-dist" -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=$MACOSX_DEPLOYMENT_TARGET -DCMAKE_INSTALL_PREFIX="$PAYLOAD"
cmake --build "$SRC/cs16-client/build-dist" -j8
cmake --install "$SRC/cs16-client/build-dist"

# --- Bundle third-party dylibs next to the engine and relink everything relatively ---
cd "$PAYLOAD"
cp "$DEPS/lib/libSDL3.0.dylib" .
cp /opt/homebrew/opt/freetype/lib/libfreetype.6.dylib /opt/homebrew/opt/libpng/lib/libpng16.16.dylib .
chmod u+w *.dylib

relink() { # file old new
  install_name_tool -change "$2" "$3" "$1" 2>/dev/null || true
}
for f in *.dylib cstrike/cl_dlls/*.dylib cstrike/dlls/*.dylib; do
  install_name_tool -id "@rpath/$(basename "$f")" "$f"
  for dep in $(otool -L "$f" | tail -n +2 | awk '{print $1}' | grep -E "/opt/homebrew|$DEPS|@rpath/libSDL3"); do
    name=$(basename "$dep")
    case "$f" in
      cstrike/*) relink "$f" "$dep" "@loader_path/../../$name" ;;
      *)         relink "$f" "$dep" "@loader_path/$name" ;;
    esac
  done
done

# Fail loudly if anything still points outside the bundle
if otool -L xash3d *.dylib cstrike/cl_dlls/*.dylib cstrike/dlls/*.dylib | grep -E "/opt/homebrew|/Users/"; then
  echo "ERROR: unbundled dependency left (see above)"; exit 1
fi

# Console on F1 (key left of 1 is § on ISO keyboards)
echo 'bind "F1" "toggleconsole"' > cstrike/userconfig.cfg

# --- App bundle ---
mkdir -p "$APP/Contents/MacOS" "$RES"
cp -R "$PAYLOAD" "$RES/game"

# What never to take from a game install: Valve's x86/Windows/Linux binaries (our arm64 builds replace
# them) and per-machine state an engine may have written there. Shared by the build and the in-app import.
cat > "$RES/import-excludes.txt" <<'EOF'
*.dll
*.so
dlls/*.dylib
cl_dlls/*.dylib
*.bak
logs/
.xash_id
console_history.txt
history_servers.lst
opengl.cfg
video.cfg
vfs.cfg
voice_ban.dt
userconfig.cfg
EOF

# First-run defaults, appended to the player's initial config.cfg (bundled one, or the imported one).
# The engine writes the player's own config.cfg on exit, so these never override later changes.
cat > "$RES/first-run.cfg" <<'EOF'

// CS16Client static crosshair
xhair_enable "1"
xhair_dynamic_scale "0"
xhair_dynamic_move "0"
cl_dynamiccrosshair "0"

// scale the HUD as if the screen were 1280 wide (no effect at or below 1280)
hud_scale "1280"

// keep the plain nickname on GoldSrc servers (the "[Xash3D]" prefix breaks name-based admin)
cl_advertise_engine_in_name "0"

// match 100-tick servers (engine caps: updaterate 102, cmdrate 100)
cl_updaterate "101"
cl_cmdrate "100"
rate "100000"
ex_interp "0.01"
fps_max "200"
EOF

# Icon: CS16Client's own artwork (GPL, ships with the source), so the public build carries no Valve art
ICONSET="$DIST/AppIcon.iconset"; rm -rf "$ICONSET"; mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$SRC/cs16-client/android/app/src/main/ic_launcher-playstore.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$SRC/cs16-client/android/app/src/main/ic_launcher-playstore.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$RES/AppIcon.icns"

if [ "$WITH_DATA" = 1 ]; then
  # Valve game data from the local Steam install; falls back to the dev tree when Counter-Strike
  # is no longer installed in Steam. --ignore-existing keeps our arm64 builds of anything both provide.
  STEAM_HL="${STEAM_HL:-$HOME/Library/Application Support/Steam/steamapps/common/Half-Life}"
  [ -f "$STEAM_HL/valve/halflife.wad" ] || STEAM_HL="$ROOT/xash-build"
  [ -f "$STEAM_HL/valve/halflife.wad" ] && [ -f "$STEAM_HL/cstrike/liblist.gam" ] \
    || { echo "ERROR: no complete valve/cstrike data in Steam or $ROOT/xash-build"; exit 1; }
  echo "Game data from: $STEAM_HL"
  for mod in valve cstrike; do
    rsync -a --ignore-existing --exclude-from="$RES/import-excludes.txt" "$STEAM_HL/$mod/" "$RES/game/$mod/"
  done
  cat "$RES/first-run.cfg" >> "$RES/game/cstrike/config.cfg"
  DMG="$DIST/CS16-with-game-data.dmg"
else
  DMG="$DIST/CS16.dmg"
fi

VERSION=$(date +%Y%m%d%H%M%S)
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>CS 1.6</string>
  <key>CFBundleDisplayName</key><string>CS 1.6</string>
  <key>CFBundleIdentifier</key><string>io.github.7tg.cs16-macos-arm64</string>
  <key>CFBundleExecutable</key><string>CS16</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.1</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>$MACOSX_DEPLOYMENT_TARGET</string>
  <key>LSArchitecturePriority</key><array><string>arm64</string></array>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
EOF

cat > "$APP/Contents/MacOS/CS16" <<'EOF'
#!/bin/bash
# Engine (and, in personal builds, game data) run read-only from inside the app; settings, screenshots,
# downloaded maps and imported game data go to ~/Library/Application Support/CS16.
set -e
RES="$(cd "$(dirname "$0")/../Resources" && pwd)"
GAME="$RES/game"
DATA="$HOME/Library/Application Support/CS16"
STEAM_HL="$HOME/Library/Application Support/Steam/steamapps/common/Half-Life"
mkdir -p "$DATA/cstrike"

valid_install() { [ -f "$1/valve/halflife.wad" ] && [ -f "$1/cstrike/liblist.gam" ]; }
have_data() { valid_install "$GAME" || valid_install "$DATA"; }
say() { osascript -e "display dialog \"$1\" with title \"CS 1.6\" buttons {\"OK\"} default button 1" >/dev/null 2>&1 || true; }

# Public builds ship no Valve files: import them once from the player's own copy.
# CS16_GAME_DATA=/path/to/Half-Life skips the search (also handy for scripting).
if ! have_data; then
  SRC_HL="${CS16_GAME_DATA:-}"
  [ -z "$SRC_HL" ] && valid_install "$STEAM_HL" && SRC_HL="$STEAM_HL"
  while [ -z "$SRC_HL" ] || ! valid_install "$SRC_HL"; do
    [ -n "$SRC_HL" ] && say "That folder doesn't contain the Counter-Strike game files (it needs both a valve and a cstrike folder)."
    BTN=$(osascript -e 'button returned of (display dialog "CS 1.6 needs the game files from your own copy of Counter-Strike.\n\nInstall Counter-Strike in Steam (it downloads even though Steam cannot run it) and open CS 1.6 again, or choose a Half-Life folder copied from any PC or Mac — the one containing valve and cstrike." with title "CS 1.6" buttons {"Quit", "Choose Folder…"} default button 2)' 2>/dev/null) || exit 0
    [ "$BTN" = "Quit" ] && exit 0
    SRC_HL=$(osascript -e 'POSIX path of (choose folder with prompt "Select your Half-Life folder (contains valve and cstrike):")' 2>/dev/null) || exit 0
    SRC_HL="${SRC_HL%/}"
  done
  osascript -e 'display notification "Importing game files from your Counter-Strike install..." with title "CS 1.6"' 2>/dev/null || true
  FRESH_CONFIG=1; [ -f "$DATA/cstrike/config.cfg" ] && FRESH_CONFIG=0
  for mod in valve cstrike; do
    rsync -a --ignore-existing --exclude-from="$RES/import-excludes.txt" "$SRC_HL/$mod/" "$DATA/$mod/"
  done
  [ "$FRESH_CONFIG" = 1 ] && [ -f "$DATA/cstrike/config.cfg" ] && cat "$RES/first-run.cfg" >> "$DATA/cstrike/config.cfg"
fi

# The engine chdirs to XASH3D_BASEDIR and the CS server DLL dlopens filesystem_stdio from the cwd;
# without it the game crashes on map load. Refresh every launch since the app may have moved.
ln -sf "$GAME/filesystem_stdio.dylib" "$DATA/filesystem_stdio.dylib"

cd "$GAME"
export XASH3D_BASEDIR="$DATA" XASH3D_RODIR="$GAME"
exec ./xash3d -game cstrike -console "$@"
EOF
chmod +x "$APP/Contents/MacOS/CS16"

# Ad-hoc sign (arm64 refuses to run unsigned code; install_name_tool invalidated the signatures)
find "$RES/game" -type f \( -name "*.dylib" -o -name xash3d \) -exec codesign -f -s - {} \;
codesign -f -s - "$APP"

# --- DMG ---
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "CS 1.6" -srcfolder "$STAGE" -format UDZO -ov "$DMG"
echo "Built: $DMG"

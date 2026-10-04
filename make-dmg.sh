#!/bin/bash
# Build a self-contained "CS 1.6.app" (Xash3D FWGS + CS16Client, native arm64) and wrap it in a DMG.
# Bundles the Valve game data (valve/, cstrike/) from this Mac's Steam install, so the target Mac needs nothing else.
set -euo pipefail

ROOT="$HOME/Games/CS16"
SRC="$ROOT/src"
DIST="$ROOT/dist"
DEPS="$DIST/deps"
PAYLOAD="$DIST/payload"
APP="$DIST/stage/CS 1.6.app"
SDL3_VER=3.4.18
export MACOSX_DEPLOYMENT_TARGET=15.0

rm -rf "$PAYLOAD" "$DIST/stage"
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

# Valve game data from the local Steam install. --ignore-existing keeps our arm64 builds of anything
# both provide; Valve's own x86/Windows/Linux game binaries are dropped since they can't be used here.
# Falls back to the dev build's copy when Counter-Strike is no longer installed in Steam.
STEAM_HL="${STEAM_HL:-$HOME/Library/Application Support/Steam/steamapps/common/Half-Life}"
[ -f "$STEAM_HL/valve/halflife.wad" ] || STEAM_HL="$ROOT/xash-build"
[ -f "$STEAM_HL/valve/halflife.wad" ] && [ -f "$STEAM_HL/cstrike/liblist.gam" ] \
  || { echo "ERROR: no complete valve/cstrike data in Steam or $ROOT/xash-build"; exit 1; }
echo "Game data from: $STEAM_HL"
for mod in valve cstrike; do
  # also skip per-machine state the engine writes (only present in the xash-build fallback)
  rsync -a --ignore-existing --exclude '*.dll' --exclude '*.so' \
    --exclude 'dlls/*.dylib' --exclude 'cl_dlls/*.dylib' \
    --exclude '*.bak' --exclude 'logs/' --exclude '.xash_id' --exclude 'console_history.txt' \
    --exclude 'history_servers.lst' --exclude 'opengl.cfg' --exclude 'video.cfg' --exclude 'vfs.cfg' \
    --exclude 'voice_ban.dt' --exclude 'userconfig.cfg' \
    "$STEAM_HL/$mod/" "$PAYLOAD/$mod/"
done

# First-run defaults: the engine only falls back to this bundled config.cfg until it writes the
# player's own into Application Support, so these never override later changes.
cat >> "$PAYLOAD/cstrike/config.cfg" <<'EOF'

// CS16Client static crosshair
xhair_enable "1"
xhair_dynamic_scale "0"
xhair_dynamic_move "0"
cl_dynamiccrosshair "0"

// scale the HUD as if the screen were 1280 wide (no effect at or below 1280)
hud_scale "1280"
EOF

# Console on F1 (key left of 1 is § on ISO keyboards)
echo 'bind "F1" "toggleconsole"' > cstrike/userconfig.cfg

# --- App bundle ---
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp -R "$PAYLOAD" "$APP/Contents/Resources/game"
cp "$ROOT/xash-build/cstrike/game.icns" "$APP/Contents/Resources/AppIcon.icns"
VERSION=$(date +%Y%m%d%H%M%S)
echo "$VERSION" > "$APP/Contents/Resources/game/.payload-version"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>CS 1.6</string>
  <key>CFBundleDisplayName</key><string>CS 1.6</string>
  <key>CFBundleIdentifier</key><string>local.cs16.xash3d</string>
  <key>CFBundleExecutable</key><string>CS16</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>$MACOSX_DEPLOYMENT_TARGET</string>
  <key>LSArchitecturePriority</key><array><string>arm64</string></array>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
EOF

cat > "$APP/Contents/MacOS/CS16" <<'EOF'
#!/bin/bash
# Engine + game data run read-only from inside the app; settings, screenshots and
# downloaded maps go to ~/Library/Application Support/CS16 (an .app must not write into itself).
set -e
GAME="$(cd "$(dirname "$0")/../Resources/game" && pwd)"
DATA="$HOME/Library/Application Support/CS16"
mkdir -p "$DATA/cstrike"
# The engine chdirs to XASH3D_BASEDIR and the CS server DLL dlopens filesystem_stdio from the cwd;
# without it the game crashes on map load. Refresh every launch since the app may have moved.
ln -sf "$GAME/filesystem_stdio.dylib" "$DATA/filesystem_stdio.dylib"

cd "$GAME"
export XASH3D_BASEDIR="$DATA" XASH3D_RODIR="$GAME"
exec ./xash3d -game cstrike -console "$@"
EOF
chmod +x "$APP/Contents/MacOS/CS16"

# Ad-hoc sign (arm64 refuses to run unsigned code; install_name_tool invalidated the signatures)
find "$APP/Contents/Resources/game" -type f \( -name "*.dylib" -o -name xash3d \) -exec codesign -f -s - {} \;
codesign -f -s - "$APP"

# --- DMG ---
ln -s /Applications "$DIST/stage/Applications"
rm -f "$DIST/CS16.dmg"
hdiutil create -volname "CS 1.6" -srcfolder "$DIST/stage" -format UDZO -ov "$DIST/CS16.dmg"
echo "Built: $DIST/CS16.dmg"

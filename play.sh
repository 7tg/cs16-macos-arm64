#!/bin/bash
# Launch CS 1.6 natively (arm64) via Xash3D FWGS + CS16Client.
# Copies game assets from the Steam install on first run (only files we don't already have,
# so the arm64 dylibs from the build are never overwritten).
set -e
BUILD="$HOME/Games/CS16/xash-build"
STEAM="${STEAM_HL:-$HOME/Library/Application Support/Steam/steamapps/common/Half-Life}"
if [ ! -f "$BUILD/cstrike/liblist.gam" ]; then
  [ -d "$STEAM/cstrike" ] || { echo "Game files not found at: $STEAM"; echo "Install Counter-Strike in Steam first (or set STEAM_HL=/path/to/Half-Life)."; exit 1; }
  echo "Copying game assets from Steam..."
  rsync -a --ignore-existing "$STEAM/valve/" "$BUILD/valve/"
  rsync -a --ignore-existing "$STEAM/cstrike/" "$BUILD/cstrike/"
fi
cd "$BUILD"
exec ./xash3d -game cstrike -console "$@"

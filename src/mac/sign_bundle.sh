#!/bin/sh
# sign_bundle.sh <APP_BUNDLE_PATH>
# Removes dangling symlinks, clears xattrs, then signs the bundle.
# Uses "EVE Imager Dev" self-signed cert if present in keychain (set up via
# setup-codesign.sh), otherwise falls back to ad-hoc signing.
set -e
APP="$1"
if [ -z "$APP" ]; then
  echo "Usage: $0 <app_bundle_path>" >&2
  exit 1
fi
# Remove broken symlinks (left after plugin pruning)
find "$APP" -type l | while read L; do
  if ! test -e "$L"; then rm -f "$L"; fi
done
# Clear extended attributes (quarantine etc.)
xattr -cr "$APP" 2>/dev/null || true
# Use trusted self-signed cert if available, otherwise ad-hoc
IDENTITY="-"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "EVE Imager Dev"; then
  IDENTITY="EVE Imager Dev"
fi
codesign --deep --force --sign "$IDENTITY" --timestamp=none "$APP"
echo "Signed: $APP (identity: $IDENTITY)"

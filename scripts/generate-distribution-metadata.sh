#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VERSION=$(tr -d '[:space:]' < "$ROOT/VERSION")
ARM_ARCHIVE=${ARM_ARCHIVE:-"$ROOT/dist/arm64/PortHarbor-$VERSION-arm64.zip"}
INTEL_ARCHIVE=${INTEL_ARCHIVE:-"$ROOT/dist/x86_64/PortHarbor-$VERSION-x86_64.zip"}
ARM_SIGNATURE=${ARM_ED_SIGNATURE:-}
INTEL_SIGNATURE=${INTEL_ED_SIGNATURE:-}

test -f "$ARM_ARCHIVE"
test -f "$INTEL_ARCHIVE"

if test -n "${SPARKLE_SIGN_UPDATE:-}"; then
    ARM_SIGNATURE=$($SPARKLE_SIGN_UPDATE "$ARM_ARCHIVE" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')
    INTEL_SIGNATURE=$($SPARKLE_SIGN_UPDATE "$INTEL_ARCHIVE" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')
fi

: "${ARM_SIGNATURE:?ARM_ED_SIGNATURE or SPARKLE_SIGN_UPDATE is required}"
: "${INTEL_SIGNATURE:?INTEL_ED_SIGNATURE or SPARKLE_SIGN_UPDATE is required}"

ARM_SHA=$(/usr/bin/shasum -a 256 "$ARM_ARCHIVE" | awk '{print $1}')
INTEL_SHA=$(/usr/bin/shasum -a 256 "$INTEL_ARCHIVE" | awk '{print $1}')
ARM_LENGTH=$(stat -f %z "$ARM_ARCHIVE")
INTEL_LENGTH=$(stat -f %z "$INTEL_ARCHIVE")

# Escape values before inserting them into sed replacement expressions.
# Sparkle EdDSA signatures are Base64 and may contain '/', '&', or '\\'.
escape_sed_replacement() {
    printf '%s' "$1" | sed 's/[\\&|]/\\&/g'
}

ARM_SIGNATURE_ESCAPED=$(escape_sed_replacement "$ARM_SIGNATURE")
INTEL_SIGNATURE_ESCAPED=$(escape_sed_replacement "$INTEL_SIGNATURE")

mkdir -p "$ROOT/Casks"

sed -e "s/@VERSION@/$VERSION/g" \
    -e "s/@ARM_SHA@/$ARM_SHA/g" \
    -e "s/@INTEL_SHA@/$INTEL_SHA/g" \
    "$ROOT/distribution/portharbor.rb.template" > "$ROOT/Casks/portharbor.rb"

sed -e "s|@VERSION@|$VERSION|g" \
    -e "s|@ARM_LENGTH@|$ARM_LENGTH|g" \
    -e "s|@INTEL_LENGTH@|$INTEL_LENGTH|g" \
    -e "s|@ARM_SIGNATURE@|$ARM_SIGNATURE_ESCAPED|g" \
    -e "s|@INTEL_SIGNATURE@|$INTEL_SIGNATURE_ESCAPED|g" \
    "$ROOT/distribution/appcast.xml.template" > "$ROOT/appcast.xml"

printf '%s\n' "$ROOT/appcast.xml" "$ROOT/Casks/portharbor.rb"

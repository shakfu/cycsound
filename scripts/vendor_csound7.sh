#!/usr/bin/env bash
#
# vendor_csound7.sh - Download and vendor the Csound 7 beta macOS framework.
#
# The Csound 7 macOS release ships as a .pkg installer whose framework has an
# absolute install name (/Applications/Csound/...). To use the framework from a
# repo-local location without a system install, this script extracts the
# framework into vendor/ and repoints its install id to the absolute vendored
# path so the built extension can locate it at runtime.
#
# The release asset is a public download, so no GitHub account or gh CLI is
# needed: it is fetched over plain HTTPS with curl (or wget as a fallback).
#
# Requires: curl or wget, pkgutil, install_name_tool, codesign (macOS).
#
# Usage: scripts/vendor_csound7.sh [tag]
set -euo pipefail

TAG="${1:-7.0.0-beta.16}"
REPO="csound/csound"
ASSET="csound-macos-${TAG}.zip"
URL="https://github.com/${REPO}/releases/download/${TAG}/${ASSET}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
VENDOR_DIR="${ROOT_DIR}/vendor"
FRAMEWORK="${VENDOR_DIR}/CsoundLib64.framework"

if [[ "$(uname)" != "Darwin" ]]; then
    echo "error: this script targets macOS only" >&2
    exit 1
fi

mkdir -p "${VENDOR_DIR}"
cd "${VENDOR_DIR}"

echo ">> downloading ${URL}"
if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 3 -o "${ASSET}" "${URL}"
elif command -v wget >/dev/null 2>&1; then
    wget -O "${ASSET}" "${URL}"
else
    echo "error: need curl or wget to download the Csound 7 framework" >&2
    exit 1
fi

echo ">> extracting"
rm -rf _extract "${FRAMEWORK}"
mkdir -p _extract
unzip -q -o "${ASSET}" -d _extract
PKG="$(find _extract -name '*.pkg' | head -1)"
pkgutil --expand "${PKG}" _pkg
mkdir -p _payload
tar xzf _pkg/Payload -C _payload
mv "$(find _payload -name 'CsoundLib64.framework' -maxdepth 5 | head -1)" "${FRAMEWORK}"
rm -rf _extract _pkg _payload

BIN="${FRAMEWORK}/Versions/Current/CsoundLib64"
echo ">> repointing install id to vendored path"
install_name_tool -id "${BIN}" "${BIN}"
echo ">> re-signing (ad-hoc)"
codesign --force --sign - "${BIN}"

echo ">> done: ${FRAMEWORK}"
otool -D "${BIN}" | sed -n '1,2p'

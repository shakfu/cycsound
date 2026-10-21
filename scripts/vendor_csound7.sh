#!/usr/bin/env bash
#
# vendor_csound7.sh - Download and vendor the Csound 7 runtime.
#
# The wrapper targets Csound 7, which on most systems is not the Csound that a
# distro/Homebrew package manager installs (that is still Csound 6). To keep a
# Csound 6 system install untouched, this script fetches the official Csound 7
# release binaries and stages them under a repo-local vendor/ directory that
# CMake links against.
#
# macOS: the release ships a .pkg installer whose CsoundLib64.framework has an
#   absolute install name (/Library/Frameworks/...). The framework is extracted
#   to vendor/CsoundLib64.framework and its install id is repointed at that
#   vendored path so the built extension finds it at runtime.
#
# Linux: the "linux-minimal" release ships libcsound64.so plus its opcode
#   plugins. They are staged as vendor/lib/ and vendor/plugins/; CMake links
#   against vendor/lib and bakes an rpath so no LD_LIBRARY_PATH is needed. The
#   release carries no headers, so the build uses the repo-local include/
#   directory (kept in sync with the same tag).
#
# The release assets are public downloads, so no GitHub account or gh CLI is
# needed: they are fetched over plain HTTPS with curl (or wget as a fallback).
#
# Requires: curl or wget, unzip; plus pkgutil/install_name_tool/codesign on
# macOS, and patchelf (optional, for the plugin rpath) on Linux.
#
# Usage: scripts/vendor_csound7.sh [tag]
set -euo pipefail

TAG="${1:-7.0.0}"
REPO="csound/csound"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
VENDOR_DIR="${ROOT_DIR}/vendor"

fetch() {
    local url="$1" out="$2"
    echo ">> downloading ${url}"
    if command -v curl >/dev/null 2>&1; then
        curl -fL --retry 3 -o "${out}" "${url}"
    elif command -v wget >/dev/null 2>&1; then
        wget -O "${out}" "${url}"
    else
        echo "error: need curl or wget to download the Csound 7 release" >&2
        exit 1
    fi
}

vendor_macos() {
    local asset="csound-macos-${TAG}.zip"
    local framework="${VENDOR_DIR}/CsoundLib64.framework"

    cd "${VENDOR_DIR}"
    fetch "https://github.com/${REPO}/releases/download/${TAG}/${asset}" "${asset}"

    echo ">> extracting"
    rm -rf _extract "${framework}"
    mkdir -p _extract
    unzip -q -o "${asset}" -d _extract
    local pkg
    pkg="$(find _extract -name '*.pkg' | head -1)"
    pkgutil --expand "${pkg}" _pkg
    mkdir -p _payload
    tar xzf _pkg/Payload -C _payload
    mv "$(find _payload -name 'CsoundLib64.framework' -maxdepth 5 | head -1)" "${framework}"
    rm -rf _extract _pkg _payload

    local bin="${framework}/Versions/Current/CsoundLib64"
    echo ">> repointing install id to vendored path"
    install_name_tool -id "${bin}" "${bin}"
    echo ">> re-signing (ad-hoc)"
    codesign --force --sign - "${bin}"

    echo ">> done: ${framework}"
    otool -D "${bin}" | sed -n '1,2p'
}

vendor_linux() {
    local arch
    arch="$(uname -m)"
    if [[ "${arch}" != "x86_64" ]]; then
        echo "error: no Csound 7 Linux release asset for ${arch}" >&2
        exit 1
    fi

    local asset="csound-linux-minimal-${arch}-${TAG}.zip"

    cd "${VENDOR_DIR}"
    fetch "https://github.com/${REPO}/releases/download/${TAG}/${asset}" "${asset}"

    echo ">> extracting"
    rm -rf _extract "${VENDOR_DIR}/lib" "${VENDOR_DIR}/plugins"
    mkdir -p _extract
    unzip -q -o "${asset}" -d _extract

    local payload
    payload="$(find _extract -maxdepth 2 -name 'libcsound64.so' -print -quit)"
    if [[ -z "${payload}" ]]; then
        echo "error: libcsound64.so not found in ${asset}" >&2
        exit 1
    fi
    payload="$(dirname "${payload}")"

    mkdir -p "${VENDOR_DIR}/lib"
    cp -a "${payload}"/libcsound64.so* "${VENDOR_DIR}/lib/"
    if [[ -d "${payload}/plugins" ]]; then
        cp -a "${payload}/plugins" "${VENDOR_DIR}/plugins"
    fi
    rm -rf _extract

    # The plugins link against libcsound64.so; give them an rpath to the
    # vendored library so OPCODE7DIR64 loading works without LD_LIBRARY_PATH.
    if command -v patchelf >/dev/null 2>&1; then
        echo ">> setting plugin rpath"
        local so
        for so in "${VENDOR_DIR}"/plugins/*.so; do
            [[ -e "${so}" ]] || continue
            patchelf --set-rpath "${VENDOR_DIR}/lib" "${so}" 2>/dev/null || true
        done
    else
        echo ">> note: patchelf not found; plugin rpath left unset"
    fi

    echo ">> done: ${VENDOR_DIR}/lib/libcsound64.so"
}

mkdir -p "${VENDOR_DIR}"

case "$(uname)" in
    Darwin) vendor_macos ;;
    Linux)  vendor_linux ;;
    *)      echo "error: unsupported platform $(uname)" >&2; exit 1 ;;
esac

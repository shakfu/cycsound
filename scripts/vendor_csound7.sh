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
#   vendored path so the built extension finds it at runtime. Its driver
#   plugins (Resources/Opcodes64) are staged as vendor/plugins/. The libraries
#   three of them need (PortAudio, PortMidi, liblo) are rebuilt from source
#   into vendor/deps/: the release's copies require macOS 26.0, the rest of
#   the framework 12.0.
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
# Requires: curl or wget, unzip; plus pkgutil/install_name_tool/codesign,
# cmake and a C compiler on macOS, and patchelf (optional, for the plugin
# rpath) on Linux.
#
# Usage: scripts/vendor_csound7.sh [tag]
set -euo pipefail

TAG="${1:-7.0.0}"
REPO="csound/csound"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
VENDOR_DIR="${ROOT_DIR}/vendor"

# macOS plugin dependencies: name, GitHub repo, commit, archive sha256, CMake
# source subdirectory, extra CMake arguments. The commits are those the
# 7.0.0 release was built from (default branches on 2026-10-21).
MACOS_TARGET="12.0"
MACOS_DEPS=(
    "libportmidi PortMidi/portmidi 6b51c25659965ff763e266e4d90be099b5bcb344 c714d54f6823c8a73b44aab44785539cd7398b549302e7cea2f9c740ae2ccd30 ."
    "libportaudio PortAudio/portaudio 7c45fed9322bd86b5dd0da4547b15d9ac3b9b0ac d236b3482ca938858010dcb76b08f43b3f63a7aba9dfd465b20c446e5e5eeca3 ."
    "liblo radarsat1/liblo 025f277275e6b81032a72dfb0b131adab80363e6 7254eab24f8ac96d9ebb4c933eb8e2704e5c61f1901e42936b90fdeed52d3eaf cmake -DWITH_TOOLS=OFF -DWITH_TESTS=OFF -DWITH_EXAMPLES=OFF -DWITH_CPP_TESTS=OFF"
)

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

# Build MACOS_DEPS as universal dylibs into vendor/deps with absolute
# install names, and fail if any requires a macOS newer than MACOS_TARGET.
build_macos_deps() {
    local prefix="${VENDOR_DIR}/deps" cmake="${CMAKE:-cmake}"
    local spec name repo rev sum subdir args src lib minos
    rm -rf "${prefix}" _deps
    mkdir -p _deps
    for spec in "${MACOS_DEPS[@]}"; do
        read -r name repo rev sum subdir args <<< "${spec}"
        src="_deps/${name}"
        fetch "https://github.com/${repo}/archive/${rev}.tar.gz" "${src}.tar.gz"
        echo "${sum}  ${src}.tar.gz" | shasum -a 256 -c -
        mkdir -p "${src}"
        tar xzf "${src}.tar.gz" -C "${src}" --strip-components 1
        # shellcheck disable=SC2086  # args is a list of flags
        "${cmake}" -S "${src}/${subdir}" -B "${src}/build" \
            -DCMAKE_BUILD_TYPE=Release \
            -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
            -DCMAKE_OSX_DEPLOYMENT_TARGET="${MACOS_TARGET}" \
            -DCMAKE_INSTALL_PREFIX="${prefix}" \
            -DCMAKE_INSTALL_NAME_DIR="${prefix}/lib" \
            ${args}
        "${cmake}" --build "${src}/build" --parallel
        "${cmake}" --install "${src}/build"
    done
    rm -rf _deps

    for lib in "${prefix}"/lib/*.dylib; do
        [[ -L "${lib}" ]] && continue
        for minos in $(otool -l "${lib}" | awk '/minos/{print $2}' | sort -u); do
            if [[ "${minos}" != "${MACOS_TARGET}" ]]; then
                echo "error: ${lib} targets macOS ${minos}, not ${MACOS_TARGET}" >&2
                exit 1
            fi
        done
    done
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

    echo ">> building plugin dependencies for macOS ${MACOS_TARGET}"
    build_macos_deps

    # Stage the driver plugins (rtaudio, rtmidi, osc, ...). Repoint their
    # links to the framework's libs/ at the rebuilt copies, by absolute path,
    # so the staged plugins resolve and delocate can bundle them.
    echo ">> staging plugins"
    rm -rf "${VENDOR_DIR}/plugins"
    mkdir -p "${VENDOR_DIR}/plugins"
    cp "${framework}"/Resources/Opcodes64/*.dylib "${VENDOR_DIR}/plugins/"
    local so dep
    for so in "${VENDOR_DIR}"/plugins/*.dylib; do
        for dep in $(otool -L "${so}" | awk '/@loader_path\/.*\/libs\//{print $1}'); do
            install_name_tool -change "${dep}" \
                "$(otool -D "${VENDOR_DIR}/deps/lib/${dep##*/}" | tail -1)" "${so}"
        done
        codesign --force --sign - "${so}"
    done

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

# Read by the Makefile to re-vendor when TAG changes.
printf '%s\n' "${TAG}" > "${VENDOR_DIR}/.tag"

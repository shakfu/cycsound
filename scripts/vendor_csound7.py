#!/usr/bin/env python3
"""vendor_csound7.py - Download and vendor the Csound 7 runtime.

The wrapper targets Csound 7, which on most systems is not the Csound that a
distro/Homebrew package manager installs (that is still Csound 6). To keep a
Csound 6 system install untouched, this script fetches the official Csound 7
release binaries and stages them under a repo-local vendor/ directory that
CMake links against.

macOS: the release ships a .pkg installer whose CsoundLib64.framework has an
  absolute install name (/Library/Frameworks/...). The framework is extracted
  to vendor/CsoundLib64.framework and its install id is repointed at that
  vendored path so the built extension finds it at runtime. Its driver
  plugins (Resources/Opcodes64) are staged as vendor/plugins/. The libraries
  three of them need (PortAudio, PortMidi, liblo) are rebuilt from source
  into vendor/deps/: the release's copies require macOS 26.0, the rest of
  the framework 12.0.

Linux: the "linux-minimal" release ships libcsound64.so plus its opcode
  plugins. They are staged as vendor/lib/ and vendor/plugins/; CMake links
  against vendor/lib and bakes an rpath so no LD_LIBRARY_PATH is needed. The
  release carries no headers, so the build uses the repo-local include/
  directory (kept in sync with the same tag).

Windows: the release ships only an Inno Setup installer, newer than
  innoextract supports, which sets OPCODE7DIR64 machine-wide and so needs
  admin rights. It is run silently as a system install into
  C:/Program Files/Csound7_x64, where CMake finds it; without admin rights
  a UAC prompt is raised. Csound 7's DLL (csound7_64.dll) does not clash
  with a Csound 6 install.

The release assets are public downloads, so no GitHub account or gh CLI is
needed: they are fetched over plain HTTPS with the standard library.

Requires: Python 3.8+; plus pkgutil/tar/install_name_tool/codesign/otool,
cmake and a C compiler on macOS, and patchelf (optional, for the plugin
rpath) on Linux.

Usage: scripts/vendor_csound7.py [tag]
"""

import ctypes
import glob
import hashlib
import os
import platform
import shutil
import subprocess
import sys
import tarfile
import urllib.request
import zipfile

TAG = "7.0.0"
REPO = "csound/csound"

# Where the Windows installer puts Csound 7; CMakeLists.txt expects it here.
WINDOWS_ROOT = r"C:\Program Files\Csound7_x64"

ROOT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VENDOR_DIR = os.path.join(ROOT_DIR, "vendor")

# macOS plugin dependencies: name, GitHub repo, commit, archive sha256, CMake
# source subdirectory, extra CMake arguments. The commits are those the
# 7.0.0 release was built from (default branches on 2026-10-21).
MACOS_TARGET = "12.0"
MACOS_DEPS = [
    ("libportmidi", "PortMidi/portmidi",
     "6b51c25659965ff763e266e4d90be099b5bcb344",
     "c714d54f6823c8a73b44aab44785539cd7398b549302e7cea2f9c740ae2ccd30",
     ".", []),
    ("libportaudio", "PortAudio/portaudio",
     "7c45fed9322bd86b5dd0da4547b15d9ac3b9b0ac",
     "d236b3482ca938858010dcb76b08f43b3f63a7aba9dfd465b20c446e5e5eeca3",
     ".", []),
    ("liblo", "radarsat1/liblo",
     "025f277275e6b81032a72dfb0b131adab80363e6",
     "7254eab24f8ac96d9ebb4c933eb8e2704e5c61f1901e42936b90fdeed52d3eaf",
     "cmake", ["-DWITH_TOOLS=OFF", "-DWITH_TESTS=OFF", "-DWITH_EXAMPLES=OFF",
               "-DWITH_CPP_TESTS=OFF"]),
]


def die(msg):
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(1)


def run(*cmd, **kwargs):
    return subprocess.run(cmd, check=True, **kwargs)


def output(*cmd):
    return subprocess.run(cmd, check=True, capture_output=True,
                          text=True).stdout


def fetch(url, out):
    print(f">> downloading {url}", flush=True)
    for attempt in range(3):
        try:
            with urllib.request.urlopen(url) as resp, open(out, "wb") as f:
                shutil.copyfileobj(resp, f)
            return
        except OSError as e:
            if attempt == 2:
                die(f"download failed: {e}")
            print(f">> retrying ({e})", flush=True)


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def rmtree(path):
    if os.path.islink(path) or os.path.isfile(path):
        os.remove(path)
    elif os.path.isdir(path):
        shutil.rmtree(path)


def unzip(archive, dest):
    # zipfile drops Unix permissions and symlinks, which the Linux and macOS
    # payloads rely on; use unzip(1) there as before.
    if sys.platform == "win32":
        with zipfile.ZipFile(archive) as z:
            z.extractall(dest)
    else:
        run("unzip", "-q", "-o", archive, "-d", dest)


def release_asset(asset):
    path = os.path.join(VENDOR_DIR, asset)
    fetch(f"https://github.com/{REPO}/releases/download/{TAG}/{asset}", path)
    return path


# Build MACOS_DEPS as universal dylibs into vendor/deps with absolute
# install names, and fail if any requires a macOS newer than MACOS_TARGET.
def build_macos_deps():
    prefix = os.path.join(VENDOR_DIR, "deps")
    cmake = os.environ.get("CMAKE", "cmake")
    deps = os.path.join(VENDOR_DIR, "_deps")
    rmtree(prefix)
    rmtree(deps)
    os.makedirs(deps)
    for name, repo, rev, digest, subdir, args in MACOS_DEPS:
        src = os.path.join(deps, name)
        archive = f"{src}.tar.gz"
        fetch(f"https://github.com/{repo}/archive/{rev}.tar.gz", archive)
        if sha256(archive) != digest:
            die(f"checksum mismatch for {archive}")
        print(f"{archive}: OK")
        os.makedirs(src)
        # --strip-components 1
        with tarfile.open(archive) as t:
            for m in t.getmembers():
                _, _, m.name = m.name.partition("/")
                if m.name:
                    t.extract(m, src)
        build = os.path.join(src, "build")
        run(cmake, "-S", os.path.join(src, subdir), "-B", build,
            "-DCMAKE_BUILD_TYPE=Release",
            "-DCMAKE_OSX_ARCHITECTURES=arm64;x86_64",
            f"-DCMAKE_OSX_DEPLOYMENT_TARGET={MACOS_TARGET}",
            f"-DCMAKE_INSTALL_PREFIX={prefix}",
            f"-DCMAKE_INSTALL_NAME_DIR={prefix}/lib",
            *args)
        run(cmake, "--build", build, "--parallel")
        run(cmake, "--install", build)
    rmtree(deps)

    for lib in glob.glob(os.path.join(prefix, "lib", "*.dylib")):
        if os.path.islink(lib):
            continue
        lines = output("otool", "-l", lib).splitlines()
        for minos in {ln.split()[1] for ln in lines if "minos" in ln}:
            if minos != MACOS_TARGET:
                die(f"{lib} targets macOS {minos}, not {MACOS_TARGET}")


def vendor_macos():
    framework = os.path.join(VENDOR_DIR, "CsoundLib64.framework")
    asset = release_asset(f"csound-macos-{TAG}.zip")

    print(">> extracting")
    extract = os.path.join(VENDOR_DIR, "_extract")
    pkgdir = os.path.join(VENDOR_DIR, "_pkg")
    payload = os.path.join(VENDOR_DIR, "_payload")
    for d in (extract, pkgdir, payload, framework):
        rmtree(d)
    unzip(asset, extract)
    pkgs = glob.glob(os.path.join(extract, "**", "*.pkg"), recursive=True)
    if not pkgs:
        die(f"no .pkg found in {asset}")
    run("pkgutil", "--expand", pkgs[0], pkgdir)
    os.makedirs(payload)
    run("tar", "xzf", os.path.join(pkgdir, "Payload"), "-C", payload)
    found = None
    for dirpath, dirnames, _ in os.walk(payload):
        if dirpath[len(payload):].count(os.sep) >= 5:
            dirnames[:] = []
        if "CsoundLib64.framework" in dirnames:
            found = os.path.join(dirpath, "CsoundLib64.framework")
            break
    if found is None:
        die("CsoundLib64.framework not found in the package payload")
    shutil.move(found, framework)
    for d in (extract, pkgdir, payload):
        rmtree(d)

    binary = os.path.join(framework, "Versions", "Current", "CsoundLib64")
    print(">> repointing install id to vendored path")
    run("install_name_tool", "-id", binary, binary)
    print(">> re-signing (ad-hoc)")
    run("codesign", "--force", "--sign", "-", binary)

    print(f">> building plugin dependencies for macOS {MACOS_TARGET}")
    build_macos_deps()

    # Stage the driver plugins (rtaudio, rtmidi, osc, ...). Repoint their
    # links to the framework's libs/ at the rebuilt copies, by absolute path,
    # so the staged plugins resolve and delocate can bundle them.
    print(">> staging plugins")
    plugins = os.path.join(VENDOR_DIR, "plugins")
    rmtree(plugins)
    os.makedirs(plugins)
    for so in glob.glob(os.path.join(framework, "Resources", "Opcodes64",
                                     "*.dylib")):
        shutil.copy2(so, plugins)
    for so in glob.glob(os.path.join(plugins, "*.dylib")):
        for line in output("otool", "-L", so).splitlines()[1:]:
            dep = line.split()[0] if line.split() else ""
            if not (dep.startswith("@loader_path/") and "/libs/" in dep):
                continue
            rebuilt = os.path.join(VENDOR_DIR, "deps", "lib",
                                   os.path.basename(dep))
            new = output("otool", "-D", rebuilt).splitlines()[-1].strip()
            run("install_name_tool", "-change", dep, new, so)
        run("codesign", "--force", "--sign", "-", so)

    print(f">> done: {framework}")
    print("\n".join(output("otool", "-D", binary).splitlines()[:2]))


def vendor_linux():
    arch = platform.machine()
    if arch != "x86_64":
        die(f"no Csound 7 Linux release asset for {arch}")

    asset = release_asset(f"csound-linux-minimal-{arch}-{TAG}.zip")

    print(">> extracting")
    extract = os.path.join(VENDOR_DIR, "_extract")
    lib = os.path.join(VENDOR_DIR, "lib")
    plugins = os.path.join(VENDOR_DIR, "plugins")
    for d in (extract, lib, plugins):
        rmtree(d)
    unzip(asset, extract)

    hits = (glob.glob(os.path.join(extract, "libcsound64.so"))
            + glob.glob(os.path.join(extract, "*", "libcsound64.so")))
    if not hits:
        die(f"libcsound64.so not found in {asset}")
    payload = os.path.dirname(hits[0])

    os.makedirs(lib)
    for so in glob.glob(os.path.join(payload, "libcsound64.so*")):
        shutil.copy2(so, lib, follow_symlinks=False)
    if os.path.isdir(os.path.join(payload, "plugins")):
        shutil.copytree(os.path.join(payload, "plugins"), plugins,
                        symlinks=True)
    rmtree(extract)

    # The plugins link against libcsound64.so; give them an rpath to the
    # vendored library so OPCODE7DIR64 loading works without LD_LIBRARY_PATH.
    if shutil.which("patchelf"):
        print(">> setting plugin rpath")
        for so in glob.glob(os.path.join(plugins, "*.so")):
            subprocess.run(["patchelf", "--set-rpath", lib, so],
                           stderr=subprocess.DEVNULL)
    else:
        print(">> note: patchelf not found; plugin rpath left unset")

    print(f">> done: {os.path.join(lib, 'libcsound64.so')}")


def vendor_windows():
    if platform.machine().lower() not in ("amd64", "x86_64"):
        die(f"no Csound 7 Windows release asset for {platform.machine()}")

    asset = release_asset(f"csound-windows-{TAG}.zip")

    print(">> extracting")
    extract = os.path.join(VENDOR_DIR, "_extract")
    rmtree(extract)
    unzip(asset, extract)
    exes = [p for p in glob.glob(os.path.join(extract, "**", "*.exe"),
                                 recursive=True)
            if "__MACOSX" not in p]
    if not exes:
        die(f"no installer found in {asset}")

    # The installer sets OPCODE7DIR64 machine-wide, so it needs admin rights
    # even when asked for a per-user install. CI runners are admin; locally
    # this raises one UAC prompt.
    log = os.path.join(VENDOR_DIR, "install.log")
    args = (f'/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /ALLUSERS /NOICONS '
            f'/DIR="{WINDOWS_ROOT}" /LOG="{log}"')
    print(f">> installing into {WINDOWS_ROOT}")
    print(f">> installer log: {log}", flush=True)
    if ctypes.windll.shell32.IsUserAnAdmin():
        rc = subprocess.run(f'"{exes[0]}" {args}').returncode
    else:
        print(">> requesting administrator rights", flush=True)
        ps = "'" + "''".join(exes[0].split("'")) + "'"
        rc = subprocess.run([
            "powershell", "-NoProfile", "-Command",
            f"$p = Start-Process -FilePath {ps} -ArgumentList "
            f"'{args}' -Verb RunAs -Wait -PassThru; exit $p.ExitCode",
        ]).returncode
    if rc != 0:
        if os.path.exists(log):
            with open(log, errors="replace") as f:
                sys.stderr.write("".join(f.readlines()[-40:]))
        die(f"installer exited with status {rc} (see {log})")
    rmtree(extract)

    dll = os.path.join(WINDOWS_ROOT, "bin", "csound7_64.dll")
    if not os.path.exists(dll):
        die(f"{dll} missing after install")
    print(f">> done: {dll}")


def main():
    global TAG
    if len(sys.argv) > 1:
        TAG = sys.argv[1]

    os.makedirs(VENDOR_DIR, exist_ok=True)
    if sys.platform == "darwin":
        vendor_macos()
    elif sys.platform.startswith("linux"):
        vendor_linux()
    elif sys.platform == "win32":
        vendor_windows()
    else:
        die(f"unsupported platform {sys.platform}")

    # Read by the Makefile to re-vendor when TAG changes.
    with open(os.path.join(VENDOR_DIR, ".tag"), "w", newline="\n") as f:
        f.write(f"{TAG}\n")


if __name__ == "__main__":
    main()

import os
import platform
import subprocess
from pathlib import Path

from Cython.Build import cythonize
from setuptools import Extension, setup

# ----------------------------------------------------------------------------
# helper funcs

def getenv(key: str, default: bool = False) -> bool:
    """convert '0','1' env values to bool {True, False}"""
    return bool(int(os.getenv(key, default)))

def get_min_osx_ver(platform, arch) -> str:
    min_osx_ver = os.getenv("MACOSX_DEPLOYMENT_TARGET")
    if not min_osx_ver:
        min_osx_ver = "10.9"
        if platform == "Darwin" and arch == "arm64":
            min_osx_ver = "11.0"
    return min_osx_ver

def get_homebrew_prefix() -> Path:
    try:
        prefix = subprocess.check_output('brew --prefix'.split(), encoding='utf8').strip()
    except FileNotFoundError:
        raise SystemExit("Homebrew requirded for macOS static build")
    return Path(prefix)

def check_static_libs(dep_lib_paths):
    fail=False
    msgs = []
    for p in dep_lib_paths:
        if os.path.exists(p):
            msgs.append(f"Found: {p}")
        else:
            msgs.append(f"Not Found: {p}")
            fail=True
    if fail:
        for m in msgs:
            print(m)
        raise SystemExit()

# ----------------------------------------------------------------------------
# VARS

VERSION = "0.0.1"

# ----------------------------------------------------------------------------
# OPTIONS (to be set as environment variables)

# set cycsound static or dynamic build here
STATIC = getenv("STATIC")

# ----------------------------------------------------------------------------
# COMMON

PLATFORM = platform.system()
INCLUDE_DIRS = []
LIBRARIES = []
LIBRARY_DIRS = []
EXTRA_OBJECTS = []

# ----------------------------------------------------------------------------
# PLATFORM-SPECIFIC CONFIGURATION

if PLATFORM == "Darwin":

    framework = Path("/Library/Frameworks/CsoundLib64.framework")
    INCLUDE_DIRS = [ str(framework / 'Headers') ]

    if STATIC:

        homebrew = get_homebrew_prefix()
        homebrew_lib = homebrew / 'lib'

        INCLUDE_DIRS.append(
            str(homebrew / 'include'),
        )

        csound_libs = [
            'libCsoundLib64.a',
            'libcsnd6.a',
        ]

        dep_libs = [
            'libsndfile.a',
            'libFLAC.a',
            'libopus.a',
            'libvorbis.a',
            'libvorbisenc.a',
            'libogg.a',
            'libmpg123.a',
            'libmp3lame.a',
        ]

        dep_lib_paths = [str(homebrew_lib / lib) for lib in dep_libs]
        check_static_libs(dep_lib_paths)
        EXTRA_OBJECTS = [str(framework / lib) for lib in csound_libs]
        EXTRA_OBJECTS.extend(dep_lib_paths)
        LIBRARY_DIRS = [str(homebrew_lib)]
        LIBRARIES = ['curl']

    else:

        os.environ['LDFLAGS'] = " ".join([
            "-framework CsoundLib64",
            "-F /Library/Frameworks",
        ])
        

elif PLATFORM == "Windows":
    base = Path("C:\\Program Files\\Csound6_x64")
    bin = base / 'bin'
    include = base / 'include' / 'csound'
    libdir = base / 'lib'
    INCLUDE_DIRS.append(str(include))
    LIBRARY_DIRS.append(str(libdir))
    LIBRARIES.extend([
        'csound64',
        'csnd6',
    ])

elif PLATFORM == "Linux":
    INCLUDE_DIRS.append("/usr/include/csound")
    LIBRARIES.extend([
        'csound64',
    ])

else:
    raise SystemExit("Platform not supported")

extensions = [
    Extension("cycsound", ["cycsound.pyx"],
        define_macros = [
            ('MYFLT', 'double'),
        ],
        include_dirs=INCLUDE_DIRS,
        libraries = LIBRARIES,
        library_dirs=LIBRARY_DIRS,
        extra_objects=EXTRA_OBJECTS,
    ),
]


setup(
    name="cycsound",
    description="csound wrapped by cython",
    ext_modules=cythonize(extensions, 
        compiler_directives={
            'language_level' : '3',
            'embedsignature': True,
        }),
)

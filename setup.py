import os
import platform
from pathlib import Path

from setuptools import setup, Extension

from Cython.Build import cythonize

PLATFORM = platform.system()
INCLUDE_DIRS = []
LIBRARIES = []
LIBRARY_DIRS = []

if PLATFORM == "Darwin":
    os.environ['LDFLAGS'] = " ".join([
        "-framework CsoundLib64",
        "-framework CoreFoundation",
        "-framework AudioUnit",
        "-framework AudioToolbox",
        "-framework CoreAudio",
        "-F /Library/Frameworks",
    ])
    INCLUDE_DIRS.append("/Library/Frameworks/CsoundLib64.framework/Headers")
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
    pass
else:
    pass

extensions = [
    Extension("csnd", ["csnd.pyx"],
        # define_macros = [
        #     ('PD', 1),
        # ],
        include_dirs=INCLUDE_DIRS,
        libraries = LIBRARIES,
        library_dirs=LIBRARY_DIRS,
    ),
]


setup(
    name="csound in cython",
    ext_modules=cythonize(extensions, 
        compiler_directives={
            'language_level' : '3',
            'embedsignature': True,
        }),
)

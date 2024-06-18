import os
# from distutils.core import setup
# from distutils.extension import Extension
from setuptools import setup, Extension


from Cython.Build import cythonize

os.environ['LDFLAGS'] = " ".join([
        "-framework CsoundLib64",
        "-framework CoreFoundation",
        "-framework AudioUnit",
        "-framework AudioToolbox",
        "-framework CoreAudio",
        "-F /Library/Frameworks",
])

extensions = [
    Extension("csnd", ["csnd.pyx"],
        # define_macros = [
        #     ('PD', 1),
        # ],
        include_dirs=[
            "/Library/Frameworks/CsoundLib64.framework/Headers",
        ],
        libraries = [
            'm',
            'dl',
            'pthread',
        ],
        library_dirs=[],
        extra_objects=[
        ],
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

cmake_minimum_required(VERSION 3.15...3.30)
project(${SKBUILD_PROJECT_NAME} VERSION ${SKBUILD_PROJECT_VERSION} LANGUAGES C)

find_package(Python REQUIRED COMPONENTS Interpreter Development.Module)

# Option for static linking (creates standalone wheel)
option(STATIC "Build with static Csound libraries" OFF)

# Platform-specific Csound configuration
if(APPLE)
    # macOS: Use the vendored Csound 7 CsoundLib64 framework. If it is missing,
    # fetch it automatically (over plain HTTPS, no GitHub account required) by
    # running scripts/vendor_csound7.sh.
    set(CSOUND_FRAMEWORK "${CMAKE_SOURCE_DIR}/vendor/CsoundLib64.framework")
    if(NOT EXISTS ${CSOUND_FRAMEWORK})
        message(STATUS "Vendored CsoundLib64 framework not found; fetching Csound 7 beta...")
        execute_process(
            COMMAND bash "${CMAKE_SOURCE_DIR}/scripts/vendor_csound7.sh"
            RESULT_VARIABLE VENDOR_RESULT)
        if(NOT VENDOR_RESULT EQUAL 0 OR NOT EXISTS ${CSOUND_FRAMEWORK})
            message(FATAL_ERROR
                "Failed to vendor the Csound 7 framework via "
                "scripts/vendor_csound7.sh. Run it manually and rebuild.")
        endif()
    endif()
    set(CSOUND_INCLUDE_DIR "${CSOUND_FRAMEWORK}/Headers")

    if(STATIC)
        message(FATAL_ERROR
            "Static linking against the vendored Csound 7 framework is not "
            "supported (it ships dynamic libraries only).")
        message(STATUS "Building with static Csound libraries")

        # Find Homebrew prefix
        execute_process(
            COMMAND brew --prefix
            OUTPUT_VARIABLE HOMEBREW_PREFIX
            OUTPUT_STRIP_TRAILING_WHITESPACE
            RESULT_VARIABLE BREW_RESULT
        )
        if(NOT BREW_RESULT EQUAL 0)
            message(FATAL_ERROR "Homebrew required for macOS static build")
        endif()
        message(STATUS "Homebrew prefix: ${HOMEBREW_PREFIX}")

        set(HOMEBREW_LIB "${HOMEBREW_PREFIX}/lib")
        set(HOMEBREW_INCLUDE "${HOMEBREW_PREFIX}/include")

        # Add Homebrew include path
        list(APPEND CSOUND_INCLUDE_DIR ${HOMEBREW_INCLUDE})

        # Static Csound libraries from framework
        set(CSOUND_STATIC_LIBS
            "${CSOUND_FRAMEWORK}/libCsoundLib64.a"
            "${CSOUND_FRAMEWORK}/libcsnd6.a"
        )

        # Static dependency libraries from Homebrew
        set(DEP_STATIC_LIBS
            "${HOMEBREW_LIB}/libsndfile.a"
            "${HOMEBREW_LIB}/libFLAC.a"
            "${HOMEBREW_LIB}/libopus.a"
            "${HOMEBREW_LIB}/libvorbis.a"
            "${HOMEBREW_LIB}/libvorbisenc.a"
            "${HOMEBREW_LIB}/libogg.a"
            "${HOMEBREW_LIB}/libmpg123.a"
            "${HOMEBREW_LIB}/libmp3lame.a"
        )

        # Verify all static libraries exist
        foreach(LIB ${CSOUND_STATIC_LIBS} ${DEP_STATIC_LIBS})
            if(NOT EXISTS ${LIB})
                message(FATAL_ERROR "Static library not found: ${LIB}")
            endif()
            message(STATUS "Found: ${LIB}")
        endforeach()

        # Combine all static libraries
        set(CSOUND_LIBRARIES ${CSOUND_STATIC_LIBS} ${DEP_STATIC_LIBS})

        # curl is kept dynamic
        find_library(CURL_LIB curl REQUIRED)
        list(APPEND CSOUND_LIBRARIES ${CURL_LIB})

        # macOS frameworks needed for static build
        set(MACOS_FRAMEWORKS
            "-framework Accelerate"
            "-framework AudioToolbox"
            "-framework CoreAudio"
            "-framework CoreMIDI"
            "-framework CoreFoundation"
        )
    else()
        # Dynamic linking against the vendored framework. Its install id has
        # been repointed to this absolute path by scripts/vendor_csound7.sh,
        # so no rpath is required at runtime.
        set(CSOUND_LIBRARIES "-framework CsoundLib64")
        set(CSOUND_FRAMEWORK_DIR "${CMAKE_SOURCE_DIR}/vendor")
    endif()

elseif(WIN32)
    # Windows: use a Csound 7 installation (the release ships an installer;
    # override CSOUND_ROOT if it was installed elsewhere).
    set(CSOUND_ROOT "C:/Program Files/Csound7_x64" CACHE PATH
        "Root of the Csound 7 installation")
    set(CSOUND_INCLUDE_DIR "${CSOUND_ROOT}/include/csound")
    set(CSOUND_LIBRARY_DIR "${CSOUND_ROOT}/lib")

    if(STATIC)
        message(FATAL_ERROR "Static linking not yet supported on Windows")
    endif()

    find_library(CSOUND_LIB csound64 PATHS ${CSOUND_LIBRARY_DIR} REQUIRED)
    set(CSOUND_LIBRARIES ${CSOUND_LIB})

elseif(UNIX)
    # Linux: use the vendored Csound 7 shared library. A distro `csound`
    # package is still Csound 6, whose host API this wrapper does not target,
    # so the Csound 7 release binaries are staged under vendor/ instead (and
    # fetched automatically when missing, as on macOS).
    set(CSOUND_VENDOR_LIB_DIR "${CMAKE_SOURCE_DIR}/vendor/lib")
    if(NOT EXISTS "${CSOUND_VENDOR_LIB_DIR}/libcsound64.so")
        message(STATUS "Vendored Csound 7 library not found; fetching Csound 7 beta...")
        execute_process(
            COMMAND bash "${CMAKE_SOURCE_DIR}/scripts/vendor_csound7.sh"
            RESULT_VARIABLE VENDOR_RESULT)
        if(NOT VENDOR_RESULT EQUAL 0
           OR NOT EXISTS "${CSOUND_VENDOR_LIB_DIR}/libcsound64.so")
            message(FATAL_ERROR
                "Failed to vendor the Csound 7 library via "
                "scripts/vendor_csound7.sh. Run it manually and rebuild.")
        endif()
    endif()

    # The Linux release carries no headers; use the repo-local copy, which
    # tracks the same Csound 7 tag.
    set(CSOUND_INCLUDE_DIR "${CMAKE_SOURCE_DIR}/include")

    if(STATIC)
        message(FATAL_ERROR "Static linking not yet supported on Linux")
    endif()

    set(CSOUND_LIBRARIES "${CSOUND_VENDOR_LIB_DIR}/libcsound64.so")

else()
    message(FATAL_ERROR "Unsupported platform")
endif()

# Cython transpilation
add_custom_command(
    OUTPUT _core.c
    COMMAND Python::Interpreter -m cython
        "${CMAKE_CURRENT_SOURCE_DIR}/src/cycsound/_core.pyx"
        -I "${CMAKE_CURRENT_SOURCE_DIR}/src/cycsound"
        --output-file _core.c
    DEPENDS
        src/cycsound/_core.pyx
        src/cycsound/csound.pxd
    COMMENT "Running Cython on _core.pyx"
)

# Build the extension module
python_add_library(_core MODULE _core.c WITH_SOABI)

# Set include directories
target_include_directories(_core PRIVATE ${CSOUND_INCLUDE_DIR})

# Build against the double-precision (cs_float == double) Csound API
target_compile_definitions(_core PRIVATE USE_DOUBLE)

# Link Csound library
if(APPLE)
    if(STATIC)
        target_link_libraries(_core PRIVATE ${CSOUND_LIBRARIES} ${MACOS_FRAMEWORKS})
        target_link_directories(_core PRIVATE ${HOMEBREW_LIB})
    else()
        target_link_options(_core PRIVATE "-F${CSOUND_FRAMEWORK_DIR}")
        target_link_libraries(_core PRIVATE ${CSOUND_LIBRARIES})
    endif()
elseif(WIN32)
    target_link_directories(_core PRIVATE ${CSOUND_LIBRARY_DIR})
    target_link_libraries(_core PRIVATE ${CSOUND_LIBRARIES})
else()
    target_link_libraries(_core PRIVATE ${CSOUND_LIBRARIES})
    # Bake in the vendored library location so the extension resolves
    # libcsound64.so without LD_LIBRARY_PATH.
    set_target_properties(_core PROPERTIES
        BUILD_RPATH "${CSOUND_VENDOR_LIB_DIR}"
        INSTALL_RPATH "${CSOUND_VENDOR_LIB_DIR}")
endif()

# Install the extension module
install(TARGETS _core DESTINATION cycsound)

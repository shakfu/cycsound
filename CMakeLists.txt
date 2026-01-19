cmake_minimum_required(VERSION 3.15...3.30)
project(${SKBUILD_PROJECT_NAME} VERSION ${SKBUILD_PROJECT_VERSION} LANGUAGES C)

find_package(Python REQUIRED COMPONENTS Interpreter Development.Module)

# Option for static linking (creates standalone wheel)
option(STATIC "Build with static Csound libraries" OFF)

# Platform-specific Csound configuration
if(APPLE)
    # macOS: Use CsoundLib64 framework
    set(CSOUND_FRAMEWORK "/Library/Frameworks/CsoundLib64.framework")
    if(NOT EXISTS ${CSOUND_FRAMEWORK})
        message(FATAL_ERROR "CsoundLib64 framework not found at ${CSOUND_FRAMEWORK}")
    endif()
    set(CSOUND_INCLUDE_DIR "${CSOUND_FRAMEWORK}/Headers")

    if(STATIC)
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
        # Dynamic linking
        set(CSOUND_LIBRARIES "-framework CsoundLib64")
        set(CSOUND_FRAMEWORK_DIR "/Library/Frameworks")
    endif()

elseif(WIN32)
    # Windows: Use Csound6_x64 installation
    set(CSOUND_ROOT "C:/Program Files/Csound6_x64")
    set(CSOUND_INCLUDE_DIR "${CSOUND_ROOT}/include/csound")
    set(CSOUND_LIBRARY_DIR "${CSOUND_ROOT}/lib")

    if(STATIC)
        message(FATAL_ERROR "Static linking not yet supported on Windows")
    endif()

    find_library(CSOUND_LIB csound64 PATHS ${CSOUND_LIBRARY_DIR} REQUIRED)
    set(CSOUND_LIBRARIES ${CSOUND_LIB})

elseif(UNIX)
    # Linux: Use system csound
    set(CSOUND_INCLUDE_DIR "/usr/include/csound")

    if(STATIC)
        message(FATAL_ERROR "Static linking not yet supported on Linux")
    endif()

    find_library(CSOUND_LIB csound64 REQUIRED)
    set(CSOUND_LIBRARIES ${CSOUND_LIB})

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

# Define MYFLT as double (matches original setup.py)
target_compile_definitions(_core PRIVATE MYFLT=double USE_DOUBLE)

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
endif()

# Install the extension module
install(TARGETS _core DESTINATION cycsound)

cmake_minimum_required(VERSION 3.15...3.30)
project(${SKBUILD_PROJECT_NAME} VERSION ${SKBUILD_PROJECT_VERSION} LANGUAGES C)

find_package(Python REQUIRED COMPONENTS Interpreter Development.Module)

# Platform-specific Csound configuration
if(APPLE)
    # macOS: Use the vendored Csound 7 CsoundLib64 framework. If it is missing,
    # fetch it automatically (over plain HTTPS, no GitHub account required) by
    # running scripts/vendor_csound7.sh.
    set(CSOUND_FRAMEWORK "${CMAKE_SOURCE_DIR}/vendor/CsoundLib64.framework")
    if(NOT EXISTS ${CSOUND_FRAMEWORK}
       OR NOT EXISTS "${CMAKE_SOURCE_DIR}/vendor/plugins"
       OR NOT EXISTS "${CMAKE_SOURCE_DIR}/vendor/deps")
        message(STATUS "Vendored CsoundLib64 framework or plugins not found; fetching Csound 7...")
        execute_process(
            COMMAND ${CMAKE_COMMAND} -E env "CMAKE=${CMAKE_COMMAND}"
                bash "${CMAKE_SOURCE_DIR}/scripts/vendor_csound7.sh"
            RESULT_VARIABLE VENDOR_RESULT)
        if(NOT VENDOR_RESULT EQUAL 0 OR NOT EXISTS ${CSOUND_FRAMEWORK})
            message(FATAL_ERROR
                "Failed to vendor the Csound 7 framework via "
                "scripts/vendor_csound7.sh. Run it manually and rebuild.")
        endif()
    endif()
    set(CSOUND_INCLUDE_DIR "${CSOUND_FRAMEWORK}/Headers")

    # Dynamic linking against the vendored framework. Its install id has
    # been repointed to this absolute path by scripts/vendor_csound7.sh,
    # so no rpath is required at runtime.
    set(CSOUND_LIBRARIES "-framework CsoundLib64")
    set(CSOUND_FRAMEWORK_DIR "${CMAKE_SOURCE_DIR}/vendor")

elseif(WIN32)
    # Windows: use a Csound 7 installation (the release ships an installer;
    # override CSOUND_ROOT if it was installed elsewhere).
    set(CSOUND_ROOT "C:/Program Files/Csound7_x64" CACHE PATH
        "Root of the Csound 7 installation")
    set(CSOUND_INCLUDE_DIR "${CSOUND_ROOT}/include/csound")
    set(CSOUND_LIBRARY_DIR "${CSOUND_ROOT}/lib")
    set(CSOUND_PLUGIN_DIR "${CSOUND_ROOT}/plugins64" CACHE PATH
        "Directory of the Csound 7 plugin DLLs to ship")

    # csound64 is Csound 6's name; matching it could link the wrong major.
    find_library(CSOUND_LIB csound7_64 PATHS ${CSOUND_LIBRARY_DIR} REQUIRED)
    set(CSOUND_LIBRARIES ${CSOUND_LIB})

elseif(UNIX)
    # Linux: use the vendored Csound 7 shared library. A distro `csound`
    # package is still Csound 6, whose host API this wrapper does not target,
    # so the Csound 7 release binaries are staged under vendor/ instead (and
    # fetched automatically when missing, as on macOS).
    set(CSOUND_VENDOR_LIB_DIR "${CMAKE_SOURCE_DIR}/vendor/lib")
    if(NOT EXISTS "${CSOUND_VENDOR_LIB_DIR}/libcsound64.so")
        message(STATUS "Vendored Csound 7 library not found; fetching Csound 7...")
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
    target_link_options(_core PRIVATE "-F${CSOUND_FRAMEWORK_DIR}")
    target_link_libraries(_core PRIVATE ${CSOUND_LIBRARIES})
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

# Ship the Csound plugins: the realtime audio/MIDI drivers on all platforms,
# and on Linux the opcode library too.
if(WIN32)
    install(DIRECTORY "${CSOUND_PLUGIN_DIR}/"
        DESTINATION cycsound/plugins
        FILES_MATCHING PATTERN "*.dll")
else()
    install(DIRECTORY "${CMAKE_SOURCE_DIR}/vendor/plugins/"
        DESTINATION cycsound/plugins
        FILES_MATCHING PATTERN "*.so" PATTERN "*.dylib")
endif()

# Same public-suffix snapshot as upstream, with built-in data and no ICU DLL.
ExternalProject_Add(libpsl
    GIT_REPOSITORY https://github.com/rockdaboot/libpsl.git
    GIT_REMOTE_NAME origin
    GIT_TAG aa3a80e18f25caf3916636c8668dcc0fff7c016d
    GIT_RESET aa3a80e18f25caf3916636c8668dcc0fff7c016d
    SOURCE_DIR ${SOURCE_LOCATION}
    GIT_CLONE_FLAGS "--filter=tree:0"
    GIT_SUBMODULES list
    UPDATE_COMMAND ""
    # The built-in PSL is a pinned submodule, not part of libpsl's own tree.
    # Also initialize it here for source caches cloned with submodules disabled.
    CONFIGURE_COMMAND ${EXEC} git -C <SOURCE_DIR> submodule update --init list
    COMMAND ${EXEC} echo > <SOURCE_DIR>/tools/meson.build
    COMMAND ${EXEC} CONF=1 meson setup <BINARY_DIR> <SOURCE_DIR>
        --prefix=${MINGW_INSTALL_PREFIX}
        --libdir=${MINGW_INSTALL_PREFIX}/lib
        --cross-file=${MESON_CROSS}
        --buildtype=release
        --default-library=static
        -Dtests=false
        -Druntime=no
    BUILD_COMMAND ${EXEC} ninja -C <BINARY_DIR> src/suffixes_dafsa.h
    INSTALL_COMMAND ${EXEC} ninja -C <BINARY_DIR> install
    LOG_DOWNLOAD 1 LOG_UPDATE 1 LOG_CONFIGURE 1 LOG_BUILD 1 LOG_INSTALL 1
)

force_rebuild_git(libpsl)
force_meson_configure(libpsl)
cleanup(libpsl install)

# c-ares v1.34.8 for asynchronous DNS and HTTPS records in libcurl.
ExternalProject_Add(c-ares
    GIT_REPOSITORY https://github.com/c-ares/c-ares.git
    GIT_REMOTE_NAME origin
    GIT_TAG c7a3138dcfe3bb0eaaf10c0c24c36dc66dc790ab
    GIT_RESET c7a3138dcfe3bb0eaaf10c0c24c36dc66dc790ab
    SOURCE_DIR ${SOURCE_LOCATION}
    GIT_CLONE_FLAGS "--filter=tree:0"
    GIT_SUBMODULES ""
    UPDATE_COMMAND ""
    CONFIGURE_COMMAND ${EXEC} CONF=1 cmake -S <SOURCE_DIR> -B <BINARY_DIR>
        -G Ninja
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_TOOLCHAIN_FILE=${TOOLCHAIN_FILE}
        -DCMAKE_INSTALL_PREFIX=${MINGW_INSTALL_PREFIX}
        -DCMAKE_INSTALL_LIBDIR=lib
        -DBUILD_SHARED_LIBS=OFF
        -DCARES_BUILD_TOOLS=OFF
        -DCARES_BUILD_TESTS=OFF
        -DCARES_SHARED=OFF
        -DCARES_STATIC=ON
        -DCARES_INSTALL=ON
    BUILD_COMMAND ${EXEC} ninja -C <BINARY_DIR>
    INSTALL_COMMAND ${EXEC} ninja -C <BINARY_DIR> install
    LOG_DOWNLOAD 1 LOG_UPDATE 1 LOG_CONFIGURE 1 LOG_BUILD 1 LOG_INSTALL 1
)

force_rebuild_git(c-ares)
cleanup(c-ares install)

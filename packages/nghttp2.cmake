# nghttp2 v1.70.0. Pin the source so cached CI builds use the same HTTP/2 ABI.
ExternalProject_Add(nghttp2
    GIT_REPOSITORY https://github.com/nghttp2/nghttp2.git
    GIT_REMOTE_NAME origin
    GIT_TAG 85e300c79fb6dbcfa9c1013215c8710c1c2cd3d2
    GIT_RESET 85e300c79fb6dbcfa9c1013215c8710c1c2cd3d2
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
        -DBUILD_STATIC_LIBS=ON
        -DENABLE_LIB_ONLY=ON
        -DENABLE_APP=OFF
        -DENABLE_EXAMPLES=OFF
        -DENABLE_HPACK_TOOLS=OFF
        -DENABLE_DOC=OFF
        -DBUILD_TESTING=OFF
    BUILD_COMMAND ${EXEC} ninja -C <BINARY_DIR>
    INSTALL_COMMAND ${EXEC} ninja -C <BINARY_DIR> install
    LOG_DOWNLOAD 1 LOG_UPDATE 1 LOG_CONFIGURE 1 LOG_BUILD 1 LOG_INSTALL 1
)

force_rebuild_git(nghttp2)
cleanup(nghttp2 install)

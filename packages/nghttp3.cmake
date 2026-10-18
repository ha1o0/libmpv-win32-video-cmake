# nghttp3 v1.18.0; only the HTTP/3 library and its sfparse submodule are needed.
ExternalProject_Add(nghttp3
    GIT_REPOSITORY https://github.com/ngtcp2/nghttp3.git
    GIT_REMOTE_NAME origin
    GIT_TAG dbfc24286138cb0b6490160e7ca87fe1ce6722a0
    GIT_RESET dbfc24286138cb0b6490160e7ca87fe1ce6722a0
    SOURCE_DIR ${SOURCE_LOCATION}
    GIT_CLONE_FLAGS "--filter=tree:0"
    GIT_SUBMODULES lib/sfparse
    UPDATE_COMMAND ""
    CONFIGURE_COMMAND ${EXEC} CONF=1 cmake -S <SOURCE_DIR> -B <BINARY_DIR>
        -G Ninja
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_TOOLCHAIN_FILE=${TOOLCHAIN_FILE}
        -DCMAKE_INSTALL_PREFIX=${MINGW_INSTALL_PREFIX}
        -DCMAKE_INSTALL_LIBDIR=lib
        -DBUILD_SHARED_LIBS=OFF
        -DENABLE_LIB_ONLY=ON
        -DENABLE_STATIC_LIB=ON
        -DENABLE_SHARED_LIB=OFF
        -DBUILD_TESTING=OFF
    BUILD_COMMAND ${EXEC} ninja -C <BINARY_DIR>
    INSTALL_COMMAND ${EXEC} ninja -C <BINARY_DIR> install
    LOG_DOWNLOAD 1 LOG_UPDATE 1 LOG_CONFIGURE 1 LOG_BUILD 1 LOG_INSTALL 1
)

force_rebuild_git(nghttp3)
cleanup(nghttp3 install)

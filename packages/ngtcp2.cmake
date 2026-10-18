# ngtcp2 v1.25.0 with OpenSSL's QUIC TLS API (libngtcp2_crypto_ossl).
ExternalProject_Add(ngtcp2
    DEPENDS openssl
    GIT_REPOSITORY https://github.com/ngtcp2/ngtcp2.git
    GIT_REMOTE_NAME origin
    GIT_TAG f9e9ff01ad2c8116bc09de4f644b0028a61486a6
    GIT_RESET f9e9ff01ad2c8116bc09de4f644b0028a61486a6
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
        -DENABLE_LIB_ONLY=ON
        -DENABLE_STATIC_LIB=ON
        -DENABLE_SHARED_LIB=OFF
        -DENABLE_OPENSSL=ON
        -DOPENSSL_USE_STATIC_LIBS=ON
        -DBUILD_TESTING=OFF
        "-DCMAKE_C_FLAGS='-lz -lbrotlienc -lbrotlidec -lbrotlicommon -lzstd -lcrypt32'"
    BUILD_COMMAND ${EXEC} ninja -C <BINARY_DIR>
    INSTALL_COMMAND ${EXEC} ninja -C <BINARY_DIR> install
    LOG_DOWNLOAD 1 LOG_UPDATE 1 LOG_CONFIGURE 1 LOG_BUILD 1 LOG_INSTALL 1
)

force_rebuild_git(ngtcp2)
cleanup(ngtcp2 install)

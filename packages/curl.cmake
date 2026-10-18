# curl 8.23.0: static transport matching upstream's HTTP/2 + HTTP/3 features.
ExternalProject_Add(curl
    DEPENDS
        nghttp2
        nghttp3
        ngtcp2
        c-ares
        libpsl
        libssh
        openssl
        zlib
        brotli
        zstd
    GIT_REPOSITORY https://github.com/curl/curl.git
    GIT_REMOTE_NAME origin
    GIT_TAG 3163ec065643ba20709f190111f42c3e1fe95273
    GIT_RESET 3163ec065643ba20709f190111f42c3e1fe95273
    SOURCE_DIR ${SOURCE_LOCATION}
    GIT_CLONE_FLAGS "--filter=tree:0"
    PATCH_COMMAND ${EXEC} git am --3way ${CMAKE_CURRENT_SOURCE_DIR}/curl-0001-libssh-include-scp-declarations.patch
    UPDATE_COMMAND ""
    CONFIGURE_COMMAND ${EXEC} CONF=1 cmake -S <SOURCE_DIR> -B <BINARY_DIR>
        -G Ninja
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_TOOLCHAIN_FILE=${TOOLCHAIN_FILE}
        -DCMAKE_INSTALL_PREFIX=${MINGW_INSTALL_PREFIX}
        -DCMAKE_INSTALL_LIBDIR=lib
        -DBUILD_SHARED_LIBS=OFF
        -DBUILD_STATIC_LIBS=ON
        -DBUILD_CURL_EXE=OFF
        -DBUILD_TESTING=OFF
        -DBUILD_EXAMPLES=OFF
        -DBUILD_LIBCURL_DOCS=OFF
        -DBUILD_MISC_DOCS=OFF
        -DENABLE_CURL_MANUAL=OFF
        -DCURL_USE_SCHANNEL=OFF
        -DCURL_USE_OPENSSL=ON
        -DCURL_USE_MBEDTLS=OFF
        -DOPENSSL_USE_STATIC_LIBS=ON
        -DCURL_CA_NATIVE=ON
        -DCURL_CA_BUNDLE=none
        -DCURL_CA_PATH=none
        -DUSE_NGHTTP2=ON
        -DNGHTTP2_USE_STATIC_LIBS=ON
        -DCMAKE_REQUIRE_FIND_PACKAGE_NGHTTP2=ON
        -DUSE_NGTCP2=ON
        -DNGTCP2_USE_STATIC_LIBS=ON
        -DNGHTTP3_USE_STATIC_LIBS=ON
        -DENABLE_ARES=ON
        -DCARES_USE_STATIC_LIBS=ON
        -DENABLE_THREADED_RESOLVER=ON
        -DENABLE_UNICODE=ON
        -DCURL_WINDOWS_SSPI=ON
        -DUSE_ECH=ON
        -DUSE_HTTPSRR=ON
        -DUSE_SSLS_EXPORT=ON
        -DUSE_PROXY_HTTP3=ON
        -DCURL_USE_PKGCONFIG=ON
        -DCMAKE_DISABLE_FIND_PACKAGE_Perl=ON
        "-DCMAKE_C_FLAGS='-DNGHTTP3_STATICLIB -DNGHTTP2_STATICLIB -DNGTCP2_STATICLIB -lz -lbrotlienc -lbrotlidec -lbrotlicommon -lzstd -lcrypt32 -lsecur32'"
        -DCURL_ZLIB=ON
        -DCURL_BROTLI=ON
        -DCURL_ZSTD=ON
        -DUSE_WIN32_IDN=ON
        -DUSE_LIBIDN2=OFF
        -DCURL_USE_LIBPSL=ON
        -DCURL_USE_LIBSSH2=OFF
        -DCURL_USE_LIBSSH=ON
        -DLIBSSH_USE_STATIC_LIBS=ON
    BUILD_COMMAND ${EXEC} ninja -C <BINARY_DIR>
    INSTALL_COMMAND ${EXEC} ninja -C <BINARY_DIR> install
    LOG_DOWNLOAD 1 LOG_UPDATE 1 LOG_CONFIGURE 1 LOG_BUILD 1 LOG_INSTALL 1
)

# Curl may otherwise silently configure without nghttp2. Check the installed
# target's metadata before mpv can consume it; no Windows executable is run here.
ExternalProject_Add_Step(curl verify-features
    DEPENDEES install
    COMMAND ${CMAKE_COMMAND}
        -DCURL_PC=${MINGW_INSTALL_PREFIX}/lib/pkgconfig/libcurl.pc
        -DCURL_CONFIG=${MINGW_INSTALL_PREFIX}/bin/curl-config
        -P ${PROJECT_SOURCE_DIR}/cmake/verify_curl_features.cmake
    LOG 1
)

force_rebuild_git(curl)
# Old source caches can still be on a tracking branch. Detach at our pin before
# patching even when that branch has not advanced since the previous CI run.
ExternalProject_Add_Step(curl pin-source
    INDEPENDENT TRUE
    DEPENDEES update write-head
    DEPENDERS patch
    COMMAND ${EXEC} git -C <SOURCE_DIR> checkout --detach --force 3163ec065643ba20709f190111f42c3e1fe95273
    LOG 1
)
cleanup(curl verify-features)

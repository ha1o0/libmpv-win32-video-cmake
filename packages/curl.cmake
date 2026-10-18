# curl 8.23.0: static transport for mpv, with HTTP/2 and Windows certificate trust.
ExternalProject_Add(curl
    DEPENDS
        nghttp2
        zlib
        brotli
        zstd
    GIT_REPOSITORY https://github.com/curl/curl.git
    GIT_REMOTE_NAME origin
    GIT_TAG 3163ec065643ba20709f190111f42c3e1fe95273
    GIT_RESET 3163ec065643ba20709f190111f42c3e1fe95273
    SOURCE_DIR ${SOURCE_LOCATION}
    GIT_CLONE_FLAGS "--filter=tree:0"
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
        -DCURL_USE_SCHANNEL=ON
        -DCURL_USE_OPENSSL=OFF
        -DCURL_USE_MBEDTLS=OFF
        -DUSE_NGHTTP2=ON
        -DNGHTTP2_USE_STATIC_LIBS=ON
        -DCMAKE_REQUIRE_FIND_PACKAGE_NGHTTP2=ON
        -DCURL_ZLIB=ON
        -DCURL_BROTLI=ON
        -DCURL_ZSTD=ON
        -DUSE_WIN32_IDN=ON
        -DUSE_LIBIDN2=OFF
        -DCURL_USE_LIBPSL=OFF
        -DCURL_USE_LIBSSH2=OFF
        -DCURL_USE_LIBSSH=OFF
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
cleanup(curl verify-features)

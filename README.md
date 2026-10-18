# CMake-based MinGW-w64 Cross Toolchain

This thing’s primary use is to build Windows binaries of mpv.

Alternatively, you can download the builds from [here](https://sourceforge.net/projects/mpv-player-windows/files/).

## Prerequisites

 -  You should also install Ninja and use CMake’s Ninja build file generator.
    It’s not only much faster than GNU Make, but also far less error-prone,
    which is important for this project because CMake’s ExternalProject module
    tends to generate makefiles which confuse GNU Make’s jobserver thingy.

 -  As a build environment, any modern Linux distribution *should* work.

-   Compiling on Cygwin / MSYS2 is supported, but it tends to be slower
    than compiling on Linux.

## Setup Build Environment
### Manjaro / Arch Linux

These packages need to be installed first before compiling mpv:

    pacman -S git gyp mercurial subversion ninja cmake meson ragel yasm nasm asciidoc enca gperf unzip p7zip gcc-multilib clang lld libc++ libc++abi python-pip curl lib32-gcc-libs lib32-glib2 mimalloc ccache
    
    pip3 install rst2pdf mako jsonschema

    pacman -S llvm # needed for building LLVM PGO

### Ubuntu Linux / WSL (Windows 10)

    apt-get install build-essential checkinstall bison flex gettext git mercurial subversion ninja-build gyp cmake yasm nasm automake pkgconf libtool libtool-bin gcc-multilib g++-multilib clang lld libc++1 libc++abi1 libgmp-dev libmpfr-dev libmpc-dev libgcrypt-dev gperf ragel texinfo autopoint re2c asciidoc python3-pip docbook2x unzip p7zip-full curl mimalloc ccache

    pip3 install rst2pdf meson mako jsonschema

**Note:**

* Use [apt-fast](https://github.com/ilikenwf/apt-fast) if apt-get is too slow.
* It is advised to use bash over dash. Set `sudo ln -sf /bin/bash /bin/sh`. Revert back by `sudo ln -sf /bin/dash /bin/sh`.
* On WSL platform, compiling 32bit requires qemu. Refer to [this](https://github.com/Microsoft/WSL/issues/2468#issuecomment-374904520).
* To update package installed by pip, run `pip3 install <package> --upgrade`.

### Cygwin

Download Cygwin installer and run:

    setup-x86_64.exe -R "C:\cygwin64" -q --packages="bash,binutils,bzip2,cygwin,gcc-core,gcc-g++,cygwin32-gcc-core,cygwin32-gcc-g++,gzip,m4,pkgconf,make,unzip,zip,diffutils,wget,git,patch,cmake,gperf,yasm,enca,asciidoc,bison,flex,gettext-devel,mercurial,python-devel,python-docutils,docbook2X,texinfo,libmpfr-devel,libgmp-devel,libmpc-devel,libtool,autoconf2.5,automake,automake1.9,libxml2-devel,libxslt-devel,meson,libunistring5"

Additionally, some packages, `re2c`, `ninja`, `ragel`, `gyp`, `rst2pdf`, `nasm` need to be [installed manually](https://gist.github.com/shinchiro/705b0afcc7b6c0accffba1bedb067abf).

### MSYS2

Install MSYS2 and run it via `MSYS2 MSYS` shortcut.
Don't use `MSYS2 MinGW 32-bit` or `MSYS2 MinGW 64-bit` shortcuts, that's important!

These packages need to be installed first before compiling mpv:

    pacman -S base-devel cmake gcc yasm nasm git mercurial subversion gyp tar gmp-devel mpc-devel mpfr-devel python zlib-devel unzip zip p7zip meson libunistring5

Don't install anything from the `mingw32` and `mingw64` repositories,
it's better to completely disable them in `/etc/pacman.conf` just to be safe.

Additionally, some packages, `re2c`, `ninja`, `ragel`, `libjpeg`, `rst2pdf`, `jinja2` need to be [installed manually](https://gist.github.com/shinchiro/705b0afcc7b6c0accffba1bedb067abf).


## Compiling with GCC

Example:

    cmake -DTARGET_ARCH=x86_64-w64-mingw32 \
    -DGCC_ARCH=x86-64-v3 \
    -DSINGLE_SOURCE_LOCATION="/home/user/packages" \
    -DRUSTUP_LOCATION="/home/user/install_rustup" \
    -G Ninja -B build64 -S mpv-winbuild-cmake

This cmake command will create `build64` folder for `x86_64-w64-mingw32`. Set `-DTARGET_ARCH=i686-w64-mingw32` for compiling 32-bit.

`-DGCC_ARCH=x86-64-v3` will set `-march` option when compiling gcc with `x86-64-v3` instructions. Other value like `native`, `znver3` should work too.

Enter `build64` folder and build toolchain once. By default, it will be installed in `install` folder.

    ninja download # download all packages at once (optional)
    ninja gcc      # build gcc only once (take around ~20 minutes)
    ninja mpv      # build mpv and all its dependencies

On **WSL2**, you might see it stuck with 100% disk usage and never finished. See [below](#wsl-workaround).

The final `build64` folder's size will be around ~3GB.

## Building Software (Second Time)

To build mpv for a second time:

    ninja update # perform git pull on all packages that used git

After that, build mpv as usual:

    ninja mpv

## mpv gpu-next fork

This branch builds mpv from `https://github.com/ha1o0/mpv.git`, branch `zcopy`, by default. Override it locally with:

    cmake -DMPV_GIT_REPOSITORY="https://github.com/ha1o0/mpv.git" \
    -DMPV_GIT_TAG="zcopy" \
    ...

This repository's GitHub Actions workflows upload `libmpv-<arch>-dev` artifacts containing `libmpv-2.dll`, `libmpv.dll.a`, and mpv headers for downstream consumers such as bota/media-kit.

The default GitHub Actions target list is `["x86_64"]`. To build more clang targets later, run the workflow with:

    ["x86_64","x86_64_v3","aarch64"]

`x86_64_v3` is a modern CPU baseline build, and `aarch64` is for Windows ARM64. `i686` is still supported by the scripts but is not part of the default bota build.

### Windows HTTP/2 and HTTP/3 transport

The fork build explicitly enables mpv's libcurl stream backend. It builds pinned
curl 8.23.0, nghttp2 1.70.0, nghttp3 1.18.0, ngtcp2 1.25.0 and c-ares 1.34.8
as static libraries. OpenSSL and libpsl use the same pinned snapshots as
upstream mpv-winbuild-cmake (`1f8d2e76255abc48f0456d9be99b4cab9c6566e6`).
The OpenSSL pin is a 4.1.0-dev snapshot, matching upstream rather than a floating
development branch; validate the rebuilt FFmpeg/libssh TLS paths as well.
OpenSSL replaces Schannel for HTTP/3 and ECH; Windows certificate trust remains
enabled with `CURL_CA_NATIVE`. The build also enables upstream's HTTPS DNS
records, SSL session export, HTTP/3 proxy support, SSPI, Unicode, libpsl and
libssh. zlib, brotli and zstd support remain available. No separate `curl.exe`
or networking DLLs are needed in the downstream app package.
The installed target metadata is checked for these features and static-link
dependencies before mpv builds. Missing capabilities fail the build.

Use the **mpv clang** workflow with `build_targets=["x86_64"]` initially. Leave
`mpv_tarball`, `sourceforge`, `github_release` and `run_gcc` disabled to build the
custom `zcopy` kernel and collect the `libmpv-x86_64-dev` test artifact only.
The existing compiler/toolchain caches can be reused; leave the custom command
field empty. New dependencies participate in `download`/`update`. OpenSSL's
explicit QUIC/ECH configuration also invalidates an older cached configuration.
FFmpeg and libssh may rebuild against the pinned OpenSSL, but their feature
configuration and FFmpeg's fixed revision are unchanged. The fork's video/render
patches are unchanged.

At runtime, verify the `[curl]` stream-open log and HTTP/2 negotiation on a
compatible HTTPS server. HTTP/3 is a compiled capability, not a guarantee that
`curl-http-version=auto` uses QUIC. Test with `curl-http-version=3` to allow
fallback to HTTP/2 or HTTP/1.1; `3only` requires HTTP/3 and is for diagnostics.
Ordinary HTTP proxies may not carry QUIC. The mpv build applies a curl routing
patch: an explicitly empty `http-proxy` disables environment proxies, and an
explicit proxy is not bypassed by `NO_PROXY`. Leaving the option unset retains
libcurl's environment behavior. This patch must be in the build used by the app.
The second mpv patch honors `network-timeout` for inactive header/body reads and
caps connect timeout by it, excluding ring-buffer backpressure. Optional
`curl-reconnect-streamed=yes` permits bounded unseekable HTTP reconnects;
`curl-retry-delay-max=5` schedules 1/3/5-second backoff without stalling other
transfers. Closing, cancellation and seeking retire pending retries. The app
checks these options before enabling curl, retaining FFmpeg on incomplete cores.
`curl-enabled=no` selects the existing FFmpeg transport for A/B
testing. The upstream release-tarball build path is unchanged and is not the
custom-kernel test path. Validate playback, proxy/authentication, subtitles,
seek/resume, cancellation, hardware decoding, HDR and gpu-next before adoption.

Focused native policy test (requires Python, CMake, a C11 compiler and libcurl):

```sh
python tests/test_curl_network_policy.py --mpv-source /path/to/mpv
```

For a Windows static libcurl installation, add `--curl-prefix /path/to/prefix`.
This tests actual patched C functions against local HTTP fixtures, not a full
mpv cross build. It does not modify the supplied source checkout.

## Compiling with Clang

Supported target architecture (`TARGET_ARCH`) with clang is: `x86_64-w64-mingw32` , `i686-w64-mingw32` , `aarch64-w64-mingw32`. The `aarch64` are untested.

Example:

    cmake -DTARGET_ARCH=x86_64-w64-mingw32 \
    -DCMAKE_INSTALL_PREFIX="/home/user/clang_root" \
    -DCOMPILER_TOOLCHAIN=clang \
    -DGCC_ARCH=x86-64-v3 \
    -DSINGLE_SOURCE_LOCATION="/home/user/packages" \
    -DRUSTUP_LOCATION="/home/user/install_rustup" \
    -DMINGW_INSTALL_PREFIX="/home/user/build_x86_64_v3/x86_64_v3-w64-mingw32" \
    -G Ninja -B build_x86_64_v3 -S mpv-winbuild-cmake

The cmake command will create `clang_root` as clang sysroot where llvm tools installed. `build_x86_64` is build directory to compiling packages.

    cd build_x86_64
    ninja llvm       # build LLVM (take around ~2 hours)
    ninja rustup     # build rust toolchain
    ninja llvm-clang # build clang on specified target
    ninja mpv        # build mpv and all its dependencies

If you want add another target (ex. `i686-w64-mingw32`), change `TARGET_ARCH` and build folder.

    cmake -DTARGET_ARCH=i686-w64-mingw32 \
    -DCMAKE_INSTALL_PREFIX="/home/user/clang_root" \
    -DCOMPILER_TOOLCHAIN=clang \
    -DSINGLE_SOURCE_LOCATION="/home/user/packages" \
    -DRUSTUP_LOCATION="/home/user/install_rustup" \
    -DMINGW_INSTALL_PREFIX="/home/user/build_i686/i686-w64-mingw32" \
    -G Ninja -B build_i686 -S mpv-winbuild-cmake
    cd build_i686
    ninja llvm-clang # same as above

If you've changed `GCC_ARCH` option, you need to run:

    ninja rebuild_cache

to update flags which will pass on gcc, g++ and etc.

## Available Commands

| Commands                   | Description |
| -------------------------- | ----------- |
| ninja package              | compile a package |
| ninja clean                | remove all stamp files in all packages. |
| ninja download             | Download all packages' sources at once without compiling. |
| ninja update               | Update all git repos. When a package pulls new changes, all of its stamp files will be deleted and will be forced rebuild. If there is no change, it will not remove the stamp files and no rebuild occur. Use this instead of `ninja clean` if you don't want to rebuild everything in the next run. |
| ninja package-fullclean    | Remove all stamp files of a package. |
| ninja package-liteclean    | Remove build, clean stamp files only. This will skip re-configure in the next running `ninja package` (after the first compile). Updating repo or patching need to do manually. Ideally, all `DEPENDS` targets in `package.cmake` should be temporarily commented or deleted. Might be useful in some cases. |
| ninja package-removebuild  | Remove 'build' directory of a package. |
| ninja package-removeprefix | Remove 'prefix' directory. |
| ninja package-force-update | Update a package. Only git repo will be updated. |

`package` is package's name found in `packages` folder.

## Information about packages

- Git/Hg
    - ANGLE
    - FFmpeg
    - xz
    - x264
    - x265 (multilib)
    - uchardet
    - rubberband (with libsamplerate)
    - opus
    - openal-soft
    - mpv
    - luajit
    - libvpx
    - libwebp
    - libpng
    - libsoxr
    - libzimg (with graphengine)
    - libdvdread
    - libdvdnav
    - libdvdcss
    - libudfread
    - libbluray
    - libunibreak
    - libass
    - libmysofa
    - lcms2
    - lame
    - harfbuzz
    - game-music-emu
    - freetype2
    - flac
    - opus-tools
    - mujs
    - libarchive
    - libjpeg
    - shaderc (with spirv-headers, spirv-tools, glslang)
    - vulkan-header
    - vulkan
    - spirv-cross
    - fribidi
    - ~~nettle~~
    - curl
    - libxml2
    - amf-headers
    - avisynth-headers
    - nvcodec-headers
    - libvpl
    - megasdk (with termcap, readline, cryptopp, sqlite, libuv, libsodium)
    - aom
    - dav1d
    - libplacebo (with glad, fast_float, xxhash)
    - fontconfig
    - libbs2b
    - libssh
    - libsrt
    - libjxl (with brotli, highway)
    - libmodplug
    - uavs3d
    - davs2
    - libsixel
    - libva
    - libzvbi
    - svtav1
    - libaribcaption
    - zlib (zlib-ng)
    - zstd
    - expat
    - openssl
    - libsdl2
    - speex
    - vorbis
    - ogg
    - bzip2

- Zip
    - xvidcore (1.3.7)
    - lzo (2.10)
    - libopenmpt (0.7.12)
    - libiconv (1.18)
    - ~~gmp (6.3.0)~~
    - vapoursynth (R65/R63)
    - ~~mbedtls (3.5.0)~~
    - ~~libressl (3.1.5)~~


### WSL workaround

Place the file on specified location to limit ram & cpu usage to avoid getting stuck while building mpv.

    # /etc/wsl.conf
    [interop]
    #enabled=false
    appendWindowsPath=false

    [automount]
    enabled = true
    options = "metadata"
    mountFsTab = false

    [user]
    default=<user>
    ---------------------------------------
    # C:\Users\<UserName>\.wslconfig
    [wsl2]
    memory=4GB
    swap=0
    pageReporting=false

## Acknowledgements

This project was originally created and maintained [lachs0r](https://github.com/lachs0r/mingw-w64-cmake). Since then, it heavily modified to suit my own need.

get_property(src_glad TARGET glad PROPERTY _EP_SOURCE_DIR)
get_property(src_fast_float TARGET fast_float PROPERTY _EP_SOURCE_DIR)
# git reset --hard replaces these submodule-path symlinks with empty directories.
# A restored build can skip configure, and ninja may regenerate during either
# build or install, so restore both links before each Meson/Ninja invocation.
set(libplacebo_prepare_sources
    ${CMAKE_COMMAND} -E rm -rf <SOURCE_DIR>/3rdparty/glad <SOURCE_DIR>/3rdparty/fast_float
    COMMAND ${CMAKE_COMMAND} -E create_symlink ${src_glad} <SOURCE_DIR>/3rdparty/glad
    COMMAND ${CMAKE_COMMAND} -E create_symlink ${src_fast_float} <SOURCE_DIR>/3rdparty/fast_float
)
ExternalProject_Add(libplacebo
    DEPENDS
        vulkan
        shaderc
        spirv-cross
        lcms2
        glad
        fast_float
        xxhash
    GIT_REPOSITORY https://github.com/haasn/libplacebo.git
    SOURCE_DIR ${SOURCE_LOCATION}
    GIT_CLONE_FLAGS "--filter=tree:0"
    GIT_SUBMODULES ""
    UPDATE_COMMAND ""
    CONFIGURE_COMMAND ${libplacebo_prepare_sources}
    COMMAND ${EXEC} CONF=1 meson setup <BINARY_DIR> <SOURCE_DIR>
        --prefix=${MINGW_INSTALL_PREFIX}
        --libdir=${MINGW_INSTALL_PREFIX}/lib
        --cross-file=${MESON_CROSS}
        --default-library=static
        -Dd3d11=enabled
        -Ddebug=true
        -Db_ndebug=true
        -Doptimization=3
        -Dvulkan-registry='${MINGW_INSTALL_PREFIX}/share/vulkan/registry/vk.xml'
        -Ddemos=false
    BUILD_COMMAND ${libplacebo_prepare_sources}
    COMMAND ${EXEC} ninja -C <BINARY_DIR>
    INSTALL_COMMAND ${libplacebo_prepare_sources}
    COMMAND ${EXEC} ninja -C <BINARY_DIR> install
    LOG_DOWNLOAD 1 LOG_UPDATE 1 LOG_CONFIGURE 1 LOG_BUILD 1 LOG_INSTALL 1
)

force_rebuild_git(libplacebo)
force_meson_configure(libplacebo)
cleanup(libplacebo install)

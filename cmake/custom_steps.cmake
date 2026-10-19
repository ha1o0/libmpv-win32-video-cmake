function(cleanup _name _last_step)
    get_property(_build_in_source TARGET ${_name} PROPERTY _EP_BUILD_IN_SOURCE)
    get_property(_git_repository TARGET ${_name} PROPERTY _EP_GIT_REPOSITORY)
    get_property(_url TARGET ${_name} PROPERTY _EP_URL)
    get_property(git_tag TARGET ${_name} PROPERTY _EP_GIT_TAG)
    get_property(git_remote_name TARGET ${_name} PROPERTY _EP_GIT_REMOTE_NAME)
    get_property(stamp_dir TARGET ${_name} PROPERTY _EP_STAMP_DIR)
    get_property(source_dir TARGET ${_name} PROPERTY _EP_SOURCE_DIR)

    if("${git_remote_name}" STREQUAL "" AND NOT "${git_tag}" STREQUAL "")
        # GIT_REMOTE_NAME is not set when commit hash is specified
        set(git_tag "")
    else()
        set(git_tag "@{u}")
    endif()

    if(_git_repository)
        if(_build_in_source)
            set(remove_cmd "git -C <SOURCE_DIR> clean -dfx")
        else()
            set(remove_cmd "find <BINARY_DIR> -mindepth 1 -delete && git -C <SOURCE_DIR> clean -df")
        endif()
        set(COMMAND_FORCE_UPDATE COMMAND bash -c "git -C <SOURCE_DIR> am --abort 2> /dev/null || true"
                                 COMMAND ${stamp_dir}/reset_head.sh
                                 COMMAND bash -c "git -C <SOURCE_DIR> restore .")
        set(COMMAND_POSTREMOVE_UPDATE
            COMMAND bash -c "git -C <SOURCE_DIR> am --abort 2> /dev/null || true"
            COMMAND ${stamp_dir}/reset_head.sh --cleanup
            COMMAND bash -c "git -C <SOURCE_DIR> restore .")
    endif()

    # <STAMP_DIR> doesn't resolve into full path, so <LOG_DIR> is used instead since its same folder.
    ExternalProject_Add_Step(${_name} fullclean
        COMMAND ${EXEC} find <LOG_DIR> -type f " ! -iname '*.cmake' " -size 0c -delete # remove 0 byte files which are stamp files
        ${COMMAND_FORCE_UPDATE}
        ALWAYS TRUE
        EXCLUDE_FROM_MAIN TRUE
        INDEPENDENT TRUE
        LOG 1
        COMMENT "Deleting all stamp files of ${_name} package"
    )

    ExternalProject_Add_Step(${_name} liteclean
        COMMAND ${EXEC} rm -f <LOG_DIR>/${_name}-build
                              <LOG_DIR>/${_name}-install
        ALWAYS TRUE
        EXCLUDE_FROM_MAIN TRUE
        INDEPENDENT TRUE
        LOG 1
        COMMENT "Deleting build, install stamp files of ${_name} package"
    )

    ExternalProject_Add_Step(${_name} postremovebuild
        DEPENDEES ${_last_step}
        COMMAND ${EXEC} ${remove_cmd}
        # Successful cleanup must not invalidate the completed build stamps.
        ${COMMAND_POSTREMOVE_UPDATE}
        LOG 1
        COMMENT "Deleting build directory of ${_name} package after install"
    )

    ExternalProject_Add_Step(${_name} removebuild
        DEPENDEES fullclean
        COMMAND ${EXEC} ${remove_cmd}
        ALWAYS TRUE
        EXCLUDE_FROM_MAIN TRUE
        INDEPENDENT TRUE
        LOG 1
        COMMENT "Deleting build directory of ${_name} package"
    )

    ExternalProject_Add_Step(${_name} removeprefix
        COMMAND ${EXEC} rm -rf <INSTALL_DIR> ${source_dir}
        COMMAND ${CMAKE_COMMAND} --build ${CMAKE_BINARY_DIR} --target rebuild_cache
        ALWAYS TRUE
        EXCLUDE_FROM_MAIN TRUE
        INDEPENDENT TRUE
        LOG 1
        COMMENT "Deleting everything about ${_name} package"
    )
    ExternalProject_Add_StepTargets(${_name} fullclean liteclean removeprefix removebuild)
endfunction()

function(force_rebuild_git _name)
    get_property(git_tag TARGET ${_name} PROPERTY _EP_GIT_TAG)
    get_property(git_reset TARGET ${_name} PROPERTY _EP_GIT_RESET)
    get_property(git_remote_name TARGET ${_name} PROPERTY _EP_GIT_REMOTE_NAME)
    get_property(stamp_dir TARGET ${_name} PROPERTY _EP_STAMP_DIR)
    get_property(source_dir TARGET ${_name} PROPERTY _EP_SOURCE_DIR)

    if("${git_remote_name}" STREQUAL "")
        set(git_remote_name origin)
    endif()
    # A recipe/patch change must also retire a cached configure/build/install.
    # CMake's individual command stamps cannot account for source edits removed
    # by git reset, or a build directory already deleted after installation.
    file(SHA256 "${CMAKE_CURRENT_LIST_FILE}" recipe_hash)
    file(GLOB recipe_patches "${CMAKE_CURRENT_SOURCE_DIR}/${_name}-*.patch")
    foreach(recipe_patch IN LISTS recipe_patches)
        file(SHA256 "${recipe_patch}" patch_hash)
        string(APPEND recipe_hash ";${recipe_patch}:${patch_hash}")
    endforeach()
    foreach(phase PATCH CONFIGURE BUILD INSTALL)
        get_property(phase_command TARGET ${_name} PROPERTY _EP_${phase}_COMMAND)
        string(APPEND recipe_hash ";${phase}:${phase_command}")
    endforeach()
    string(SHA256 recipe_hash "${recipe_hash}")
    configure_file(${CMAKE_CURRENT_FUNCTION_LIST_DIR}/reset_git.sh.in
                   ${stamp_dir}/reset_head.sh @ONLY)
file(CHMOD ${stamp_dir}/reset_head.sh 
PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE GROUP_READ GROUP_EXECUTE WORLD_READ WORLD_EXECUTE)

    ExternalProject_Add_Step(${_name} force-update
        ALWAYS TRUE
        EXCLUDE_FROM_MAIN TRUE
        INDEPENDENT TRUE
        WORKING_DIRECTORY <SOURCE_DIR>
        COMMAND bash -c "git am --abort 2> /dev/null || true"
        COMMAND bash -c "git fetch --filter=tree:0 --no-recurse-submodules || true"
        COMMAND ${stamp_dir}/reset_head.sh
    )
    ExternalProject_Add_StepTargets(${_name} force-update)

    ExternalProject_Add_Step(${_name} write-head
        DEPENDEES update
        DEPENDERS patch
        INDEPENDENT TRUE
        WORKING_DIRECTORY <SOURCE_DIR>
        # If this step reruns, patch and every later stage rerun too. Start at
        # the requested base so cached patch commits are never applied twice.
        COMMAND ${stamp_dir}/reset_head.sh --before-patch
        LOG 1
    )

    if(EXISTS ${source_dir}/.git)
        ExternalProject_Add_Step(${_name} check-git
            DEPENDERS download
            INDEPENDENT TRUE
            WORKING_DIRECTORY ${stamp_dir}
            COMMAND ${CMAKE_COMMAND} -E touch <INSTALL_DIR>/src/${_name}-stamp/${_name}-download
            COMMAND ${CMAKE_COMMAND} -E copy ${_name}-gitinfo.txt ${_name}-gitclone-lastrun.txt
            LOG 1
        )
    else()
        execute_process(
            WORKING_DIRECTORY ${stamp_dir}
            COMMAND ${EXEC} rm ${_name}-gitclone-lastrun.txt
            ERROR_QUIET
        )
    endif()
endfunction()

function(force_rebuild_svn _name)
    ExternalProject_Add_Step(${_name} force-update
        DEPENDEES download update
        DEPENDERS patch build install
        COMMAND svn revert -R .
        COMMAND svn up
        WORKING_DIRECTORY <SOURCE_DIR>
        LOG 1
    )
endfunction()

function(force_rebuild_hg _name)
    ExternalProject_Add_Step(${_name} force-update
        DEPENDEES download update
        DEPENDERS patch build install
        COMMAND hg --config "extensions.purge=" purge --all
        COMMAND hg update -C
        WORKING_DIRECTORY <SOURCE_DIR>
        LOG 1
    )
endfunction()

function(force_meson_configure _name)
    ExternalProject_Add_Step(${_name} force-meson-configure
        DEPENDERS configure
        COMMAND ${EXEC} rm -rf <BINARY_DIR>/meson-*
        LOG 1
    )
endfunction()

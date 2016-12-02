#
# Multimake
# Copyright (C) 2015 Pelagicore AB
#
# Permission to use, copy, modify, and/or distribute this software for 
# any purpose with or without fee is hereby granted, provided that the 
# above copyright notice and this permission notice appear in all copies. 
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL 
# WARRANTIES WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED  
# WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR 
# BE LIABLE FOR ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES 
# OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, 
# WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, 
# ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS 
# SOFTWARE.
#
# For further information see LICENSE

cmake_minimum_required(VERSION 2.6)

# Include guard
if(__PROJECTS_BUILDER_INCLUDED)
    return()
endif()
set(__PROJECTS_BUILDER_INCLUDED 1)

# Get rid of some warnings. https://cmake.org/cmake/help/v3.0/policy/CMP0011.html
cmake_policy(SET CMP0011 OLD)

include(GNUInstallDirs)
include(ExternalProject)
include(CTest)


set(COMMON_CMAKE_CONFIGURATION_OPTIONS ${COMMON_CMAKE_CONFIGURATION_OPTIONS})

set(AUTOTOOLS_CONFIGURE_COMMAND configure ${CROSS_COMPILER_AUTOTOOLS_OPTIONS} --prefix=${CMAKE_INSTALL_PREFIX})

set(PROJECTS_DOWNLOAD_DIR ${CMAKE_BINARY_DIR}/Downloads)

OPTION( WITH_ICECC "Enable distributed build with IceCC" OFF)
IF(WITH_ICECC)
    set(EXTRA_PATH ":/usr/lib/icecc/bin")
ENDIF()


OPTION( ENABLE_DEBUG "Enable debug mode" ON )
IF(ENABLE_DEBUG)
    set(CMAKE_BUILD_TYPE Debug)
    set(AUTOTOOLS_CONFIGURE_COMMAND ${AUTOTOOLS_CONFIGURE_COMMAND} "CXXFLAGS=-O0 -g")
ELSE()
    set(CMAKE_BUILD_TYPE RelWithDebInfo)
    set(AUTOTOOLS_CONFIGURE_COMMAND ${AUTOTOOLS_CONFIGURE_COMMAND} "CXXFLAGS=-O2 -g")
ENDIF()


OPTION( WITH_CLANG "Use Clang compiler" OFF )
IF(WITH_CLANG)
    set(CMAKE_C_COMPILER clang)
    set(CMAKE_CXX_COMPILER clang++)
    set(COMMON_CMAKE_CONFIGURATION_OPTIONS ${COMMON_CMAKE_CONFIGURATION_OPTIONS} -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++)
ENDIF()


OPTION( ENABLE_UNINSTALLED_PKG_CONFIG "Enable the use of the uninstalled pkg-config file variants" OFF )

if(NOT DEFINED PROJECTS_LOCATION)
    set(PROJECTS_LOCATION ${CMAKE_SOURCE_DIR})
endif()


macro(on_package_already_defined PACKAGE)
    message("Package already defined : ${PACKAGE}")
endmacro()


macro(set_package_defined PROJECT)
    if(${PROJECT}_DEFINED)
        on_package_already_defined(${PROJECT})
    endif()
    set(${PROJECT}_DEFINED 1)
#    message("Package defined : ${PROJECT}")
endmacro()


macro(set_package_defined_with_git_repository PROJECT)
    set(${PROJECT}_GIT_DEFINED 1)
    set_package_defined(${PROJECT})
endmacro()


macro(add_available_package PROJECT)
    set_package_defined(${PROJECT})

    add_custom_target(${PROJECT} ALL)

endmacro()


macro(add_unknown_package PROJECT )
    message("Unknown package : ${PROJECT}")
    add_custom_target(${PROJECT} ALL
        COMMAND echo "A required package can not be found or it is referred before being defined: ${PROJECT}"
        COMMAND exit 1
    )
endmacro()


macro(find_layer LAYER_NAME)
    find_package(${LAYER_NAME}Layer REQUIRED)
endmacro()


macro(append_to_variables PROJECT)
    if(ENABLE_UNINSTALLED_PKG_CONFIG)
        set(PKG_CONFIG_PATH ${CMAKE_BINARY_DIR}/${PROJECT}-prefix/src/${PROJECT}-build:${PKG_CONFIG_PATH})
    endif()
endmacro()


macro(write_variables_file)
    file(WRITE ${PROJECT_BINARY_DIR}/make "PKG_CONFIG_PATH=${PKG_CONFIG_PATH}:${CMAKE_INSTALL_PREFIX}/lib/pkgconfig:${CMAKE_INSTALL_FULL_LIBDIR}/pkgconfig:$PKG_CONFIG_PATH PATH=${CMAKE_INSTALL_PREFIX}/bin:${EXTRA_PATH}:$PATH LD_LIBRARY_PATH=${CMAKE_INSTALL_PREFIX}/lib:${CMAKE_INSTALL_FULL_LIBDIR}:$LD_LIBRARY_PATH make $@")
    # TODO : find a way to make the "make" file executable
endmacro()


macro(check_dependencies_existence PROJECT DEPENDENCIES)
    
    foreach(DEP ${DEPENDENCIES})
        if(${DEP}_DEFINED)
        else()
            message("Package not found : ${DEP}")
            add_unknown_package(${DEP})
        endif()
    endforeach()

endmacro()


macro(validate_git_commit PROJECT)
    if(NOT ${PROJECT}_GIT_COMMIT)
        set(${PROJECT}_GIT_COMMIT "master")
    endif()
endmacro()


set(EXCLUDED_PACKAGES "" CACHE STRING "List of packages to exclude (semi-column separated)")

set(EXCLUDED_PACKAGES_LIST "${EXCLUDED_PACKAGES}")

if(${EXCLUDED_PACKAGES_LIST})
    message("Excluding packages ${EXCLUDED_PACKAGES_LIST}")
endif()

foreach(APACKAGE ${EXCLUDED_PACKAGES_LIST})
    message("Excluding package ${APACKAGE}")
    add_available_package(${APACKAGE})
endforeach()


# Create a new target which can be used to build all the dependencies of the given package
macro(add_dependencies_target PROJECT DEPENDENCIES)

    add_custom_target(${PROJECT}_deps
        DEPENDS ${DEPENDENCIES}
    )

endmacro()


# This macro can be used to simply clone a repository and add operations manually via "ExternalProject_Add_Step"
macro(add_no_build_external_project PROJECT REPOSITORY_URL DEPENDENCIES)

validate_git_commit(${PROJECT})

    if(NOT ${PROJECT}_DEFINED)

        set_package_defined_with_git_repository(${PROJECT})
        add_dependencies_target(${PROJECT} "${DEPENDENCIES}")
        check_dependencies_existence(${PROJECT} "${DEPENDENCIES}")
        append_to_variables(${PROJECT})

        ExternalProject_Add(${PROJECT}
            DEPENDS ${DEPENDENCIES}
            SOURCE_DIR ${PROJECTS_DOWNLOAD_DIR}/${PROJECT}
            GIT_REPOSITORY ${REPOSITORY_URL}
            CONFIGURE_COMMAND ""
            INSTALL_COMMAND ""
            BUILD_COMMAND ""
            UPDATE_COMMAND ""
            GIT_TAG ${${PROJECT}_GIT_COMMIT}
        )

        write_variables_file()

    endif()

endmacro()


macro(set_external_git_project_commit PROJECT COMMIT)

    if (NOT DEFINED ${PROJECT}_GIT_COMMIT)
        set(${PROJECT}_GIT_COMMIT ${COMMIT})
    else()
        message("Commit or branch already set for component ${PROJECT} : ${${PROJECT}_GIT_COMMIT}")
    endif()

endmacro()


macro(read_common_properties PROJECT)

    if(${${PROJECT}_BUILD_ALWAYS})
        if (${CMAKE_VERSION} VERSION_GREATER 3.1)
            set(BUILD_ALWAYS BUILD_ALWAYS 1)
        else()
            message(WARNING "BUILD_ALWAYS is supported with CMake > 3.1 only") 
        endif()
    endif()

    if(${${PROJECT}_NO_INSTALL})
        set(INSTALL_COMMAND INSTALL_COMMAND echo No installation for ${PROJECT})
    else()
        # Use standard installation command (should be "make install")
        set(INSTALL_COMMAND )
    endif()
    
endmacro()


include(${CMAKE_CURRENT_LIST_DIR}/MultimakeAutotools.cmake)
include(${CMAKE_CURRENT_LIST_DIR}/MultimakeQt.cmake)
include(${CMAKE_CURRENT_LIST_DIR}/MultimakeCMake.cmake)
include(${CMAKE_CURRENT_LIST_DIR}/MultimakeMaven.cmake)
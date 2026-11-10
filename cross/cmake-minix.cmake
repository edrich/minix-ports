# CMake toolchain file for i586-elf32-minix
# usage: cmake -B build -DCMAKE_TOOLCHAIN_FILE=../minix-ports/cross/cmake-minix.cmake ..
set(CMAKE_SYSTEM_NAME Minix)
set(CMAKE_SYSTEM_PROCESSOR i586)

set(triple i586-elf32-minix)
set(CMAKE_C_COMPILER   ${triple}-gcc)
set(CMAKE_CXX_COMPILER ${triple}-g++)
set(CMAKE_AR           ${triple}-ar)
set(CMAKE_RANLIB       ${triple}-ranlib)

# Point at the MINIX destdir sysroot (adjust if the repo lives elsewhere).
set(MINIX_PORTS_ROOT ${CMAKE_CURRENT_LIST_DIR}/..)
get_filename_component(MINIX_PORTS_ROOT ${MINIX_PORTS_ROOT} ABSOLUTE)
set(MINIX_REPO ${MINIX_PORTS_ROOT}/../minix)
get_filename_component(MINIX_REPO ${MINIX_REPO} ABSOLUTE)
set(CMAKE_SYSROOT ${MINIX_REPO}/../obj.docker.i386/destdir.i386)

set(CMAKE_FIND_ROOT_PATH ${CMAKE_SYSROOT} ${MINIX_PORTS_ROOT}/rootfs)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

# MINIX has no dlopen-style dl; static-linked ports keep things simple for now.
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)
set(CMAKE_EXE_LINKER_FLAGS_INIT "-static-libstdc++")

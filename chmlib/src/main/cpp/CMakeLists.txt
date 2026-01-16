# the minimum version of CMake.
cmake_minimum_required(VERSION 3.5.0)
project(chmlib)

include_directories(${CMAKE_CURRENT_SOURCE_DIR}/chmlib_src)

# chmlib 是老代码，为了支持超过 2GB 的大文件和兼容性，建议添加以下定义
add_definitions(-D_FILE_OFFSET_BITS=64 -D_LARGEFILE64_SOURCE)



# 3. 定义编译目标 (Shared Library)
add_library(chmlib SHARED
    # --- NAPI 接口文件 ---
    napi_init.cpp

    # --- chmlib 源码文件 ---
    # 根据你的目录结构 src/main/cpp/chmlib_src
    chmlib_src/chm_lib.c
    chmlib_src/lzx.c
)

target_link_libraries(chmlib PUBLIC
    # 必须：鸿蒙 NAPI 核心库
    libace_napi.z.so

    # 推荐：日志库 (如果你在代码里用了 OH_LOG_PRINT)
    libhilog_ndk.z.so
)

#set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})
#
#if(DEFINED PACKAGE_FIND_FILE)
#    include(${PACKAGE_FIND_FILE})
#endif()
#
#include_directories(${NATIVERENDER_ROOT_PATH}
#                    ${NATIVERENDER_ROOT_PATH}/include)
#
#add_library(chmlib SHARED napi_init.cpp)
#target_link_libraries(chmlib PUBLIC libace_napi.z.so)

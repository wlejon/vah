cmake_minimum_required(VERSION 3.10)

# Set vcpkg toolchain file
if(DEFINED ENV{VCPKG_ROOT})
    set(CMAKE_TOOLCHAIN_FILE "$ENV{VCPKG_ROOT}/scripts/buildsystems/vcpkg.cmake" CACHE STRING "")
elseif(EXISTS "D:/vcpkg/scripts/buildsystems/vcpkg.cmake")
    set(CMAKE_TOOLCHAIN_FILE "D:/vcpkg/scripts/buildsystems/vcpkg.cmake" CACHE STRING "")
endif()

project(vah)

set(CMAKE_CXX_STANDARD 20)

find_package(SDL2 CONFIG REQUIRED)
find_package(assimp CONFIG REQUIRED)
find_package(OpenGL REQUIRED)
find_package(RmlUi CONFIG REQUIRED)
find_package(glm CONFIG REQUIRED)
find_package(glad CONFIG REQUIRED)
find_package(spdlog CONFIG REQUIRED)
find_package(Lua REQUIRED)
find_package(sol2 CONFIG REQUIRED)
find_package(nlohmann_json CONFIG REQUIRED)
find_package(unofficial-sqlite3 CONFIG REQUIRED)

find_path(MINIAUDIO_INCLUDE_DIRS "miniaudio.h")

add_executable(vah
    src/main.cpp
    src/Logger.cpp
    src/RmlUi_Renderer_GL3.cpp
    src/CommandQueue.cpp
    src/ResponseQueue.cpp
    src/LuaThread.cpp
    src/ThreadManager.cpp
    src/RmlUiBridge.cpp
    src/FileSystem.cpp
    src/JsonBindings.cpp
    src/SqliteBindings.cpp
    src/DataBindings.cpp
    src/DataStore.cpp
)

target_include_directories(vah PRIVATE
    ${CMAKE_SOURCE_DIR}/external/stb
    src/
    ${MINIAUDIO_INCLUDE_DIRS}
)

target_link_libraries(vah PRIVATE
    SDL2::SDL2
    SDL2::SDL2main
    RmlUi::RmlUi
    RmlUi::Lua
    OpenGL::GL
    glm::glm
    glad::glad
    spdlog::spdlog
    ${LUA_LIBRARIES}
    sol2::sol2
    nlohmann_json::nlohmann_json
    unofficial::sqlite3::sqlite3
)


 
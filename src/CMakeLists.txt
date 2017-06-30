
find_package(Valac REQUIRED)
find_package(PkgConfig REQUIRED)

pkg_check_modules(CONSOLE_RUNNER_DEPS REQUIRED
    glib-2.0
    gobject-2.0
    gio-2.0
    gio-unix-2.0
)

configure_file(version.vala.in version.vala @ONLY)

# Client

vala2c(CLIENT_C_FILES
    PACKAGES
        gio-2.0
        gio-unix-2.0
        posix
    TARGET_GLIB
        2.48
    OUTPUT_DIR
        client
    SOURCE_FILES
        ${CMAKE_CURRENT_BINARY_DIR}/version.vala
        common.vala
        client.vala
)

set(CLIENT_TARGET "conrun")
add_executable(${CLIENT_TARGET} ${CLIENT_C_FILES})
target_compile_options(${CLIENT_TARGET} PRIVATE "-w")
target_include_directories(${CLIENT_TARGET} PRIVATE ${CONSOLE_RUNNER_DEPS_INCLUDE_DIRS})
target_link_libraries(${CLIENT_TARGET} ${CONSOLE_RUNNER_DEPS_LIBRARIES} ${SHARED_LIBRARY_TARGET})

install(TARGETS ${CLIENT_TARGET} RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})


# Server

vala2c(SERVER_C_FILES
    PACKAGES
        gio-2.0
        gio-unix-2.0
        linux
        posix
    TARGET_GLIB
        2.48
    OUTPUT_DIR
        server
    SOURCE_FILES
        ${CMAKE_CURRENT_BINARY_DIR}/version.vala
        common.vala
        server.vala
)

set(SERVER_TARGET "conrun-server")
add_executable(${SERVER_TARGET} ${SERVER_C_FILES})
target_compile_options(${SERVER_TARGET} PRIVATE "-w")
target_include_directories(${SERVER_TARGET} PRIVATE ${CONSOLE_RUNNER_DEPS_INCLUDE_DIRS})
target_link_libraries(${SERVER_TARGET} ${CONSOLE_RUNNER_DEPS_LIBRARIES})

install(TARGETS ${SERVER_TARGET} RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})

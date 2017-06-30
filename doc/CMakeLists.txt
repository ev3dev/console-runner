
find_package(Pandoc REQUIRED)

add_man_page(console-runner.1
    SECTION 1
    HEADER "User's Manual"
    FOOTER ${PROJECT_VERSION}
    console-runner.rst)

install(FILES ${MAN_PAGES} DESTINATION ${CMAKE_INSTALL_DOCDIR}/man)

add_custom_target(doc ALL DEPENDS console-runner.1)

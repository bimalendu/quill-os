cmake_minimum_required(VERSION 3.21)
project(quill-setup VERSION 44 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Core Gui Qml Quick QuickControls2)
qt_standard_project_setup(REQUIRES 6.5)

qt_add_executable(quill-setup main.cpp backend.cpp backend.h)
qt_add_qml_module(quill-setup
    URI QuillSetup
    VERSION 1.0
    QML_FILES qml/Main.qml
)
target_link_libraries(quill-setup PRIVATE Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick Qt6::QuickControls2)

include(GNUInstallDirs)
install(TARGETS quill-setup RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(PROGRAMS quill-setup-helper DESTINATION ${CMAKE_INSTALL_LIBEXECDIR})
install(DIRECTORY groups/ DESTINATION ${CMAKE_INSTALL_DATADIR}/quill-setup/groups FILES_MATCHING PATTERN "*.json")
install(FILES data/org.quill.setup.policy DESTINATION ${CMAKE_INSTALL_DATADIR}/polkit-1/actions)
install(FILES data/quill-setup.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
install(FILES data/quill-setup-autostart.desktop DESTINATION /etc/xdg/autostart RENAME quill-setup.desktop)

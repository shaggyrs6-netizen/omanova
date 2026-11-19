QT += core gui qml quick quickcontrols2
CONFIG += c++17 release
TARGET = omanova-mission-control-preview
TEMPLATE = app
SOURCES += src/main.cpp src/mission.cpp
HEADERS += src/mission.h
RESOURCES += src/resources.qrc

# Already installed system library; used only for the optional wallpaper surface.
INCLUDEPATH += /usr/include/LayerShellQt
LIBS += -lLayerShellQtInterface

SOURCES += src/startupoptions.cpp
HEADERS += src/startupoptions.h

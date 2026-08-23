#include "include/torrserver_flutter/torrserver_flutter_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "torrserver_flutter_plugin.h"

void TorrserverFlutterPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  torrserver_flutter::TorrserverFlutterPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}

#include "torrserver_flutter_plugin.h"

// This must be included before many other Windows headers.
#include <windows.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <memory>

namespace torrserver_flutter {

// static
void TorrserverFlutterPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "torrserver_flutter",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<TorrserverFlutterPlugin>();

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto &call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

TorrserverFlutterPlugin::TorrserverFlutterPlugin() {}

TorrserverFlutterPlugin::~TorrserverFlutterPlugin() {}

void TorrserverFlutterPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  result->NotImplemented();
}

}  // namespace torrserver_flutter

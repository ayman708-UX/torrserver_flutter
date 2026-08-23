#ifndef FLUTTER_PLUGIN_TORRSERVER_FLUTTER_PLUGIN_H_
#define FLUTTER_PLUGIN_TORRSERVER_FLUTTER_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace torrserver_flutter {

class TorrserverFlutterPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  TorrserverFlutterPlugin();

  virtual ~TorrserverFlutterPlugin();

  // Disallow copy and assign.
  TorrserverFlutterPlugin(const TorrserverFlutterPlugin&) = delete;
  TorrserverFlutterPlugin& operator=(const TorrserverFlutterPlugin&) = delete;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace torrserver_flutter

#endif  // FLUTTER_PLUGIN_TORRSERVER_FLUTTER_PLUGIN_H_

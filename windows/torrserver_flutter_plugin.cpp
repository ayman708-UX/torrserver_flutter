#include "torrserver_flutter_plugin.h"

// This must be included before many other Windows headers.
#include <windows.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <memory>

namespace torrserver_flutter {

namespace {
// Global Job Object handle configured with KILL_ON_JOB_CLOSE.
// Any child process spawned by this host process (including torrserver.exe via Dart Process.start)
// automatically inherits and becomes part of this job.
// The Windows NT Kernel guarantees that when the parent process exits or terminates,
// all child processes in the job are immediately and forcefully closed.
HANDLE g_job_handle = NULL;

void InitializeJobObject() {
  if (g_job_handle != NULL) {
    return;
  }
  g_job_handle = CreateJobObject(NULL, NULL);
  if (g_job_handle != NULL) {
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION jeli = {0};
    jeli.BasicLimitInformation.LimitFlags =
        JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE | JOB_OBJECT_LIMIT_SILENT_BREAKAWAY_OK;
    if (SetInformationJobObject(g_job_handle,
                               JobObjectExtendedLimitInformation, &jeli,
                               sizeof(jeli))) {
      AssignProcessToJobObject(g_job_handle, GetCurrentProcess());
    }
  }
}
}  // namespace

// static
void TorrserverFlutterPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  InitializeJobObject();

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

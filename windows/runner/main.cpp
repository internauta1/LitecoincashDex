#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <cstdio>

#include "flutter_window.h"
#include "utils.h"
#include "single_instance_policy.h"

namespace {
HRESULT ShutdownWebViewComposition() {
  const HMODULE module = GetModuleHandleW(L"flutter_inappwebview_windows_plugin.dll");
  if (!module) return S_OK;
  using Shutdown = HRESULT (__cdecl*)();
  const auto shutdown = reinterpret_cast<Shutdown>(GetProcAddress(module, "LccNextShutdownWebViewComposition"));
  return shutdown ? shutdown() : HRESULT_FROM_WIN32(ERROR_PROC_NOT_FOUND);
}
}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  // Enforce single instance: create a named mutex. If it already exists or we
  // don't have access to it, try to bring the existing window to the foreground
  // and exit immediately.
#ifdef LCC_NEXT_ISOLATED_RUNNER
  constexpr auto policy = GetSingleInstancePolicy(true);
#else
  constexpr auto policy = GetSingleInstancePolicy(false);
#endif
  HANDLE singleInstanceMutex = CreateMutexW(nullptr, TRUE, policy.mutex_name);
  DWORD createMutexError = GetLastError();
  if (!singleInstanceMutex && !policy.activate_existing_window) {
    std::fprintf(stderr, "isolated_runner phase=start category=mutex_unavailable\n");
    ::CoUninitialize();
    return EXIT_FAILURE;
  }
  const bool mutexIndicatesOtherInstance =
      (singleInstanceMutex == nullptr && createMutexError == ERROR_ACCESS_DENIED) ||
      (singleInstanceMutex != nullptr && createMutexError == ERROR_ALREADY_EXISTS);
  if (mutexIndicatesOtherInstance) {
    // Isolated profiles never find, restore, or activate another app's window.
    if (policy.activate_existing_window) {
      HWND existing = FindWindowW(nullptr, policy.window_title);
      if (existing != nullptr) {
        ShowWindow(existing, SW_RESTORE);
        AllowSetForegroundWindow(ASFW_ANY);
        SetForegroundWindow(existing);
        BringWindowToTop(existing);
      }
    } else {
      std::fprintf(stderr, "isolated_runner phase=start category=duplicate_profile\n");
    }
    if (singleInstanceMutex) {
      CloseHandle(singleInstanceMutex);
    }
    ::CoUninitialize();
    return policy.activate_existing_window ? EXIT_SUCCESS : ERROR_ALREADY_EXISTS;
  }

  // Destroy Flutter and its plugins before draining the plugin's current-thread
  // composition queue. COM must remain initialized throughout both operations.
  int exit_code = [&]() {
    flutter::DartProject project(L"data");
    project.set_dart_entrypoint_arguments(GetCommandLineArguments());
    FlutterWindow window(project);
    Win32Window::Point origin(10, 10);
    Win32Window::Size size(1280, 720);
    if (!window.Create(policy.window_title, origin, size)) {
      return EXIT_FAILURE;
    }
    window.SetQuitOnClose(true);
    ::MSG msg{};
    BOOL result;
    while ((result = ::GetMessage(&msg, nullptr, 0, 0)) > 0) {
      ::TranslateMessage(&msg);
      ::DispatchMessage(&msg);
    }
    return result < 0 ? EXIT_FAILURE : EXIT_SUCCESS;
  }();
  const HRESULT composition_shutdown = ShutdownWebViewComposition();
  if (FAILED(composition_shutdown)) {
    std::fprintf(stderr, "native_runner phase=shutdown category=composition_failed result=0x%08lX\n",
        static_cast<unsigned long>(composition_shutdown));
    exit_code = EXIT_FAILURE;
  }

  if (singleInstanceMutex) {
    ReleaseMutex(singleInstanceMutex);
    CloseHandle(singleInstanceMutex);
  }

  ::CoUninitialize();
  return exit_code;
}

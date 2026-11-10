#pragma once

#include <windows.h>
#include <winrt/Windows.Foundation.h>
#include <memory>

#include "graphics_context.h"

namespace flutter_inappwebview_plugin {

// Must run on the creating UI thread, after all views/engines release their
// consumers and before COM uninitialization or DLL_PROCESS_DETACH. A current-
// thread DispatcherQueue requires pumping until ShutdownQueueAsync completes.
inline HRESULT ShutdownCompositionResources(
    std::shared_ptr<rx::RoHelper>& rohelper,
    winrt::com_ptr<ABI::Windows::System::IDispatcherQueueController>& controller,
    std::unique_ptr<GraphicsContext>& graphics,
    winrt::com_ptr<ABI::Windows::UI::Composition::ICompositor>& compositor) noexcept {
  bool saw_quit = false;
  int quit_code = 0;
  HRESULT result = S_OK;
  try {
    compositor = nullptr;
    graphics.reset();
    if (controller) {
      winrt::Windows::Foundation::IAsyncAction action{nullptr};
      result = controller->ShutdownQueueAsync(
          reinterpret_cast<ABI::Windows::Foundation::IAsyncAction**>(winrt::put_abi(action)));
      if (SUCCEEDED(result) && action) {
        const ULONGLONG deadline = GetTickCount64() + 10000;
        while (action.Status() == winrt::Windows::Foundation::AsyncStatus::Started) {
          MSG message{};
          while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) {
            if (message.message == WM_QUIT) {
              saw_quit = true;
              quit_code = static_cast<int>(message.wParam);
            } else {
              TranslateMessage(&message);
              DispatchMessageW(&message);
            }
          }
          if (GetTickCount64() >= deadline) { result = HRESULT_FROM_WIN32(WAIT_TIMEOUT); break; }
          MsgWaitForMultipleObjectsEx(0, nullptr, 10, QS_ALLINPUT, MWMO_INPUTAVAILABLE);
        }
        if (SUCCEEDED(result)) {
          if (action.Status() == winrt::Windows::Foundation::AsyncStatus::Error) result = action.ErrorCode();
          if (action.Status() == winrt::Windows::Foundation::AsyncStatus::Canceled) result = HRESULT_FROM_WIN32(ERROR_CANCELLED);
        }
      }
    }
    if (SUCCEEDED(result)) {
      controller = nullptr;
      rohelper.reset();
    }
  } catch (const winrt::hresult_error& error) {
    result = error.code();
  } catch (...) {
    result = E_FAIL;
  }
  if (saw_quit) PostQuitMessage(quit_code);
  return result;
}
}  // namespace flutter_inappwebview_plugin

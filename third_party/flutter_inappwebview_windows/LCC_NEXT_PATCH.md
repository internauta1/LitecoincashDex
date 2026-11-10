# Local Windows teardown correction (upstream package 0.6.0)

The r3 native debugger captured 0xC0000602 in CoreMessaging/DirectComposition
while this DLL's CRT destroyed its process-static compositor during
LdrShutdownProcess. The application runner had already finished its message
loop. Raw minidumps remain private to the disposable profile.

This local copy adds `LccNextShutdownWebViewComposition`, called by the runner
after the Flutter window/controller and all plugin consumers are destroyed,
before COM uninitialization and process/DLL detach. It releases graphics
resources, requests current-thread DispatcherQueue shutdown and pumps messages
until completion with a ten-second bound. It refuses shutdown while managers
remain alive or on the wrong thread. Failures remain visible as nonzero runner
exit status; they are not converted into successful closure.

The native regression uses the same real RoHelper/GraphicsContext/compositor
types in a DLL: retaining them until DLL detach reproduces 0xC0000602, while
explicit cleanup exits 0 and permits a second initialization on the thread.

Existing upstream/ANGLE licenses are retained. The global pub cache is read-only.
The final application's visual closure still requires validation of its build.

package com.photoframe.mobile_app

import android.os.StatFs
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts two small platform channels:
 *
 * - "photoframe/diskspace", used by
 *   `lib/services/cache/image_cache_manager.dart` to cap the on-disk image
 *   cache against the device's actually free storage (see
 *   docs/DECISIONS.md, ADR-010).
 * - "photoframe/kiosk", used by
 *   `lib/services/kiosk/kiosk_mode_controller.dart` to enter/leave Android's
 *   screen-pinning ("Lock Task") mode while the slideshow is showing (see
 *   docs/DECISIONS.md ADR-004: Kiosk/Autostart limits).
 *
 * A dedicated pub.dev package was deliberately not added for either of
 * these - both wrap a couple of lines of stable Android SDK API
 * (`android.os.StatFs`, `Activity.startLockTask`/`stopLockTask`), and this
 * project already needs its own MethodChannel surface for platform-specific
 * behaviour, so both follow the same pattern rather than pulling in a
 * small, potentially unmaintained third-party plugin.
 */
class MainActivity : FlutterActivity() {
    private val diskSpaceChannel = "photoframe/diskspace"
    private val kioskChannel = "photoframe/kiosk"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, diskSpaceChannel)
            .setMethodCallHandler { call, result ->
                if (call.method == "getFreeBytes") {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("INVALID_ARGUMENT", "Missing 'path' argument", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val stat = StatFs(path)
                        val freeBytes = stat.availableBlocksLong * stat.blockSizeLong
                        result.success(freeBytes)
                    } catch (e: Exception) {
                        result.error("STATFS_FAILED", e.message, null)
                    }
                } else {
                    result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, kioskChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startKioskMode" -> {
                        try {
                            // On a device without Device Owner/Device Policy
                            // Controller privileges (the normal case for this
                            // app - it is not an enterprise MDM tool), this
                            // enters "unprivileged" screen pinning rather
                            // than the fully-locked, Device-Owner-whitelisted
                            // variant of Lock Task Mode. That is intentional
                            // and sufficient here: unprivileged pinning still
                            // keeps the app in the foreground and hides the
                            // recents/home affordances, it only differs in
                            // that Android shows a small "unpin"/back
                            // notice at the top of the screen that the user
                            // can use to leave pinning - that UI is a
                            // platform behaviour and cannot be fully
                            // suppressed without Device Owner status (see
                            // kiosk_settings_screen.dart for the honest
                            // user-facing explanation of this limitation).
                            startLockTask()
                            result.success(null)
                        } catch (e: IllegalStateException) {
                            // Thrown e.g. if the activity is not in a state
                            // that allows entering Lock Task Mode. Never
                            // crash the slideshow over this - just report it
                            // back to Dart, which treats it as a no-op.
                            result.error("START_LOCK_TASK_FAILED", e.message, null)
                        } catch (e: Exception) {
                            result.error("START_LOCK_TASK_FAILED", e.message, null)
                        }
                    }
                    "stopKioskMode" -> {
                        try {
                            stopLockTask()
                            result.success(null)
                        } catch (e: IllegalStateException) {
                            // Thrown if Lock Task Mode was never active -
                            // harmless, just report it back.
                            result.error("STOP_LOCK_TASK_FAILED", e.message, null)
                        } catch (e: Exception) {
                            result.error("STOP_LOCK_TASK_FAILED", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}

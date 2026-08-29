package com.photoframe.mobile_app

import android.os.StatFs
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts one small platform channel, "photoframe/diskspace", used by
 * `lib/services/cache/image_cache_manager.dart` to cap the on-disk image
 * cache against the device's actually free storage (see
 * docs/DECISIONS.md, ADR "getFreeDiskSpaceBytes platform hookup").
 *
 * A dedicated pub.dev package (e.g. disk_space_plus) was deliberately not
 * added for this single number - `android.os.StatFs` on the cache
 * directory's path is a two-line, dependency-free primitive already exposed
 * by the Android SDK, and this project already needs its own MethodChannel
 * surface for platform-specific behaviour (see ADR-004 Kiosk/Autostart), so
 * this follows the same pattern rather than pulling in a small,
 * potentially unmaintained third-party plugin.
 */
class MainActivity : FlutterActivity() {
    private val diskSpaceChannel = "photoframe/diskspace"

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
    }
}

package com.photoframe.mobile_app

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Environment
import android.os.StatFs
import android.provider.DocumentsContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts three small platform channels:
 *
 * - "photoframe/diskspace", used by
 *   `lib/services/cache/image_cache_manager.dart` to cap the on-disk image
 *   cache against the device's actually free storage (see
 *   docs/DECISIONS.md, ADR-010).
 * - "photoframe/kiosk", used by
 *   `lib/services/kiosk/kiosk_mode_controller.dart` to enter/leave Android's
 *   screen-pinning ("Lock Task") mode while the slideshow is showing (see
 *   docs/DECISIONS.md ADR-004: Kiosk/Autostart limits).
 * - "photoframe/saf", used by
 *   `lib/features/sources/local/local_folder_source.dart` to pick a folder
 *   via the Storage Access Framework ourselves, instead of through
 *   `file_picker`: `file_picker`'s `getDirectoryPath()` resolves the picked
 *   tree Uri to a plain path string but never calls
 *   `ContentResolver.takePersistableUriPermission` on it, nor exposes the
 *   Uri to Dart at all - so the grant only lasted for the current process,
 *   and a folder that looked "connected" right after being picked silently
 *   lost read access on the next app restart. This channel takes the
 *   persistable permission itself right after the pick and returns the tree
 *   Uri alongside the resolved path.
 *
 * A dedicated pub.dev package was deliberately not added for any of these -
 * each wraps a small amount of stable Android SDK API
 * (`android.os.StatFs`, `Activity.startLockTask`/`stopLockTask`,
 * `Intent.ACTION_OPEN_DOCUMENT_TREE`/`ContentResolver`), and this project
 * already needs its own MethodChannel surface for platform-specific
 * behaviour, so all three follow the same pattern rather than pulling in a
 * small, potentially unmaintained third-party plugin.
 */
class MainActivity : FlutterActivity() {
    private val diskSpaceChannel = "photoframe/diskspace"
    private val kioskChannel = "photoframe/kiosk"
    private val safChannel = "photoframe/saf"

    private var pendingDirectoryPickResult: MethodChannel.Result? = null

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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, safChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickDirectoryTree" -> {
                        if (pendingDirectoryPickResult != null) {
                            // Guards against a double-tap starting a second
                            // picker while the first is still awaiting its
                            // activity result - there is only one pending
                            // callback slot.
                            result.error("ALREADY_PICKING", "A directory pick is already in progress", null)
                            return@setMethodCallHandler
                        }
                        pendingDirectoryPickResult = result
                        try {
                            startActivityForResult(
                                Intent(Intent.ACTION_OPEN_DOCUMENT_TREE),
                                PICK_DIRECTORY_TREE_REQUEST_CODE,
                            )
                        } catch (e: Exception) {
                            pendingDirectoryPickResult = null
                            result.error("PICK_DIRECTORY_FAILED", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        // Must run first so plugins that register their own
        // ActivityResultListener (image_picker, file_picker, ...) still get
        // their callbacks - this override only additionally intercepts the
        // request code this Activity itself started below.
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != PICK_DIRECTORY_TREE_REQUEST_CODE) return

        val pending = pendingDirectoryPickResult ?: return
        pendingDirectoryPickResult = null

        val treeUri = data?.data
        if (resultCode != Activity.RESULT_OK || treeUri == null) {
            // User backed out of the picker - not an error, mirrors
            // `file_picker`'s `null` return on cancellation.
            pending.success(null)
            return
        }

        try {
            val takeFlags = data.flags and
                (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            contentResolver.takePersistableUriPermission(treeUri, takeFlags)

            val path = resolvePathFromTreeUri(treeUri)
            if (path == null) {
                pending.error("UNRESOLVABLE_PATH", "Could not resolve a filesystem path for $treeUri", null)
                return
            }
            pending.success(mapOf("uri" to treeUri.toString(), "path" to path))
        } catch (e: Exception) {
            pending.error("TAKE_PERSISTABLE_PERMISSION_FAILED", e.message, null)
        }
    }

    /**
     * Mirrors the heuristic `file_picker`'s internal `FileUtils` uses to turn
     * a tree Uri into a path: a tree document id looks like
     * `primary:DCIM/Camera` for the primary shared storage volume, or
     * `1234-5678:Folder` for a removable/secondary volume. Not guaranteed
     * correct on every OEM/volume layout (same caveat that code carries
     * too), but keeps the resolved path identical to what this app
     * previously got from `file_picker`, so already-configured sources are
     * unaffected by this change.
     */
    private fun resolvePathFromTreeUri(treeUri: Uri): String? {
        val docId = try {
            DocumentsContract.getTreeDocumentId(treeUri)
        } catch (e: Exception) {
            return null
        }
        val split = docId.split(":", limit = 2)
        val volumeId = split.getOrNull(0) ?: return null
        val relativePath = split.getOrNull(1) ?: ""
        val base = if (volumeId.equals("primary", ignoreCase = true)) {
            Environment.getExternalStorageDirectory().path
        } else {
            "/storage/$volumeId"
        }
        return if (relativePath.isEmpty()) base else "$base/$relativePath"
    }

    private companion object {
        const val PICK_DIRECTORY_TREE_REQUEST_CODE = 4271
    }
}

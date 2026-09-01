import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

import '../../sources/shared_album/shared_album_photo_source.dart';

/// Lets the user pick one or more photos from the device gallery/camera and
/// upload them to a [SharedAlbumPhotoSource] (i.e. a relay-backed pairing).
class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key, required this.source, this.imagePicker});

  final SharedAlbumPhotoSource source;

  /// Overridable for tests.
  final ImagePicker? imagePicker;

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadStatus {
  _UploadStatus(this.file);
  final File file;
  bool done = false;
  String? error;
}

class _UploadScreenState extends State<UploadScreen> {
  ImagePicker get _picker => widget.imagePicker ?? ImagePicker();

  final List<_UploadStatus> _queue = [];
  bool _uploading = false;

  Future<void> _pickAndQueue() async {
    final picked = await _picker.pickMultiImage();
    if (picked.isEmpty) return;
    setState(() {
      _queue.addAll(picked.map((x) => _UploadStatus(File(x.path))));
    });
    unawaited(_processQueue());
  }

  Future<void> _pickFromCamera() async {
    // A user who skipped/never saw the onboarding permissions step (or
    // denied it there) has no other prompt before reaching this button, so
    // this is the just-in-time fallback: request here rather than letting
    // `image_picker` invoke the camera intent without the permission ever
    // having been granted, which fails silently instead of showing the
    // system dialog. Mirrors the request/openAppSettings fallback used in
    // `onboarding_screen.dart`'s `_PermissionsStep`.
    final status = await ph.Permission.camera.request();
    if (!mounted) return;
    if (!status.isGranted) {
      if (status.isPermanentlyDenied) {
        await ph.openAppSettings();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kamera-Berechtigung wird benötigt, um Fotos aufzunehmen.')),
        );
      }
      return;
    }

    final picked = await _picker.pickImage(source: ImageSource.camera);
    if (picked == null) return;
    setState(() => _queue.add(_UploadStatus(File(picked.path))));
    unawaited(_processQueue());
  }

  Future<void> _processQueue() async {
    if (_uploading) return;
    _uploading = true;
    for (final status in _queue.where((s) => !s.done && s.error == null)) {
      final result = await widget.source.uploadImage(status.file);
      if (!mounted) return;
      setState(() {
        result.when(
          onOk: (_) => status.done = true,
          onErr: (failure) => status.error = failure.message,
        );
      });
    }
    _uploading = false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Fotos hochladen')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _pickAndQueue,
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Aus Galerie wählen'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickFromCamera,
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Foto aufnehmen'),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _queue.isEmpty
                ? const Center(child: Text('Noch keine Fotos ausgewählt.'))
                : ListView.builder(
                    itemCount: _queue.length,
                    itemBuilder: (context, index) {
                      final status = _queue[index];
                      return ListTile(
                        leading: Image.file(status.file, width: 48, height: 48, fit: BoxFit.cover),
                        title: Text(status.file.uri.pathSegments.last),
                        trailing: status.error != null
                            ? Icon(Icons.error, color: Theme.of(context).colorScheme.error)
                            : status.done
                                ? const Icon(Icons.check_circle, color: Colors.green)
                                : const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                        subtitle: status.error != null ? Text(status.error!) : null,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/photo_source.dart';
import '../mock/mock_photo_source.dart';

/// Registered [PhotoSource] instances the app currently knows about.
///
/// This is a deliberately small stand-in for the real
/// `source_registry.dart` (per `docs/PLAN.md`) that a parallel agent is
/// expected to build alongside the concrete `SmbPhotoSource`/
/// `NextcloudPhotoSource`/`LocalFolderSource` implementations. Until those
/// land, the registry starts out with a single [MockPhotoSource] so the
/// Settings/Sources UI and the slideshow screen have something real to list
/// and render.
class SourcesController extends Notifier<List<PhotoSource>> {
  @override
  List<PhotoSource> build() {
    ref.onDispose(() {
      for (final source in state) {
        // Fire-and-forget: dispose() is async but Notifier.onDispose isn't.
        unawaited(source.dispose());
      }
    });
    return [MockPhotoSource()];
  }

  void add(PhotoSource source) {
    state = [...state, source];
  }

  void removeById(String id) {
    state = state.where((s) => s.id != id).toList();
  }
}

final NotifierProvider<SourcesController, List<PhotoSource>> sourcesProvider =
    NotifierProvider<SourcesController, List<PhotoSource>>(
  SourcesController.new,
);

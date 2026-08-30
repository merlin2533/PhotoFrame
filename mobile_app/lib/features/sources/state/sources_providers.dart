import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../services/storage/secure_credential_store.dart';
import '../domain/photo_source.dart';
import '../mock/mock_photo_source.dart';

/// Shared [SecureCredentialStore] instance for source-form widgets (SMB
/// password, Nextcloud app/share password, ...) - see that class's doc
/// comment for why credentials never go through `shared_preferences`.
final Provider<SecureCredentialStore> secureCredentialStoreProvider =
    Provider<SecureCredentialStore>((ref) => SecureCredentialStore());

/// Generates stable ids for newly configured [PhotoSource] instances.
/// Exposed as a provider (rather than a bare top-level `Uuid()`) purely so
/// tests can override it deterministically if ever needed.
final Provider<Uuid> sourceIdGeneratorProvider = Provider<Uuid>((ref) => const Uuid());

/// Registered [PhotoSource] instances the app currently knows about.
///
/// This is a deliberately small stand-in for the real
/// `source_registry.dart` (per `docs/PLAN.md`): it holds sources only for
/// the lifetime of the app process (no persistence of the *non-secret*
/// source configuration yet - only credentials are durably persisted, via
/// [SecureCredentialStore]). The registry starts out with a single
/// [MockPhotoSource] so the Settings/Sources UI and the slideshow screen
/// have something real to list and render even before the user configures
/// anything.
class SourcesController extends Notifier<List<PhotoSource>> {
  @override
  List<PhotoSource> build() {
    ref.onDispose(() {
      for (final source in state) {
        // Fire-and-forget: dispose() is async but Notifier.onDispose isn't.
        unawaited(source.dispose());
      }
    });
    final initial = [MockPhotoSource()];
    // Source configuration isn't persisted across restarts yet (see class
    // doc), which means every id previously written to the secure keychain
    // by a config form is unreachable from this point on - reclaim them now
    // rather than letting credentials accumulate forever. Once real
    // persistence lands, this must be called with the *actually restored*
    // ids instead of just the ones present at this exact moment.
    unawaited(
      ref.read(secureCredentialStoreProvider).pruneOrphans(initial.map((s) => s.id).toSet()),
    );
    return initial;
  }

  void add(PhotoSource source) {
    state = [...state, source];
  }

  void removeById(String id) {
    final removed = state.where((s) => s.id == id);
    state = state.where((s) => s.id != id).toList();
    for (final source in removed) {
      unawaited(source.dispose());
      // Best-effort: also drop any stored credentials for this source so
      // they don't linger in the secure keychain after the source itself
      // is gone.
      unawaited(
        ref.read(secureCredentialStoreProvider).deleteAllForSource(source.id),
      );
    }
  }
}

final NotifierProvider<SourcesController, List<PhotoSource>> sourcesProvider =
    NotifierProvider<SourcesController, List<PhotoSource>>(
  SourcesController.new,
);

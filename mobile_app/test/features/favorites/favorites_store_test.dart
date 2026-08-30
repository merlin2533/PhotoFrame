import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/favorites/domain/favorites_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('FavoritesStore', () {
    test('starts empty and not-yet-loaded before load()', () {
      final store = FavoritesStore();
      expect(store.isLoaded, isFalse);
      expect(store.favoriteIds, isEmpty);
      expect(store.isFavorite('a'), isFalse);
    });

    test('load() marks the store as loaded even with nothing persisted', () async {
      final store = FavoritesStore();
      await store.load();
      expect(store.isLoaded, isTrue);
      expect(store.favoriteIds, isEmpty);
    });

    test('toggleFavorite adds an id and isFavorite reflects it', () async {
      final store = FavoritesStore();
      await store.load();

      await store.toggleFavorite('src-1:abc123');

      expect(store.isFavorite('src-1:abc123'), isTrue);
      expect(store.favoriteIds, {'src-1:abc123'});
    });

    test('toggleFavorite twice removes the id again', () async {
      final store = FavoritesStore();
      await store.load();

      await store.toggleFavorite('id-1');
      await store.toggleFavorite('id-1');

      expect(store.isFavorite('id-1'), isFalse);
      expect(store.favoriteIds, isEmpty);
    });

    test('setFavorite(id, true/false) sets an explicit state idempotently', () async {
      final store = FavoritesStore();
      await store.load();

      await store.setFavorite('id-1', true);
      await store.setFavorite('id-1', true); // no-op, already favorited
      expect(store.isFavorite('id-1'), isTrue);
      expect(store.favoriteIds.length, 1);

      await store.setFavorite('id-1', false);
      expect(store.isFavorite('id-1'), isFalse);
    });

    test('notifies listeners on toggle', () async {
      final store = FavoritesStore();
      await store.load();

      var notifications = 0;
      store.addListener(() => notifications++);

      await store.toggleFavorite('id-1');

      expect(notifications, 1);
    });

    test('changes stream emits the current favorite set after each mutation', () async {
      final store = FavoritesStore();
      final emissions = <Set<String>>[];
      final sub = store.changes.listen(emissions.add);

      await store.load(); // emits once (empty set)
      await store.toggleFavorite('id-1'); // emits {'id-1'}
      await store.toggleFavorite('id-2'); // emits {'id-1', 'id-2'}
      // The broadcast stream dispatches asynchronously (a microtask per
      // event); let the last one flush before cancelling, otherwise
      // `sub.cancel()` can race ahead of it and drop the final emission.
      await Future<void>.delayed(Duration.zero);

      await sub.cancel();

      expect(emissions.length, 3);
      expect(emissions.last, {'id-1', 'id-2'});
    });

    test('persists across separate FavoritesStore instances sharing prefs', () async {
      final prefs = await SharedPreferences.getInstance();

      final store1 = FavoritesStore(prefs: prefs);
      await store1.load();
      await store1.toggleFavorite('persisted-id');

      final store2 = FavoritesStore(prefs: prefs);
      await store2.load();

      expect(store2.isFavorite('persisted-id'), isTrue);
    });

    test('does not persist/notify when setFavorite is a no-op', () async {
      final store = FavoritesStore();
      await store.load();

      var notifications = 0;
      store.addListener(() => notifications++);

      await store.setFavorite('never-added', false); // already not favorited

      expect(notifications, 0);
      expect(store.isFavorite('never-added'), isFalse);
    });
  });
}

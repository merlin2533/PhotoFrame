import 'package:mobile_app/features/slideshow/domain/shuffle_bag.dart';
import 'package:test/test.dart';

void main() {
  group('ShuffleBag', () {
    test('draws every item exactly once per cycle', () {
      final bag = ShuffleBag<int>(List.generate(20, (i) => i), noRepeatWindow: 3);

      final drawnInCycle = <int>{};
      for (var i = 0; i < 20; i++) {
        final item = bag.next();
        expect(
          drawnInCycle.contains(item),
          isFalse,
          reason: 'item $item repeated within a single cycle',
        );
        drawnInCycle.add(item);
      }
      expect(drawnInCycle.length, 20);
    });

    test('does not repeat the same item within the no-repeat window', () {
      const window = 5;
      final bag = ShuffleBag<int>(List.generate(20, (i) => i), noRepeatWindow: window);

      final history = <int>[];
      for (var i = 0; i < 200; i++) {
        final item = bag.next();
        final recentBefore = history.length <= window
            ? history
            : history.sublist(history.length - window);
        expect(
          recentBefore.contains(item),
          isFalse,
          reason:
              'item $item repeated within the last $window draws: $recentBefore',
        );
        history.add(item);
      }
    });

    test('starts a fresh cycle once the working list is exhausted', () {
      final bag = ShuffleBag<int>([1, 2, 3], noRepeatWindow: 1);
      final firstCycle = List.generate(3, (_) => bag.next());
      expect(firstCycle.toSet(), {1, 2, 3});

      final secondCycle = List.generate(3, (_) => bag.next());
      expect(secondCycle.toSet(), {1, 2, 3});
    });

    test('updateItems drops stale queued items and reshuffles when needed', () {
      final bag = ShuffleBag<int>([1, 2, 3, 4], noRepeatWindow: 1);
      bag.updateItems([1, 2]);

      final drawn = <int>{bag.next(), bag.next(), bag.next()};
      expect(drawn, {1, 2});
    });

    test('throws on empty item list', () {
      expect(() => ShuffleBag<int>(<int>[]), throwsArgumentError);
    });

    test('supports a custom keyOf for non-comparable items', () {
      final items = [
        _Item('a'),
        _Item('b'),
        _Item('c'),
      ];
      final bag = ShuffleBag<_Item>(
        items,
        noRepeatWindow: 1,
        keyOf: (item) => item.id,
      );

      final drawnIds = List.generate(3, (_) => bag.next().id).toSet();
      expect(drawnIds, {'a', 'b', 'c'});
    });
  });
}

class _Item {
  _Item(this.id);
  final String id;
}

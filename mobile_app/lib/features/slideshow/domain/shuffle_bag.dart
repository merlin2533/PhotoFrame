import 'dart:math';

/// Draws elements from a fixed working list without repetition within a
/// cycle ("shuffle bag" / "no-repeat shuffle"), while also enforcing that
/// the same element cannot reappear within the last [noRepeatWindow] draws
/// even across a cycle boundary.
///
/// Deliberately generic and decoupled from any specific domain type or
/// index-based storage: it is handed a list of items (e.g. `PoolEntry`s, or
/// plain ids) by the caller - typically a `WorkingSetPool` - and only
/// requires that items be usable as `Map`/`Set` keys (via `==`/`hashCode`),
/// or that a [keyOf] function is supplied to derive a stable key when `T`
/// itself isn't suitable (e.g. mutable objects).
///
/// Algorithm:
///  - Internally keeps a shuffled queue of not-yet-drawn items for the
///    current cycle ("the bag").
///  - [next] pops from the queue. When the queue is empty, a new cycle
///    starts: the source list is reshuffled and refilled, skipping any item
///    that would violate the [noRepeatWindow] rule against the most
///    recently drawn items, when a valid alternative exists.
///  - A rolling history of the last [noRepeatWindow] drawn keys is kept to
///    enforce the "not the same item within the last N draws" rule across
///    cycle boundaries.
///
/// State is entirely in-memory here; a caller that wants the permutation to
/// survive process restarts is expected to persist [history] (or simply
/// accept a fresh shuffle on restart) - this class does not do its own I/O.
class ShuffleBag<T> {
  ShuffleBag(
    List<T> items, {
    this.noRepeatWindow = 5,
    Object Function(T item)? keyOf,
    Random? random,
  })  : _keyOf = keyOf ?? ((item) => item as Object),
        _random = random ?? Random(),
        _source = List<T>.from(items) {
    if (_source.isEmpty) {
      throw ArgumentError.value(items, 'items', 'must not be empty');
    }
    _startNewCycle();
  }

  /// How many of the most recent draws must not repeat an item, in addition
  /// to the "no repeat within a single cycle" guarantee. E.g. with
  /// `noRepeatWindow = 5`, an item shown just now cannot reappear until at
  /// least 5 other items have been shown, even if that means peeking across
  /// a cycle boundary.
  final int noRepeatWindow;

  final Object Function(T item) _keyOf;
  final Random _random;

  /// The full working list this bag draws from. Replaceable via
  /// [updateItems] when the underlying pool changes.
  List<T> _source;

  /// Items remaining to be drawn in the current cycle, in draw order.
  final List<T> _queue = [];

  /// Rolling history of recently drawn item keys, most recent last. Bounded
  /// to [noRepeatWindow] entries.
  final List<Object> _history = [];

  /// Read-only view of the recent-draw history (most recent last).
  List<Object> get history => List.unmodifiable(_history);

  /// Replaces the working list, e.g. after the `WorkingSetPool` admitted or
  /// evicted entries. The current in-progress cycle's remaining queue is
  /// filtered to drop items no longer present; if that empties the queue, a
  /// fresh cycle is started immediately from the new list.
  void updateItems(List<T> items) {
    if (items.isEmpty) {
      throw ArgumentError.value(items, 'items', 'must not be empty');
    }
    _source = List<T>.from(items);
    final validKeys = _source.map(_keyOf).toSet();
    _queue.removeWhere((item) => !validKeys.contains(_keyOf(item)));
    if (_queue.isEmpty) {
      _startNewCycle();
    }
  }

  void _startNewCycle() {
    final shuffled = List<T>.from(_source)..shuffle(_random);
    _queue
      ..clear()
      ..addAll(shuffled);
  }

  /// Draws the next item, honouring both "no repeat within this cycle" and
  /// the [noRepeatWindow] recent-history rule.
  ///
  /// When [noRepeatWindow] cannot be fully satisfied (e.g. the working list
  /// is smaller than the window), the item that violates the rule least
  /// recently is chosen rather than failing - a strict guarantee is only
  /// possible when `_source.length > noRepeatWindow`.
  T next() {
    if (_queue.isEmpty) {
      _startNewCycle();
    }

    final recentKeys = _history.length <= noRepeatWindow
        ? _history.toSet()
        : _history.sublist(_history.length - noRepeatWindow).toSet();

    // Prefer the first queued item that doesn't violate the recent-history
    // rule; fall back to the front of the queue if every candidate would
    // violate it (small working set / large window).
    var chosenIndex = _queue.indexWhere(
      (item) => !recentKeys.contains(_keyOf(item)),
    );
    if (chosenIndex == -1) {
      chosenIndex = 0;
    }

    final chosen = _queue.removeAt(chosenIndex);
    _recordShown(chosen);
    return chosen;
  }

  void _recordShown(T item) {
    _history.add(_keyOf(item));
    if (_history.length > noRepeatWindow) {
      _history.removeRange(0, _history.length - noRepeatWindow);
    }
  }

  /// Number of items left to draw before the current cycle is exhausted.
  int get remainingInCycle => _queue.length;
}

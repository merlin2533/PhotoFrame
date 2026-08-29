/// Cooperative cancellation primitive used by long-running operations such
/// as folder/image listing or cache fetches (see `PhotoSource`).
///
/// This mirrors the classic "cancellation token" pattern: callers create a
/// [CancellationTokenSource], hand its [CancellationTokenSource.token] to an
/// operation, and call [CancellationTokenSource.cancel] to request that the
/// operation stop. The operation itself must periodically check
/// [CancellationToken.isCancelled] or call
/// [CancellationToken.throwIfCancelled] between steps - cancellation is
/// cooperative, not preemptive.
class CancellationToken {
  CancellationToken._(this._source);

  final CancellationTokenSource _source;

  /// Whether cancellation has been requested.
  bool get isCancelled => _source._isCancelled;

  /// Throws a [CancelledException] if cancellation has been requested.
  void throwIfCancelled() {
    if (isCancelled) {
      throw const CancelledException();
    }
  }

  /// A token that can never be cancelled. Convenient default for call sites
  /// that don't need cancellation support.
  static final CancellationToken never =
      CancellationTokenSource().token;
}

/// Owns a [CancellationToken] and controls when it becomes cancelled.
class CancellationTokenSource {
  CancellationTokenSource() {
    token = CancellationToken._(this);
  }

  bool _isCancelled = false;

  /// The token to hand to cancellable operations.
  late final CancellationToken token;

  /// Requests cancellation. Idempotent - calling this more than once has no
  /// additional effect.
  void cancel() {
    _isCancelled = true;
  }
}

/// Thrown by [CancellationToken.throwIfCancelled] when the associated
/// operation has been cancelled.
class CancelledException implements Exception {
  const CancelledException([this.message = 'Operation was cancelled']);

  final String message;

  @override
  String toString() => 'CancelledException: $message';
}

import '../errors/failure.dart';

/// A minimal `Result<T>` type representing either success ([Ok]) or
/// failure ([Err]) without relying on exceptions for expected error paths.
///
/// Kept dependency-free (no external functional-programming package) so it
/// stays easy to reason about across the whole codebase.
sealed class Result<T> {
  const Result();

  /// Wraps a success [value].
  factory Result.ok(T value) = Ok<T>;

  /// Wraps a [failure].
  factory Result.err(Failure failure) = Err<T>;

  bool get isOk => this is Ok<T>;

  bool get isErr => this is Err<T>;

  /// Returns the success value or `null` if this is an [Err].
  T? get valueOrNull => switch (this) {
        Ok<T>(value: final v) => v,
        Err<T>() => null,
      };

  /// Returns the failure or `null` if this is an [Ok].
  Failure? get failureOrNull => switch (this) {
        Ok<T>() => null,
        Err<T>(failure: final f) => f,
      };

  /// Transforms the success value, leaving a failure untouched.
  Result<R> map<R>(R Function(T value) transform) => switch (this) {
        Ok<T>(value: final v) => Result.ok(transform(v)),
        Err<T>(failure: final f) => Result.err(f),
      };

  /// Chains another [Result]-producing operation on success.
  Result<R> flatMap<R>(Result<R> Function(T value) transform) =>
      switch (this) {
        Ok<T>(value: final v) => transform(v),
        Err<T>(failure: final f) => Result.err(f),
      };

  /// Transforms the failure, leaving a success untouched.
  Result<T> mapError(Failure Function(Failure failure) transform) =>
      switch (this) {
        Ok<T>() => this,
        Err<T>(failure: final f) => Result.err(transform(f)),
      };

  /// Reduces this [Result] to a single value by handling both branches.
  R fold<R>(
    R Function(T value) onOk,
    R Function(Failure failure) onErr,
  ) =>
      switch (this) {
        Ok<T>(value: final v) => onOk(v),
        Err<T>(failure: final f) => onErr(f),
      };

  /// Returns the success value, or [fallback] if this is an [Err].
  T getOrElse(T Function(Failure failure) fallback) => switch (this) {
        Ok<T>(value: final v) => v,
        Err<T>(failure: final f) => fallback(f),
      };

  /// Runs [onOk] or [onErr] purely for side effects, returning this
  /// [Result] unchanged so calls can be chained.
  Result<T> when({
    void Function(T value)? onOk,
    void Function(Failure failure)? onErr,
  }) {
    switch (this) {
      case Ok<T>(value: final v):
        onOk?.call(v);
      case Err<T>(failure: final f):
        onErr?.call(f);
    }
    return this;
  }
}

class Ok<T> extends Result<T> {
  const Ok(this.value);

  final T value;

  @override
  bool operator ==(Object other) => other is Ok<T> && other.value == value;

  @override
  int get hashCode => Object.hash(Ok<T>, value);

  @override
  String toString() => 'Ok($value)';
}

class Err<T> extends Result<T> {
  const Err(this.failure);

  final Failure failure;

  @override
  bool operator ==(Object other) =>
      other is Err<T> && other.failure == failure;

  @override
  int get hashCode => Object.hash(Err<T>, failure);

  @override
  String toString() => 'Err($failure)';
}

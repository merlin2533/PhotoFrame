/// Common error taxonomy used across the app instead of raw exceptions.
///
/// Every operation that can fail in an expected way (network, auth,
/// permissions, ...) should surface one of these via [Result.err] rather
/// than throwing. Unexpected/programmer errors may still throw normally.
sealed class Failure {
  const Failure(this.message, {this.cause});

  /// Human-readable (developer-facing) description of what went wrong.
  final String message;

  /// Optional underlying error/exception that triggered this failure.
  final Object? cause;

  @override
  String toString() => '$runtimeType: $message';
}

/// Authentication failed or credentials are missing/expired.
class AuthError extends Failure {
  const AuthError(super.message, {super.cause});
}

/// Generic network/transport failure (DNS, connection refused, socket, ...).
class NetworkError extends Failure {
  const NetworkError(super.message, {super.cause});
}

/// The requested resource (folder, item, source, endpoint) does not exist.
class NotFound extends Failure {
  const NotFound(super.message, {super.cause});
}

/// The app lacks an OS or application-level permission needed to proceed.
class PermissionDenied extends Failure {
  const PermissionDenied(super.message, {super.cause});
}

/// The operation or feature is not supported by this source/platform.
class Unsupported extends Failure {
  const Unsupported(super.message, {super.cause});
}

/// A storage/quota limit was exceeded (disk space, server quota, ...).
class QuotaExceeded extends Failure {
  const QuotaExceeded(super.message, {super.cause});
}

/// The operation did not complete within the allotted time.
class Timeout extends Failure {
  const Timeout(super.message, {super.cause});
}

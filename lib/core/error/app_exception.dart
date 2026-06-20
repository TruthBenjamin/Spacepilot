sealed class AppException implements Exception {
  const AppException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'AppException(message: $message, cause: $cause)';
}

final class UnknownAppException extends AppException {
  const UnknownAppException(super.message, {super.cause});
}

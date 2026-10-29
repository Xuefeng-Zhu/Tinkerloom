import 'dart:io';

/// Explicit opt-in runner only: Flutter test's normal HTTP override returns 400.
/// This scoped override restores the caller's override when its Future settles.
Future<T> withRealHttp<T>(Future<T> Function() operation) =>
    HttpOverrides.runWithHttpOverrides(operation, _RealHttp());

class _RealHttp extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context);
}

import 'package:tinkerloom_client/tinkerloom_client.dart';

/// Public application configuration only. No service key belongs in Flutter.
const appwriteEndpoint = String.fromEnvironment('APPWRITE_ENDPOINT');
const appwriteProjectId = String.fromEnvironment('APPWRITE_PROJECT_ID');
const appwriteFunctionId = String.fromEnvironment(
  'APPWRITE_FUNCTION_ID',
  defaultValue: 'tinkerloom-core',
);

late Client client;

final _initialization = ClientInitialization(() async {
  if (appwriteEndpoint.isEmpty || appwriteProjectId.isEmpty) {
    throw StateError(
      'Configure the Appwrite endpoint and project before opening Tinkerloom.',
    );
  }
  client = Client(
    appwriteEndpoint,
    projectId: appwriteProjectId,
    functionId: appwriteFunctionId,
  );
  return client.auth;
});

Future<void> initializeClient() => _initialization.initialize();

/// Retains one transport during explicit startup retries. An ambiguous network
/// failure never clears a saved account session or creates another account.
class ClientInitialization {
  ClientInitialization(
    this.createSessionManager, {
    this.validationTimeout = const Duration(seconds: 45),
  });

  final Future<ClientAuth> Function() createSessionManager;
  final Duration validationTimeout;
  ClientAuth? _auth;
  Future<void>? _pending;

  Future<void> initialize() =>
      _pending ??= _initialize().whenComplete(() => _pending = null);

  Future<void> _initialize() async {
    final auth = _auth ??= await createSessionManager();
    await auth.restore().timeout(validationTimeout);
  }
}

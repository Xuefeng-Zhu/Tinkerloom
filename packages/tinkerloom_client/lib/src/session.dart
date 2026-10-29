part of '../tinkerloom_client.dart';

/// Appwrite owns session persistence. This notifier contains no service key.
class ClientAuth extends ChangeNotifier {
  ClientAuth({
    Future<Map<String, dynamic>?> Function()? restore,
    Future<Map<String, dynamic>> Function(String, String)? signIn,
    Future<Map<String, dynamic>> Function(String, String)? signUp,
    Future<void> Function()? signOut,
  }) : _restore = restore,
       _signIn = signIn,
       _signUp = signUp,
       _signOut = signOut;
  final Future<Map<String, dynamic>?> Function()? _restore;
  final Future<Map<String, dynamic>> Function(String, String)? _signIn, _signUp;
  final Future<void> Function()? _signOut;
  String? _actorId, _email;
  String? get actorId => _actorId;
  String? get userIdentifier => actorId;
  String? get email => _email;
  bool get isAuthenticated => actorId != null;
  Listenable get authInfoListenable => this;
  bool _restored = false;
  Future<void>? _restoring;
  void setSession(Map<String, dynamic>? user) {
    final id = user == null ? null : _id(user['id']);
    final email = user?['email'] as String?;
    if (id == _actorId && email == _email) return;
    _actorId = id;
    _email = email;
    notifyListeners();
  }

  Future<void> restore() =>
      _restoring ??= _restoreOnce().whenComplete(() => _restoring = null);
  Future<void> _restoreOnce() async {
    if (_restored) return;
    setSession(await _restore?.call());
    _restored = true;
  }

  Future<void> initialize() => restore();
  Future<void> validateAuthentication({Duration? timeout}) => restore();
  Future<void> signIn(String email, String password) async {
    if (_signIn == null)
      throw NestError(
        category: 'configuration',
        message: 'Sign-in is unavailable.',
      );
    setSession(await _signIn(email, password));
    _restored = true;
  }

  Future<void> signUp(String email, String password) async {
    if (_signUp == null)
      throw NestError(
        category: 'configuration',
        message: 'Registration is unavailable.',
      );
    await _signUp(email, password);
    // Account creation does not establish an authenticated Appwrite session.
    await signIn(email, password);
  }

  Future<void> signOutDevice() async {
    await _signOut?.call();
    setSession(null);
    _restored = false;
  }
}

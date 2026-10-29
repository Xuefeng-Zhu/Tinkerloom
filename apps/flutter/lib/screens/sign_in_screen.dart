import 'package:flutter/material.dart';

import '../client.dart';

import 'package:tinkerloom_client/tinkerloom_client.dart';

class SignInScreen extends StatefulWidget {
  final Widget child;
  const SignInScreen({super.key, required this.child});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  bool _isSignedIn = false;
  final _focusScope = FocusScopeNode(debugLabel: 'Tinkerloom authentication');

  @override
  void initState() {
    super.initState();
    client.auth.authInfoListenable.addListener(_updateSignedInState);
    _isSignedIn = client.auth.isAuthenticated;
  }

  @override
  void dispose() {
    client.auth.authInfoListenable.removeListener(_updateSignedInState);
    _focusScope.dispose();
    super.dispose();
  }

  void _updateSignedInState() {
    if (!mounted) return;
    final signedIn = client.auth.isAuthenticated;
    if (signedIn == _isSignedIn) return;
    // A Navigator's Focus nodes are temporarily parked on the root while its
    // globally keyed tree is deactivated. Native view-focus traversal must not
    // revisit their detached render boxes while the auth screen replaces it.
    for (final node in _focusScope.descendants.toList()) {
      node.canRequestFocus = false;
      node.skipTraversal = true;
    }
    _focusScope.unfocus();
    setState(() {
      _isSignedIn = signedIn;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    final content = _isSignedIn
        ? widget.child
        : Navigator(
            // MaterialApp.router does not supply a Navigator above this gate.
            // Login text selection and the SDK's dialogs need an Overlay even
            // before the authenticated application's Navigator is mounted.
            pages: [
              MaterialPage<void>(
                key: const ValueKey('sign-in'),
                child: Center(
                  child: SignInWidget(
                    client: client,
                    onAuthenticated: () {
                      if (!mounted) return;
                      context.showSnackBar(
                        message: 'User authenticated.',
                        backgroundColor: colors.primaryContainer,
                        foregroundColor: colors.onPrimaryContainer,
                      );
                    },
                    onError: (error) {
                      if (!mounted) return;
                      context.showSnackBar(
                        message: 'Authentication failed: $error',
                        backgroundColor: colors.errorContainer,
                        foregroundColor: colors.onErrorContainer,
                      );
                    },
                  ),
                ),
              ),
            ],
            onDidRemovePage: (_) {},
          );
    return FocusScope(node: _focusScope, child: content);
  }
}

extension on BuildContext {
  void showSnackBar({
    required String message,
    required Color backgroundColor,
    required Color foregroundColor,
  }) {
    ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(
        content: Text(message, style: TextStyle(color: foregroundColor)),
        backgroundColor: backgroundColor,
        duration: const Duration(seconds: 5),
      ),
    );
  }
}

/// The original authentication gate uses the same navigator and focus handling;
/// this form delegates account sessions to Appwrite rather than Serverpod.
class SignInWidget extends StatefulWidget {
  const SignInWidget({
    super.key,
    required this.client,
    this.onAuthenticated,
    this.onError,
  });
  final Client client;
  final VoidCallback? onAuthenticated;
  final void Function(Object)? onError;
  @override
  State<SignInWidget> createState() => _SignInWidgetState();
}

class _SignInWidgetState extends State<SignInWidget> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool busy = false;
  bool creating = false;
  String? error;
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (creating) {
        await widget.client.auth.signUp(email.text.trim(), password.text);
      } else {
        await widget.client.auth.signIn(email.text.trim(), password.text);
      }
      if (mounted) widget.onAuthenticated?.call();
    } catch (issue) {
      if (mounted) {
        setState(
          () => error =
              'Could not sign in. Check your account details and connection.',
        );
        widget.onError?.call(issue);
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Material(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: AutofillGroup(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Tinkerloom',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 24),
              TextField(
                controller: email,
                enabled: !busy,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.username],
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: password,
                enabled: !busy,
                obscureText: true,
                autofillHints: const [AutofillHints.password],
                decoration: const InputDecoration(labelText: 'Password'),
                onSubmitted: (_) => submit(),
              ),
              const SizedBox(height: 20),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(error!, semanticsLabel: error),
                ),
              ElevatedButton(
                onPressed: busy ? null : submit,
                child: Text(
                  busy
                      ? 'Please wait…'
                      : creating
                      ? 'Create account'
                      : 'Sign in',
                ),
              ),
              TextButton(
                onPressed: busy
                    ? null
                    : () => setState(() => creating = !creating),
                child: Text(
                  creating
                      ? 'Already have an account? Sign in'
                      : 'Create an account',
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

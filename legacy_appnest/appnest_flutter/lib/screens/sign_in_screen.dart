import 'package:flutter/material.dart';
import 'package:serverpod_auth_idp_flutter/serverpod_auth_idp_flutter.dart';

import '../client.dart';

class SignInScreen extends StatefulWidget {
  final Widget child;
  const SignInScreen({super.key, required this.child});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  bool _isSignedIn = false;
  final _focusScope = FocusScopeNode(debugLabel: 'AppNest authentication');

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

import 'dart:async';

import 'package:appnest_client/appnest_client.dart';
import 'package:flutter/material.dart';

/// Uses transport types, never exception text (which is minified on the web).
class HomeLoadFailure extends StatelessWidget {
  const HomeLoadFailure({
    super.key,
    required this.error,
    required this.onRetry,
  });

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final network =
        error is ServerpodClientNetworkException || error is TimeoutException;
    final unauthorized = error is ServerpodClientUnauthorized;
    final forbidden =
        error is ServerpodClientForbidden ||
        error is ServerpodClientNotFound ||
        (error is NestError && (error as NestError).category == 'forbidden');
    final local = const {
      'localhost',
      '127.0.0.1',
      '::1',
    }.contains(Uri.base.host);
    final title = network
        ? 'Can’t connect to AppNest'
        : unauthorized
        ? 'Please sign in again'
        : forbidden
        ? 'Workspace access changed'
        : 'Couldn’t load your workspace';
    final message = network
        ? local
              ? 'The local AppNest server may be stopped. Start it, then retry.'
              : 'Check your connection and try again. The server may be temporarily unavailable.'
        : unauthorized
        ? 'Your session could not be verified. Use your account menu to sign out and sign in again.'
        : forbidden
        ? 'Your current account may no longer have access. Retry to refresh your workspaces.'
        : 'Please try again. If this continues, contact your AppNest administrator.';
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                network ? Icons.cloud_off_outlined : Icons.info_outline,
                size: 40,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 20),
              Semantics(
                liveRegion: true,
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

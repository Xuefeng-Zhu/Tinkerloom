import 'dart:async';

import 'package:tinkerloom_client/tinkerloom_client.dart';
import 'package:flutter/material.dart';

/// Keeps the Router unmounted until its authenticated transport is ready.
/// MaterialApp's route provider stays in place throughout loading and retry.
class StartupScreen extends StatefulWidget {
  const StartupScreen({
    super.key,
    required this.initialize,
    required this.child,
  });

  final Future<void> Function() initialize;
  final Widget child;

  @override
  State<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<StartupScreen> {
  bool _loading = false;
  bool _ready = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.initialize();
      if (mounted) setState(() => _ready = true);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return widget.child;
    final network =
        _error is TimeoutException || _error is BackendNetworkException;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_loading)
                  const CircularProgressIndicator()
                else
                  Icon(
                    network ? Icons.cloud_off_outlined : Icons.info_outline,
                    size: 40,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                const SizedBox(height: 24),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _loading
                        ? 'Opening Tinkerloom'
                        : network
                        ? 'Can’t connect to Tinkerloom'
                        : 'Couldn’t open Tinkerloom',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _loading
                      ? 'Checking your session…'
                      : network
                      ? 'Check your connection and try again. Your saved session has been kept.'
                      : 'Please try again. If this continues, contact your Tinkerloom administrator.',
                  textAlign: TextAlign.center,
                ),
                if (!_loading) ...[
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _initialize,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

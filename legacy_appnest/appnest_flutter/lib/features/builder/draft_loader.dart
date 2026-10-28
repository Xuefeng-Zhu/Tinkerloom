import 'package:appnest_client/appnest_client.dart';
import 'package:flutter/material.dart';

import '../../client.dart';
import 'builder_screen.dart';

/// Resolves a durable app identifier through the authenticated server before
/// resuming the current user's draft. No browser storage contains definitions.
class DraftLoader extends StatefulWidget {
  final int appId;
  final Future<void> Function() onClose;
  final Future<void> Function(int appId) onPublished;
  const DraftLoader({
    super.key,
    required this.appId,
    required this.onClose,
    required this.onPublished,
  });

  @override
  State<DraftLoader> createState() => DraftLoaderState();
}

class DraftLoaderState extends State<DraftLoader> {
  final _builderKey = GlobalKey<BuilderScreenState>();
  BuilderSnapshot? _draft;
  Object? _error;
  bool _loading = true;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(DraftLoader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.appId != widget.appId) _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _draft = null;
    });
    try {
      final manifest = await client.apps.manifest(widget.appId);
      if (!mounted || generation != _generation) return;
      if (manifest.archived || !{'owner', 'builder'}.contains(manifest.role)) {
        throw NestError(category: 'notFound', message: 'Draft unavailable.');
      }
      if (manifest.versionId != null) {
        // Another tab may have published this app since the draft link opened.
        await widget.onPublished(widget.appId);
        return;
      }
      final draft = await client.builder.begin(
        manifest.workspaceId,
        'notes',
        widget.appId,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _draft = draft;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<bool> canLeave() async =>
      await _builderKey.currentState?.canLeave() ?? true;

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    if (draft != null) {
      return BuilderScreen(
        key: _builderKey,
        initial: draft,
        startFromScratch: !draft.candidateReady && draft.baseVersionId == null,
        onClose: widget.onClose,
        onPublished: widget.onPublished,
      );
    }
    final unavailable =
        _error is NestError &&
        {'forbidden', 'notFound'}.contains((_error as NestError).category);
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: widget.onClose),
        title: const Text('Continue building'),
      ),
      body: Center(
        child: _loading
            ? const CircularProgressIndicator()
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      unavailable
                          ? 'This draft is unavailable.'
                          : 'Your draft could not be loaded. Try again.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    if (!unavailable)
                      FilledButton(
                        onPressed: _load,
                        child: const Text('Retry'),
                      ),
                    TextButton(
                      onPressed: widget.onClose,
                      child: const Text('Back to your apps'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

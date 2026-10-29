import 'package:appnest_renderer/appnest_renderer.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:flutter/material.dart';

import 'main.dart' show buildTinkerloomTheme;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TinkerloomPreviewApp());
}

/// Standalone original renderer previews. This entrypoint creates no transport.
class TinkerloomPreviewApp extends StatelessWidget {
  const TinkerloomPreviewApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Tinkerloom',
    debugShowCheckedModeBanner: false,
    theme: buildTinkerloomTheme(Brightness.light),
    home: const _Templates(),
  );
}

class _Templates extends StatelessWidget {
  const _Templates();

  @override
  Widget build(BuildContext context) {
    final templates = starterTemplates().values.toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Tinkerloom')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                'Try a template',
                style: Theme.of(context).textTheme.displaySmall,
              ),
              const SizedBox(height: 12),
              const Text(
                'Offline preview · sample data · changes are temporary',
              ),
              const SizedBox(height: 24),
              for (final spec in templates)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      leading: const Icon(Icons.apps_outlined),
                      title: Text(spec.name),
                      trailing: const Icon(Icons.arrow_forward),
                      onTap: () => Navigator.of(context).push<void>(
                        MaterialPageRoute(builder: (_) => _Preview(spec: spec)),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Preview extends StatefulWidget {
  const _Preview({required this.spec});
  final AppSpec spec;
  @override
  State<_Preview> createState() => _PreviewState();
}

class _PreviewState extends State<_Preview> {
  late final adapter = PreviewRuntimeAdapter(widget.spec);
  @override
  void dispose() {
    adapter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.spec.name)),
    body: MiniAppRuntime(adapter: adapter),
    bottomNavigationBar: const SafeArea(
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Text(
          'Offline preview · sample data',
          textAlign: TextAlign.center,
        ),
      ),
    ),
  );
}

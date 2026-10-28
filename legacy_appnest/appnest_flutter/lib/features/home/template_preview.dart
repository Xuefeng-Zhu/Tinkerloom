import 'package:appnest_client/appnest_client.dart';
import 'package:appnest_renderer/appnest_renderer.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:flutter/material.dart';

/// A local sample; opening or interacting with it never creates a server draft.
class TemplatePreviewScreen extends StatefulWidget {
  final TemplateInfo template;
  const TemplatePreviewScreen({super.key, required this.template});

  @override
  State<TemplatePreviewScreen> createState() => _TemplatePreviewScreenState();
}

class _TemplatePreviewScreenState extends State<TemplatePreviewScreen> {
  late final runtime = PreviewRuntimeAdapter(
    AppSpec.parse(widget.template.specJson),
  );

  @override
  void dispose() {
    runtime.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('${widget.template.name} preview')),
    body: MiniAppRuntime(adapter: runtime),
    bottomNavigationBar: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 20,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.spaceBetween,
          children: [
            const Text('Sample data only. Your new app will start empty.'),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.add),
              label: const Text('Create from this template'),
            ),
          ],
        ),
      ),
    ),
  );
}

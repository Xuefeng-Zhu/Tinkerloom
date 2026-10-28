import 'dart:async';

import 'package:appnest_renderer/appnest_renderer.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:flutter/material.dart';

const _styles = {
  'clean': ('Clean', 'Simple and focused'),
  'editorial': ('Editorial', 'Warm and considered'),
  'playful': ('Playful', 'Bright and inviting'),
};

Map<String, dynamic> appearanceForStyle(
  Map<String, dynamic> current,
  String style,
) => {
  'style': style,
  if (current['accentColor'] != null) 'accentColor': current['accentColor'],
};

/// Local presentation controls. The caller owns validation and revision-aware
/// saving; even an incomplete hex value remains an unsaved, recoverable intent.
class AppearanceEditor extends StatefulWidget {
  final AppSpec spec;
  final Map<String, dynamic>? initialValue;
  final PreviewRuntimeAdapter? preview;
  final MiniAppLocation? location;
  final bool enabled;
  final ValueChanged<Map<String, dynamic>> onChanged;
  const AppearanceEditor({
    super.key,
    required this.spec,
    required this.onChanged,
    this.initialValue,
    this.preview,
    this.location,
    this.enabled = true,
  });

  @override
  State<AppearanceEditor> createState() => _AppearanceEditorState();
}

class _AppearanceEditorState extends State<AppearanceEditor> {
  late Map<String, dynamic> appearance;
  late final TextEditingController accent;
  late bool hasAppearance;
  String get style => appearance['style'] as String;
  bool get validAccent =>
      accent.text.isEmpty || RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(accent.text);

  @override
  void initState() {
    super.initState();
    hasAppearance =
        widget.initialValue != null || widget.spec.appearance != null;
    appearance =
        widget.initialValue ??
        widget.spec.appearance?.toJson() ??
        {'style': 'clean'};
    accent = TextEditingController(text: appearance['accentColor'] as String?);
  }

  @override
  void dispose() {
    accent.dispose();
    super.dispose();
  }

  void change(Map<String, dynamic> value) {
    setState(() {
      appearance = value;
      hasAppearance = true;
    });
    widget.onChanged(Map<String, dynamic>.from(value));
  }

  void property(String key, String? value) => change(
    {
      ...appearance,
      key: value,
    }..removeWhere((_, value) => value == null),
  );

  Widget choices(
    String title,
    String propertyName,
    Map<String, String> values,
    String fallback,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 20),
      Text(title, style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 8),
      Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          for (final entry in values.entries)
            ChoiceChip(
              key: ValueKey('appearance-$propertyName-${entry.key}'),
              label: Text(entry.value),
              selected: (appearance[propertyName] ?? fallback) == entry.key,
              onSelected: !widget.enabled
                  ? null
                  : (_) => property(propertyName, entry.key),
            ),
        ],
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('Style', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 4),
      Text(
        hasAppearance
            ? 'Try a complete look for your app.'
            : 'Original appearance. Choose a style to update it.',
      ),
      const SizedBox(height: 12),
      LayoutBuilder(
        builder: (context, constraints) {
          final largeText = MediaQuery.textScalerOf(context).scale(14) >= 21;
          final columns = largeText || constraints.maxWidth < 270 ? 2 : 3;
          final width = (constraints.maxWidth - 8 * (columns - 1)) / columns;
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in _styles.entries)
                SizedBox(
                  width: width,
                  child: _StyleChoice(
                    name: entry.value.$1,
                    description: entry.value.$2,
                    selected: hasAppearance && style == entry.key,
                    onTap: !widget.enabled
                        ? null
                        : () {
                            change(appearanceForStyle(appearance, entry.key));
                          },
                    child: _StylePreview(
                      spec: widget.spec,
                      preview: widget.preview,
                      location: widget.location,
                      appearance: {
                        'style': entry.key,
                        if (validAccent && appearance['accentColor'] != null)
                          'accentColor': appearance['accentColor'],
                      },
                    ),
                  ),
                ),
            ],
          );
        },
      ),
      const SizedBox(height: 20),
      Text('Accent color', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 8),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final swatch in const {
            '#177D79': ('Teal', Color(0xff177d79)),
            '#A86012': ('Amber', Color(0xffa86012)),
            '#386AD2': ('Blue', Color(0xff386ad2)),
            '#AF4B71': ('Rose', Color(0xffaf4b71)),
            '#507963': ('Sage', Color(0xff507963)),
          }.entries)
            ChoiceChip(
              key: ValueKey('appearance-accent-${swatch.key}'),
              avatar: CircleAvatar(backgroundColor: swatch.value.$2, radius: 8),
              label: Text(swatch.value.$1),
              selected: appearance['accentColor'] == swatch.key,
              onSelected: !widget.enabled
                  ? null
                  : (_) {
                      accent.text = swatch.key;
                      property('accentColor', swatch.key);
                    },
            ),
        ],
      ),
      const SizedBox(height: 12),
      TextField(
        key: const ValueKey('appearance-accent-hex'),
        controller: accent,
        enabled: widget.enabled,
        decoration: InputDecoration(
          labelText: 'Custom color (optional)',
          hintText: '#177D79',
          helperText: 'Leave empty for the app’s default color.',
          errorText: validAccent ? null : 'Use a color like #177D79.',
          suffixIcon: accent.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Use default accent',
                  onPressed: !widget.enabled
                      ? null
                      : () {
                          accent.clear();
                          property('accentColor', null);
                        },
                  icon: const Icon(Icons.close, size: 18),
                ),
        ),
        textCapitalization: TextCapitalization.characters,
        autocorrect: false,
        onChanged: (value) =>
            property('accentColor', value.isEmpty ? null : value),
      ),
      choices('Headings', 'typography', const {
        'sans': 'Sans-serif',
        'serif': 'Serif',
      }, style == 'editorial' ? 'serif' : 'sans'),
      choices(
        'Spacing',
        'density',
        const {
          'compact': 'Compact',
          'comfortable': 'Comfortable',
          'spacious': 'Spacious',
        },
        switch (style) {
          'clean' => 'compact',
          'editorial' => 'spacious',
          _ => 'comfortable',
        },
      ),
      choices(
        'Corners',
        'corners',
        const {
          'square': 'Square',
          'soft': 'Soft',
          'rounded': 'Rounded',
        },
        switch (style) {
          'editorial' => 'square',
          'playful' => 'rounded',
          _ => 'soft',
        },
      ),
      const SizedBox(height: 12),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: const ValueKey('appearance-reset'),
          onPressed: !widget.enabled || !hasAppearance
              ? null
              : () {
                  accent.clear();
                  change({'style': style});
                },
          icon: const Icon(Icons.restart_alt, size: 18),
          label: const Text('Reset appearance'),
        ),
      ),
    ],
  );
}

class _StyleChoice extends StatelessWidget {
  final String name, description;
  final bool selected;
  final VoidCallback? onTap;
  final Widget child;
  const _StyleChoice({
    required this.name,
    required this.description,
    required this.selected,
    required this.onTap,
    required this.child,
  });
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    enabled: onTap != null,
    label: '$name style. $description',
    excludeSemantics: true,
    child: Tooltip(
      message: description,
      child: OutlinedButton(
        key: ValueKey('appearance-style-${name.toLowerCase()}'),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.all(5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          side: BorderSide(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : const Color(0xffdce1dd),
            width: selected ? 2 : 1,
          ),
          backgroundColor: selected ? const Color(0xfff0f5f1) : Colors.white,
        ),
        onPressed: onTap,
        child: Column(
          children: [
            ClipRRect(borderRadius: BorderRadius.circular(5), child: child),
            const SizedBox(height: 7),
            Text(name, textAlign: TextAlign.center),
            const SizedBox(height: 3),
          ],
        ),
      ),
    ),
  );
}

class _StylePreview extends StatefulWidget {
  final AppSpec spec;
  final Map<String, dynamic> appearance;
  final PreviewRuntimeAdapter? preview;
  final MiniAppLocation? location;
  const _StylePreview({
    required this.spec,
    required this.appearance,
    required this.preview,
    required this.location,
  });
  @override
  State<_StylePreview> createState() => _StylePreviewState();
}

class _StylePreviewState extends State<_StylePreview> {
  late PreviewRuntimeAdapter adapter;
  late String fingerprint;
  StreamSubscription<void>? sourceChanges;
  bool refreshScheduled = false;
  String get nextFingerprint =>
      '${widget.spec.hash}:${canonicalJson(widget.appearance)}';
  void refresh() {
    final next = widget.spec.patch({
      'type': 'SetAppearance',
      'appearance': widget.appearance,
    }, () => throw StateError('Appearance does not allocate IDs'));
    adapter =
        widget.preview?.forkPresentation(next) ?? PreviewRuntimeAdapter(next);
    fingerprint = nextFingerprint;
  }

  void watchSource() {
    sourceChanges?.cancel();
    sourceChanges = widget.preview?.watch().listen((_) {
      if (refreshScheduled) return;
      refreshScheduled = true;
      scheduleMicrotask(() {
        refreshScheduled = false;
        if (!mounted) return;
        setState(() {
          adapter.dispose();
          refresh();
        });
      });
    });
  }

  @override
  void initState() {
    super.initState();
    refresh();
    watchSource();
  }

  @override
  void didUpdateWidget(covariant _StylePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.preview, widget.preview)) watchSource();
    if (!identical(oldWidget.preview, widget.preview) ||
        fingerprint != nextFingerprint) {
      adapter.dispose();
      refresh();
    }
  }

  @override
  void dispose() {
    sourceChanges?.cancel();
    adapter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 390 / 470,
    child: ExcludeFocus(
      child: IgnorePointer(
        child: FittedBox(
          fit: BoxFit.contain,
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: 390,
            height: 470,
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(
                size: const Size(390, 470),
                textScaler: TextScaler.noScaling,
                padding: EdgeInsets.zero,
                viewPadding: EdgeInsets.zero,
                viewInsets: EdgeInsets.zero,
              ),
              child: MiniAppRuntime(
                key: ObjectKey(adapter),
                adapter: adapter,
                initialLocation: widget.location?.editing == true
                    ? null
                    : widget.location,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// One layout choice shared by the inspector and the complete page editor.
class PageLayoutPicker extends StatelessWidget {
  final String? value;
  final ValueChanged<String>? onChanged;
  const PageLayoutPicker({
    super.key,
    required this.value,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('Page layout', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final layout in const {
            'stacked': ('Stacked', Icons.view_agenda_outlined),
            'twoColumn': ('Two columns', Icons.view_week_outlined),
            'featuredFirst': ('Featured first', Icons.dashboard_outlined),
          }.entries)
            ChoiceChip(
              key: ValueKey('page-layout-${layout.key}'),
              avatar: Icon(layout.value.$2, size: 20),
              label: Text(layout.value.$1),
              selected: (value ?? 'stacked') == layout.key,
              onSelected: onChanged == null
                  ? null
                  : (_) => onChanged!(layout.key),
            ),
        ],
      ),
      const SizedBox(height: 8),
      const Text(
        'Columns stack on small screens. Tables, calendars, boards, forms and details always use the full width.',
      ),
    ],
  );
}

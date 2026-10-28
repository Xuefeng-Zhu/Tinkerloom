part of '../appnest_renderer.dart';

enum MiniAppEditKind { app, page, section, field }

/// Stable definition identity, never a sample-record identity.
@immutable
class MiniAppEditTarget {
  final MiniAppEditKind kind;
  final String id;
  final String? pageId, viewId, collectionId;
  const MiniAppEditTarget(
    this.kind,
    this.id, {
    this.pageId,
    this.viewId,
    this.collectionId,
  });
  @override
  bool operator ==(Object other) =>
      other is MiniAppEditTarget &&
      kind == other.kind &&
      id == other.id &&
      pageId == other.pageId &&
      viewId == other.viewId &&
      collectionId == other.collectionId;
  @override
  int get hashCode => Object.hash(kind, id, pageId, viewId, collectionId);
}

@immutable
class MiniAppEditConfiguration {
  final MiniAppEditTarget? selected;
  final ValueChanged<MiniAppEditTarget> onSelect;
  const MiniAppEditConfiguration({this.selected, required this.onSelect});
}

class _VisualEditScope extends InheritedWidget {
  final MiniAppEditConfiguration? configuration;
  const _VisualEditScope({required this.configuration, required super.child});
  static MiniAppEditConfiguration? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_VisualEditScope>()
      ?.configuration;
  @override
  bool updateShouldNotify(_VisualEditScope oldWidget) =>
      configuration != oldWidget.configuration;
}

class _EditTarget extends StatelessWidget {
  final MiniAppEditTarget target;
  final Widget child;
  const _EditTarget({super.key, required this.target, required this.child});
  @override
  Widget build(BuildContext context) {
    final edit = _VisualEditScope.of(context);
    if (edit == null) return child;
    final selected = edit.selected == target;
    final color = Theme.of(context).colorScheme.primary;
    return Semantics(
      label: 'Edit ${target.kind.name} ${target.id}',
      button: true,
      selected: selected,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () => edit.onSelect(target),
          hoverColor: color.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(6),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: selected ? color : color.withValues(alpha: .22),
                width: selected ? 2 : 1,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

Widget _editableField(
  BuildContext context,
  ViewSpec view,
  String fieldId,
  Widget child, {
  String? pageId,
}) => _EditTarget(
  target: MiniAppEditTarget(
    MiniAppEditKind.field,
    fieldId,
    collectionId: view.collectionId,
    viewId: view.id,
    pageId: pageId,
  ),
  child: child,
);

Widget _editForm(AppSpec spec, ViewSpec view, {String? pageId}) => Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    Text(view.label),
    const SizedBox(height: 12),
    for (final field
        in spec
            .collection(view.collectionId)
            .fields
            .where(
              (f) => view.fieldIds.isEmpty || view.fieldIds.contains(f.id),
            ))
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _EditTarget(
          target: MiniAppEditTarget(
            MiniAppEditKind.field,
            field.id,
            collectionId: view.collectionId,
            viewId: view.id,
            pageId: pageId,
          ),
          child: InputDecorator(
            decoration: InputDecoration(labelText: field.label),
            child: const Text('Sample value'),
          ),
        ),
      ),
  ],
);

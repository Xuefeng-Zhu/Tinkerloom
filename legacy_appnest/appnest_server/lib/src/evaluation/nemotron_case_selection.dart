import '../modules/builder/nemotron_scenarios.dart';

/// Selects exact benchmark cases in the requested order before any dispatch.
/// A sequence can use only a source creation included earlier in this run.
List<NemotronScenario> selectNemotronCases(
  List<NemotronScenario> available, {
  String? cases,
}) {
  if (cases == null) return List<NemotronScenario>.from(available);
  final selectedIds = cases.split(',').map((id) => id.trim()).toList();
  if (selectedIds.any((id) => id.isEmpty)) {
    throw const FormatException(
      '--cases must contain nonempty exact case IDs.',
    );
  }
  if (selectedIds.toSet().length != selectedIds.length) {
    throw const FormatException(
      '--cases must contain distinct exact case IDs.',
    );
  }
  final byId = {for (final scenario in available) scenario.id: scenario};
  final selected = <NemotronScenario>[];
  final earlier = <String>{};
  for (final id in selectedIds) {
    final scenario = byId[id];
    if (scenario == null) {
      throw FormatException('Unknown --cases ID: $id.');
    }
    final source = scenario.sequenceSourceId;
    if (source != null && !earlier.contains(source)) {
      throw FormatException(
        '--cases must include $source before sequence case $id.',
      );
    }
    selected.add(scenario);
    earlier.add(id);
  }
  return selected;
}

import 'dart:convert';

/// An opt-in reminder of the existing AppSpec grammar, not a template, repair
/// compiler, or substitute for validation. It never changes the request or a
/// model response. Keep it independent of benchmark IDs and fixture contents.
const nemotronCreationChecklist =
    'Final creation contract check (nemotron-creation-checklist-v1): '
    'If the request is unsupported, keep the unsupported-only response. '
    'Otherwise verify the complete AppSpec before returning compact JSON. '
    'Root icon is exactly book, board, people, spark or check; never calendar, '
    'today or clock. Theme is teal, amber, blue, rose or sage. '
    'View presentation, query and groupByFieldId are view properties, not '
    'options properties. Use only the options allowed for that view type. '
    'Every requested feature needs an actual reachable component: a requested '
    'checklist uses type checklist, and a capacity summary uses type capacity '
    'with the same collection and declared configure/claim/release actions. '
    'A field or form step alone does not configure its control: explicitly '
    'bind requested image upload, multiline writing and rating controls through '
    'form.options.controls to their declared fields. Use imageUpload for image, '
    'multiline for text and rating for a one-to-five integer rating, with no '
    'min/max/step. Ordinary unbounded numbers need no explicit control. '
    'Never use a text control on a numeric field. '
    'Preserve all requested filters, metrics, date buckets, optional timestamps '
    'and workflow transitions. Wire each primary add action through a view on '
    'that page to its dedicated form page. Recompute requires from every used '
    'component: configured bindings/options need views.configured.v1, form '
    'controls/steps need views.interactive.v1, and explicit page layouts need '
    'navigation.layouts.v1. Never invent capability names. '
    'On repair, correct every diagnostic and check the full original request '
    'again; preserve already correct IDs and features. Return only the result.';

/// Recognize the authored creation envelope without inferring from prose.
bool isNemotronCreationRequest(List messages) {
  if (messages.isEmpty ||
      messages.first is! Map ||
      (messages.first as Map)['role'] != 'system' ||
      (messages.first as Map)['content'] is! String) {
    return false;
  }
  final user = messages
      .whereType<Map>()
      .where(
        (message) => message['role'] == 'user',
      )
      .lastOrNull;
  if (user?['content'] is! String) return false;
  try {
    final payload = jsonDecode(user!['content'] as String);
    return payload is Map &&
        payload['request'] is String &&
        !payload.containsKey('currentDefinition');
  } on FormatException {
    return false;
  }
}

/// Only an authored creation message receives this trusted system reminder.
/// Edits preserve their semantic-patch contract and guidance stays untouched.
List<Map<String, dynamic>> emphasizeNemotronCreationContract(List messages) {
  final copied = (jsonDecode(jsonEncode(messages)) as List)
      .map((message) => Map<String, dynamic>.from(message as Map))
      .toList();
  if (copied.isEmpty || copied.first['role'] != 'system') return copied;
  final system = copied.first['content'];
  if (system is! String || system.contains(nemotronCreationChecklist)) {
    return copied;
  }
  if (!isNemotronCreationRequest(copied)) return copied;
  copied.first['content'] = '$system $nemotronCreationChecklist';
  return copied;
}

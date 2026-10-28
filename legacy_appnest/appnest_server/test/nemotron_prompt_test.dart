import 'dart:convert';

import 'package:appnest_server/src/modules/builder/nemotron_prompt.dart';
import 'package:appnest_server/src/modules/builder/provider.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:test/test.dart';

void main() {
  final baseline = starterTemplates()['reading']!;

  test(
    'creation reminder preserves original request, schema and repair data',
    () {
      final body = buildAiRequest(
        nvidiaNemotronModels[1],
        'A personal photo journal',
        baseline,
        editing: false,
        diagnostics: ['synthetic validation diagnostic'],
        rejectedOutput: '{"unsupported":"synthetic rejected response"}',
      );
      final messages = body['messages'] as List;
      final before = jsonEncode(messages);
      final result = emphasizeNemotronCreationContract(messages);
      expect(jsonEncode(messages), before);
      expect(result[1], messages[1]);
      expect(
        result.first['content'],
        '${(messages.first as Map)['content']} $nemotronCreationChecklist',
      );
      expect(emphasizeNemotronCreationContract(result), result);
      result[1]['content'] = 'changed copy';
      expect(jsonEncode(messages), before);
    },
  );

  test('edit and guidance contracts remain byte equivalent', () {
    final bodies = [
      buildAiRequest(
        nvidiaNemotronModels[1],
        'Rename the app',
        baseline,
        editing: true,
      ),
      buildGuidanceRequest(nvidiaNemotronModels[1], 'Organize my life'),
    ];
    for (final body in bodies) {
      final messages = body['messages'] as List;
      expect(
        jsonEncode(emphasizeNemotronCreationContract(messages)),
        jsonEncode(messages),
      );
    }
  });

  test('unrecognized message shapes receive no inferred instructions', () {
    for (final messages in <List>[
      [],
      [
        {'role': 'user', 'content': '{"request":"A tracker"}'},
      ],
      [
        {'role': 'system', 'content': 'contract'},
      ],
      [
        {'role': 'system', 'content': 'contract'},
        {'role': 'user', 'content': 'invalid JSON'},
      ],
      [
        {'role': 'system', 'content': 'contract'},
        {'role': 'user', 'content': '{"request":1}'},
      ],
    ]) {
      expect(
        jsonEncode(emphasizeNemotronCreationContract(messages)),
        jsonEncode(messages),
      );
    }
  });
}

import 'dart:convert';

import 'package:appnest_server/src/modules/builder/creation_compiler.dart';
import 'package:appnest_server/src/modules/builder/provider.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

Map<String, dynamic> reading() =>
    jsonDecode(creationReferenceJson) as Map<String, dynamic>;

void main() {
  test(
    'creation compiler closes only parser-derived capability declarations',
    () {
      final json = reading();
      json['views'][2]['options'] = {
        'controls': [
          {'fieldId': 'title', 'control': 'multiline'},
        ],
      };
      final source = jsonEncode(json);
      expect(
        () => AppSpec.parse(source),
        throwsA(
          isA<SpecException>().having(
            (error) => error.message,
            'strict missing declaration',
            'Missing required capabilities: views.interactive.v1',
          ),
        ),
      );
      final raw = '```json\n$source\n```';
      final result = compileGeneratedCreation(source, rawOutput: raw);
      expect(result.addedCapabilities, ['views.interactive.v1']);
      expect(result.rawOutputHash, sha256.convert(utf8.encode(raw)).toString());
      expect(
        result.inputDefinitionHash,
        sha256.convert(utf8.encode(source)).toString(),
      );
      expect(result.rawOutputHash, isNot(result.spec.hash));
      expect(result.toJson()['candidateHash'], result.spec.hash);
      final expected = {
        ...json,
        'requires': [...json['requires'] as List, 'views.interactive.v1'],
      };
      expect(result.spec.hash, AppSpec.parse(jsonEncode(expected)).hash);
      final compiled = result.spec.toJson()..remove('requires');
      final authored = AppSpec.parse(jsonEncode(expected)).toJson()
        ..remove('requires');
      expect(canonicalJson(compiled), canonicalJson(authored));
      expect(json['requires'], isNot(contains('views.interactive.v1')));
      expect(
        () => result.addedCapabilities.add('workflow.v1'),
        throwsUnsupportedError,
      );
    },
  );

  test(
    'all declared features supply their closure without inferring new meaning',
    () {
      final expected = dailyPlannerTemplate();
      final json = expected.toJson()..['requires'] = <String>[];
      final result = compileGeneratedCreation(jsonEncode(json));
      expect(
        result.addedCapabilities,
        containsAll([
          'collections.v1',
          'navigation.v1',
          'workflow.v1',
          'records.create.v1',
          'records.patch.v1',
          'workflow.transition.v1',
          'notifications.inApp.v1',
          'notifications.owner.v1',
          'automations.conditions.v1',
        ]),
      );
      final compiled = result.spec.toJson()..remove('requires');
      final authored = expected.toJson()..remove('requires');
      expect(canonicalJson(compiled), canonicalJson(authored));
      expect(AppSpec.parse(result.spec.canonical).hash, result.spec.hash);
    },
  );

  test(
    'valid legacy canonical definitions and capability order remain unchanged',
    () {
      for (final spec in starterTemplates().values) {
        final result = compileGeneratedCreation(spec.canonical);
        expect(result.addedCapabilities, isEmpty);
        expect(result.spec.hash, spec.hash);
        expect(result.spec.canonical, spec.canonical);
        expect(result.spec.requires, spec.requires);
      }
      final json = reading();
      json['requires'] = [
        ...json['requires'] as List,
        'views.list.v1',
      ];
      json['views'][2]['options'] = {
        'controls': [
          {'fieldId': 'title', 'control': 'multiline'},
        ],
      };
      final result = compileGeneratedCreation(jsonEncode(json));
      expect(result.spec.requires, [
        ...json['requires'] as List,
        'views.interactive.v1',
      ]);
    },
  );

  test(
    'unsupported explicit capabilities and malformed graphs remain rejected',
    () {
      for (final unsupported in [
        'views.magic.v1',
        'personalTracker.v1',
        'views.interactive.v1\nrecords.delete.v1',
      ]) {
        final json = reading();
        json['requires'].add(unsupported);
        expect(
          () => compileGeneratedCreation(jsonEncode(json)),
          throwsA(
            isA<SpecException>().having(
              (error) => error.message,
              'allowlist',
              startsWith('Unsupported required capabilities:'),
            ),
          ),
        );
      }
      final missingReference = reading()..['requires'] = <String>[];
      missingReference['views'][0]['actionIds'].add('inventedAction');
      expect(
        () => compileGeneratedCreation(jsonEncode(missingReference)),
        throwsA(isA<SpecException>()),
      );
      final noBehavior = reading()..['requires'] = <String>[];
      noBehavior['collections'][0]['behaviors'] = <dynamic>[];
      noBehavior['views'][2]['fieldIds'].add('status');
      expect(
        () => compileGeneratedCreation(jsonEncode(noBehavior)),
        throwsA(
          isA<SpecException>().having(
            (error) => error.message,
            'no inferred behavior',
            contains('requires behaviorId'),
          ),
        ),
      );
      expect(
        () => compileGeneratedCreation('[]'),
        throwsA(isA<SpecException>()),
      );
    },
  );

  test(
    'input, raw provider output and compiled definition remain size bounded',
    () {
      expect(
        () => compileGeneratedCreation(' ' * (Limits.definitionBytes + 1)),
        throwsA(isA<SpecException>()),
      );
      expect(
        () => compileGeneratedCreation(
          creationReferenceJson,
          rawOutput: ' ' * (Limits.definitionBytes + 1),
        ),
        throwsA(isA<SpecException>()),
      );
      final json = {
        'formatVersion': 1,
        'name': 'Size boundary',
        'theme': 'sage',
        'icon': 'book',
        'requires': <String>[],
        'policyPresetRequest': 'personalTracker.v1',
        'collections': <dynamic>[],
        'actions': <dynamic>[],
        'automationRequests': <dynamic>[],
        'views': [
          for (var i = 0; i < 16; i++)
            {
              'id': 'text$i',
              'type': 'richText',
              'label': 'Text',
              'options': {'markdown': 'x' * 8192},
            },
        ],
        'navigation': {
          'entryPageId': 'main',
          'pages': [
            {
              'id': 'main',
              'title': 'Main',
              'viewIds': ['text0'],
            },
          ],
          'tabs': [
            {'pageId': 'main', 'label': 'Main', 'icon': 'book'},
          ],
        },
      };
      final excess =
          utf8.encode(jsonEncode(json)).length - (Limits.definitionBytes - 10);
      expect(excess, greaterThan(0));
      (json['views'] as List).last['options']['markdown'] =
          'x' * (8192 - excess);
      final source = jsonEncode(json);
      expect(utf8.encode(source).length, Limits.definitionBytes - 10);
      expect(
        () => AppSpec.parse(source),
        throwsA(
          isA<SpecException>().having(
            (error) => error.message,
            'input valid except declarations',
            startsWith('Missing required capabilities:'),
          ),
        ),
      );
      expect(
        () => compileGeneratedCreation(source),
        throwsA(
          isA<SpecException>().having(
            (error) => error.message,
            'post-closure bound',
            'Definition is too large',
          ),
        ),
      );
    },
  );
}

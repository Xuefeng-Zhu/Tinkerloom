import 'dart:convert';

import 'package:appnest_server/src/modules/builder/creation_patch.dart';
import 'package:appnest_server/src/modules/builder/provider.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:test/test.dart';

Map<String, dynamic> _definition() =>
    jsonDecode(creationReferenceJson) as Map<String, dynamic>;

Map<String, dynamic> _request({
  String? rejected,
  bool editing = false,
}) => buildAiRequest(
  'nvidia/nemotron-3-super-120b-a12b',
  'A personal reading tracker',
  starterTemplates()['reading']!,
  editing: editing,
  diagnostics: rejected == null ? [] : ['Correct the rejected definition.'],
  rejectedOutput: rejected,
);

Map<String, dynamic> _patch(List<Map<String, dynamic>> changes) => {
  'changes': changes,
};

Map<String, dynamic> _set(List<Object> path, Object? value) => {
  'op': 'set',
  'path': path,
  'value': value,
};

void main() {
  test('only bounded creation repairs opt into the patch protocol', () {
    final original = _request(rejected: jsonEncode(_definition()));
    final before = jsonEncode(original);
    final result = buildCreationPatchRequest(original);
    expect(isCreationPatchRequest(original), isFalse);
    expect(isCreationPatchRequest(result), isTrue);
    expect(jsonEncode(original), before);
    final envelope = jsonDecode(result['messages'].last['content'] as String);
    expect(envelope['request'], 'A personal reading tracker');
    expect(envelope['diagnostics'], ['Correct the rejected definition.']);
    expect(
      envelope['repairContext']['rejectedOutput'],
      jsonEncode(_definition()),
    );
    expect(
      result['response_format']['json_schema']['name'],
      'appnest_creation_patch',
    );
    expect(jsonEncode(buildCreationPatchRequest(result)), jsonEncode(result));
    expect(creationPatchBase(result), _definition());
  });

  test(
    'initial requests, valid-definition edits and guidance stay unchanged',
    () {
      for (final request in [
        _request(),
        _request(rejected: jsonEncode(_definition()), editing: true),
        buildGuidanceRequest('nvidia/nemotron-3-super-120b-a12b', 'An app'),
      ]) {
        final before = jsonEncode(request);
        final after = buildCreationPatchRequest(request);
        expect(jsonEncode(after), before);
        expect(isCreationPatchRequest(after), isFalse);
        expect(creationPatchBase(request), isNull);
      }
    },
  );

  test('malformed, unsupported and unsafe rejected output falls back', () {
    final unsafe = _definition()..['constructor'] = {'prototype': true};
    for (final raw in [
      '',
      '{"formatVersion":1,',
      'A response: ${jsonEncode(_definition())}',
      '[]',
      '{"unsupported":"A phone alarm is unavailable"}',
      '{"formatVersion":1}',
      jsonEncode(unsafe),
      jsonEncode(_definition()..['views'] = 'wrong type'),
      'x' * (Limits.definitionBytes + 1),
    ]) {
      final request = _request(rejected: raw);
      expect(creationPatchBase(request), isNull, reason: raw.take(100));
      expect(
        jsonEncode(buildCreationPatchRequest(request)),
        jsonEncode(request),
      );
    }
  });

  test('one complete outer JSON fence is compatible with normal parsing', () {
    final raw = '```json\n${jsonEncode(_definition())}\n```';
    expect(creationPatchBase(_request(rejected: raw)), _definition());
  });

  test('targeted changes preserve all other bytes and detach both inputs', () {
    final rejected = _definition();
    rejected['views'][0]['label'] = 'Incorrect label';
    final before = jsonEncode(rejected);
    final patch = _patch([
      _set(['views', 0, 'label'], 'Books'),
      _set(['name'], 'My books'),
    ]);
    final patchBefore = jsonEncode(patch);
    final candidate = applyCreationPatch(rejected, patch);
    expect(candidate['name'], 'My books');
    expect(candidate['views'][0]['label'], 'Books');
    final expected = jsonDecode(before) as Map<String, dynamic>;
    expected['name'] = 'My books';
    expected['views'][0]['label'] = 'Books';
    expect(jsonEncode(candidate), jsonEncode(expected));
    expect(jsonEncode(rejected), before);
    expect(jsonEncode(patch), patchBefore);
    candidate['collections'][0]['label'] = 'Candidate mutation';
    expect(jsonEncode(rejected), before);
  });

  test('new options use the actual view type schema and remain strict', () {
    final rejected = _definition();
    final formIndex = (rejected['views'] as List).indexWhere(
      (view) => view['type'] == 'form',
    );
    final fieldId = rejected['collections'][0]['fields'][0]['id'];
    final options = {
      'controls': [
        {'fieldId': fieldId, 'control': 'multiline'},
      ],
    };
    final candidate = applyCreationPatch(
      rejected,
      _patch([
        _set(['views', formIndex, 'options'], options),
        _set(
          ['requires'],
          [
            ...rejected['requires'] as List,
            'views.configured.v1',
            'views.interactive.v1',
          ],
        ),
      ]),
    );
    expect(candidate['views'][formIndex]['options'], options);
    expect(() => AppSpec.parse(jsonEncode(candidate)), returnsNormally);
    options['controls'] = [];
    expect(candidate['views'][formIndex]['options']['controls'], isNotEmpty);
    expect(
      () => applyCreationPatch(
        rejected,
        _patch([
          _set(['views', formIndex, 'options'], {'draggable': true}),
        ]),
      ),
      throwsFormatException,
    );
    expect(
      () => applyCreationPatch(
        rejected,
        _patch([
          _set(
            ['views', formIndex, 'options'],
            {
              'controls': [
                {'fieldId': fieldId, 'control': 'invented'},
              ],
            },
          ),
        ]),
      ),
      throwsFormatException,
    );
  });

  test('append and remove affect only the requested array item/property', () {
    final rejected = _definition();
    final action = {
      'id': 'extraEdit',
      'label': 'Edit book',
      'collectionId': rejected['collections'][0]['id'],
      'capability': 'records.patch.v1',
    };
    rejected['views'][0]['presentation'] = 'cards';
    final candidate = applyCreationPatch(
      rejected,
      _patch([
        {
          'op': 'append',
          'path': ['actions'],
          'value': action,
        },
        {
          'op': 'remove',
          'path': ['views', 0, 'presentation'],
        },
      ]),
    );
    expect(candidate['actions'], [...rejected['actions'] as List, action]);
    expect(candidate['views'][0].containsKey('presentation'), isFalse);
    action['label'] = 'Mutated input';
    expect(candidate['actions'].last['label'], 'Edit book');
    final removed = applyCreationPatch(
      candidate,
      _patch([
        {
          'op': 'remove',
          'path': ['actions', candidate['actions'].length - 1],
        },
      ]),
    );
    expect(removed['actions'], rejected['actions']);
  });

  test(
    'changes can be structurally valid and still fail final AppSpec checks',
    () {
      final candidate = applyCreationPatch(
        _definition(),
        _patch([
          _set(['views', 0, 'formPageId'], 'missingPage'),
        ]),
      );
      expect(
        () => AppSpec.parse(jsonEncode(candidate)),
        throwsA(isA<SpecException>()),
      );
    },
  );

  test('unknown envelope, operation, path and property keys are rejected', () {
    final definition = _definition();
    for (final patch in <Map<String, dynamic>>[
      {},
      {'changes': []},
      {'changes': 'bad'},
      {
        'changes': [
          _set(['name'], 'Book'),
        ],
        'grant': true,
      },
      _patch([
        {
          'op': 'move',
          'path': ['name'],
          'value': 'Book',
        },
      ]),
      _patch([
        {
          'op': 'set',
          'path': ['name'],
        },
      ]),
      _patch([
        {
          'op': 'remove',
          'path': ['name'],
          'value': null,
        },
      ]),
      _patch([
        {'op': 'set', 'path': '/name', 'value': 'Book'},
      ]),
      _patch([_set([], 'Book')]),
      _patch([
        _set(['views', -1, 'label'], 'Book'),
      ]),
      _patch([
        _set(['views', 999, 'label'], 'Book'),
      ]),
      _patch([
        _set(['views', '0', 'label'], 'Book'),
      ]),
      _patch([
        _set(['tenantId'], 'anotherTenant'),
      ]),
      _patch([
        _set(['__proto__', 'polluted'], true),
      ]),
      _patch([
        _set(['views', 0, 'constructor'], true),
      ]),
      _patch([
        _set(['formatVersion'], 1),
      ]),
      _patch([
        _set(['views'], []),
      ]),
      _patch([
        {
          'op': 'remove',
          'path': ['collections'],
        },
      ]),
      _patch([
        {
          'op': 'append',
          'path': ['name'],
          'value': 'Book',
        },
      ]),
      _patch([
        {
          'op': 'remove',
          'path': ['views', 0, 'unrecognized'],
        },
      ]),
      _patch([
        _set(['views', 2, 'options', 'controls'], []),
      ]),
      _patch([
        _set(['views', 0, 'label'], 'Book')..['unexpected'] = 1,
      ]),
    ]) {
      expect(
        () => applyCreationPatch(definition, patch),
        throwsFormatException,
        reason: jsonEncode(patch),
      );
    }
  });

  test('typed values, enums, nested keys and array bounds are enforced', () {
    final rejected = _definition();
    for (final change in [
      _set(['name'], 10),
      _set(['theme'], 'pink'),
      _set(['name'], ''),
      _set(['requires'], ['records.delete.v1']),
      _set(['appearance'], {'style': 'clean', 'permission': 'all'}),
      _set(['collections', 0, 'fields', 0, 'required'], 'true'),
      _set(
        ['views', 0, 'query'],
        {
          'filters': [
            {
              'fieldId': 'title',
              'operator': 'eq',
              'value': 'Book',
              'sql': true,
            },
          ],
        },
      ),
      _set(
        ['actions', 0],
        {
          'id': 'bad',
          'label': 'Delete',
          'collectionId': 'books',
          'capability': 'records.delete.v1',
        },
      ),
      _set(['navigation', 'pages', 0, 'viewIds'], ['same', 'same']),
      _set(['requires'], List.filled(41, 'collections.v1')),
      _set(['collections', 0, 'fields', 0, 'id'], 'invalid-id'),
    ]) {
      expect(
        () => applyCreationPatch(rejected, _patch([change])),
        throwsFormatException,
        reason: jsonEncode(change),
      );
    }
  });

  test(
    'operation count, bytes, depth, unsafe keys and non-JSON are bounded',
    () {
      final rejected = _definition();
      var deeplyNested = <String, dynamic>{'leaf': true};
      for (var i = 0; i < Limits.depth + 1; i++) {
        deeplyNested = {'next': deeplyNested};
      }
      for (final patch in [
        _patch(List.generate(25, (_) => _set(['name'], 'Book'))),
        _patch([
          _set(['name'], 'x' * 32768),
        ]),
        _patch([
          _set(['name'], deeplyNested),
        ]),
        _patch([
          _set(['name'], {'constructor': true}),
        ]),
        _patch([
          _set(['name'], double.nan),
        ]),
        _patch([
          _set(['name'], DateTime.utc(2026)),
        ]),
      ]) {
        expect(
          () => applyCreationPatch(rejected, patch),
          throwsFormatException,
        );
      }
      final tooLarge = _definition()..['extra'] = 'x' * Limits.definitionBytes;
      expect(
        () => applyCreationPatch(
          tooLarge,
          _patch([
            _set(['name'], 'Book'),
          ]),
        ),
        throwsFormatException,
      );
    },
  );

  test('failed later operations do not partially mutate either input', () {
    final rejected = _definition();
    final before = jsonEncode(rejected);
    final patch = _patch([
      _set(['name'], 'Changed name'),
      _set(['views', 0, 'label'], false),
    ]);
    final patchBefore = jsonEncode(patch);
    expect(() => applyCreationPatch(rejected, patch), throwsFormatException);
    expect(jsonEncode(rejected), before);
    expect(jsonEncode(patch), patchBefore);
  });

  test('later changes to inserted objects never mutate the patch input', () {
    final rejected = _definition();
    final patch = _patch([
      _set(['appearance'], {'style': 'clean'}),
      _set(['appearance', 'style'], 'editorial'),
    ]);
    final before = jsonEncode(patch);
    final candidate = applyCreationPatch(rejected, patch);
    expect(candidate['appearance']['style'], 'editorial');
    expect(jsonEncode(patch), before);
  });
}

extension on String {
  String take(int count) => length <= count ? this : substring(0, count);
}

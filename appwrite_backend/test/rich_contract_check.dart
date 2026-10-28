import 'dart:convert';
import 'dart:io';

import '../lib/definition.dart';
import '../lib/service.dart';
import 'memory_store.dart';

void _check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void _reject(void Function() run, String code) {
  try {
    run();
    throw StateError('Expected $code');
  } on ServiceException catch (error) {
    _check(error.code == code, 'Expected $code, received ${error.code}');
  }
}

Map<String, dynamic> _copy(Map<String, dynamic> value) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);

Future<int> runRichChecks() async {
  var passed = 0;
  Future<void> test(String label, Future<void> Function() run) async {
    await run();
    passed++;
    print('PASS $label');
  }

  final fixture = Map<String, dynamic>.from(
    jsonDecode(
      await File.fromUri(Platform.script.resolve('fixtures/rich_contract.json'))
          .readAsString(),
    ) as Map,
  );
  final base = validateDefinition(fixture['baseDefinition']);
  final validDefinitions = (fixture['validDefinitions'] as List).cast<Map>();
  final invalidDefinitions =
      (fixture['invalidDefinitions'] as List).cast<Map>();
  final validValues = (fixture['validValues'] as List).cast<Map>();
  final invalidValues = (fixture['invalidValues'] as List).cast<Map>();

  await test(
    'shared rich definition fixtures preserve canonical old definitions',
    () async {
      for (final item in validDefinitions) {
        _check(
          canonicalJson(validateDefinition(item['input'])) ==
              canonicalJson(item['expected']),
          'Normalization differs for ${item['name']}',
        );
      }
      for (final item in invalidDefinitions) {
        _reject(() => validateDefinition(item['input']), 'invalid_definition');
      }
    },
  );
  await test(
    'shared rich value fixtures enforce numeric and civil-date contracts',
    () async {
      for (final item in validValues) {
        _check(
          canonicalJson(validateValues(base, item['input'])) ==
              canonicalJson(item['expected']),
          'Value normalization differs for ${item['name']}',
        );
      }
      for (final item in invalidValues) {
        _reject(() => validateValues(base, item['input']), 'invalid_values');
      }
    },
  );
  await test(
    'non-finite and overflowing actual numbers cannot enter values',
    () async {
      for (final number in [
        double.nan,
        double.infinity,
        double.negativeInfinity,
        -9223372036854775808,
        1e15 + 1,
        -1e15 - 1,
      ]) {
        _reject(
          () => validateValues(base, {
            'title': 'Test',
            'amount': number,
            'when': '',
          }),
          'invalid_values',
        );
      }
      for (final number in [0, 0.0, -0.0, 1e15, -1e15, 0.000001, -1.25]) {
        _check(
          validateValues(base, {
                'title': 'Test',
                'amount': number,
                'when': '',
              })['amount'] ==
              number,
          'Valid number changed',
        );
      }
    },
  );
  await test(
    'required numeric and date fields distinguish zero from missing',
    () async {
      final required = _copy(base);
      for (final field in (required['fields'] as List).skip(1)) {
        (field as Map)['required'] = true;
      }
      final definition = validateDefinition(required);
      _check(
        validateValues(definition, {
              'title': 'Test',
              'amount': 0,
              'when': '0001-01-01',
            })['amount'] ==
            0,
        'Required zero rejected',
      );
      for (final value in [
        {'title': 'Test', 'amount': '', 'when': '0001-01-01'},
        {'title': 'Test', 'amount': 0, 'when': ''},
        {'title': 'Test', 'when': '0001-01-01'},
        {'title': 'Test', 'amount': 0},
      ]) {
        _reject(() => validateValues(definition, value), 'invalid_values');
      }
    },
  );
  await test(
    'Gregorian dates reject century rollover without timezone conversion',
    () async {
      for (final year in [
        1,
        4,
        100,
        400,
        1582,
        1600,
        1700,
        1900,
        2000,
        2024,
        2100,
        2400,
        9999,
      ]) {
        final leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
        final prefix = year.toString().padLeft(4, '0');
        _check(isCivilDate('$prefix-02-28'), 'Valid February day rejected');
        _check(
          isCivilDate('$prefix-02-29') == leap,
          'Wrong leap rule for $year',
        );
        _check(
          !isCivilDate('$prefix-02-30') && !isCivilDate('$prefix-04-31'),
          'Rollover accepted',
        );
      }
    },
  );
  await test(
      'presentation views stay compatible while rich field type changes remain destructive',
      () async {
    final prior = validateDefinition(base);
    for (final view in [
      {'kind': 'list'},
      {'kind': 'table'},
      {'kind': 'agenda', 'dateFieldId': 'when'},
    ]) {
      final next = validateDefinition({...base, 'view': view});
      requireCompatible(prior, next);
      requireCompatible(next, prior);
    }
    final changed = _copy(base);
    (changed['fields'] as List)[1]['kind'] = 'date';
    _reject(
      () => requireCompatible(prior, validateDefinition(changed)),
      'incompatible_definition',
    );
    final removed = _copy(base);
    (removed['fields'] as List).removeLast();
    _reject(
      () => requireCompatible(prior, validateDefinition(removed)),
      'incompatible_definition',
    );
  });
  await test(
    'rich values still respect the existing encoded JSON byte limit',
    () async {
      final definition = validateDefinition({
        'title': 'Notes',
        'description': '',
        'primaryFieldId': 'title',
        'fields': [
          {'id': 'title', 'label': 'Title', 'kind': 'text', 'required': true},
          for (var i = 1; i <= 3; i++)
            {'id': 'detail$i', 'label': 'Detail $i', 'kind': 'longText'},
          {'id': 'amount', 'label': 'Amount', 'kind': 'number'},
          {'id': 'when', 'label': 'Date', 'kind': 'date'},
        ],
      });
      final valid = {
        'title': 'T',
        'detail1': '🧵' * 2000,
        'detail2': '🧵' * 2000,
        'detail3': '',
        'amount': 0,
        'when': '2024-02-29',
      };
      validateValues(definition, valid);
      _reject(
        () => validateValues(definition, {...valid, 'detail3': '🧵' * 2000}),
        'invalid_values',
      );
    },
  );
  await test(
    'rich additions publish without changing legacy record or receipt meaning',
    () async {
      final store = MemoryStore();
      final api = PlatformService(store);
      final legacy = Map<String, dynamic>.from(
        validDefinitions.firstWhere(
          (item) => item['name'] == 'legacy-canonical-preserved',
        )['expected'] as Map,
      );
      await api.execute('owner', {
        'op': 'createWorkspace',
        'id': 'space',
        'name': 'Space',
      });
      await api.execute('owner', {
        'op': 'createApp',
        'id': 'app',
        'workspaceId': 'space',
        'name': 'Notes',
      });
      final originalCommand = {
        'op': 'saveDraft',
        'appId': 'app',
        'operationId': 'old-draft',
        'expectedRevision': 0,
        'definition': legacy,
      };
      final original = await api.execute('owner', originalCommand);
      await api.execute('owner', {
        'op': 'publishApp',
        'appId': 'app',
        'operationId': 'old-publish',
        'expectedRevision': 1,
      });
      await api.execute('owner', {
        'op': 'saveRecord',
        'appId': 'app',
        'id': 'legacy-record',
        'operationId': 'old-record',
        'expectedRevision': 0,
        'definitionRevision': 1,
        'values': {'title': 'Retained', 'body': 'Existing body'},
      });
      final next = _copy(legacy);
      (next['fields'] as List).addAll([
        {'id': 'amount', 'label': 'Amount', 'kind': 'number'},
        {'id': 'when', 'label': 'Date', 'kind': 'date'},
      ]);
      next['view'] = {'kind': 'agenda', 'dateFieldId': 'when'};
      await api.execute('owner', {
        'op': 'saveDraft',
        'appId': 'app',
        'operationId': 'rich-draft',
        'expectedRevision': 1,
        'definition': next,
      });
      await api.execute('owner', {
        'op': 'publishApp',
        'appId': 'app',
        'operationId': 'rich-publish',
        'expectedRevision': 2,
      });
      final page = await api.execute('owner', {
        'op': 'listRecords',
        'appId': 'app',
        'definitionRevision': 2,
      });
      final values = Map<String, dynamic>.from(
        ((page['records'] as List).single as Map)['values'] as Map,
      );
      _check(
        values['title'] == 'Retained' &&
            values['body'] == 'Existing body' &&
            values['amount'] == '' &&
            values['when'] == '',
        'Legacy values changed',
      );
      _check(
        canonicalJson(await api.execute('owner', originalCommand)) ==
            canonicalJson(original),
        'Old receipt changed after rich publication',
      );
      _check(
        !((original['app'] as Map)['definition'] as Map).containsKey('view'),
        'An absent legacy view was added to the old receipt',
      );
      final command = {
        'op': 'saveRecord',
        'appId': 'app',
        'id': 'rich-record',
        'operationId': 'rich-record-save',
        'expectedRevision': 0,
        'definitionRevision': 2,
        'values': {'title': 'Rich', 'amount': 0, 'when': '2024-02-29'},
      };
      final first = await api.execute('owner', command);
      _check(
        ((first['record'] as Map)['values'] as Map)['amount'] == 0,
        'Live numeric zero changed',
      );
      _check(
        canonicalJson(await api.execute('owner', command)) ==
            canonicalJson(first),
        'Rich record retry changed',
      );
    },
  );
  print(
    'Rich contract fixture cases: ${validDefinitions.length + invalidDefinitions.length} definitions; ${validValues.length + invalidValues.length} value cases.',
  );
  return passed;
}

Future<void> main() async {
  final passed = await runRichChecks();
  print('$passed rich backend checks passed.');
}

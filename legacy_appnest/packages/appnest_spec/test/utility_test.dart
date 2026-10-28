import 'dart:convert';
import 'dart:io';

import 'package:appnest_spec/appnest_spec.dart';
import 'package:test/test.dart';

void main() {
  final invalid = throwsA(isA<SpecException>());
  test(
    'collection-free focus definitions preserve absent defaults and hashes',
    () {
      final focus = focusTemplate();
      expect(focus.collections, isEmpty);
      expect(focus.actions, isEmpty);
      expect(focus.requires, isNot(contains('collections.v1')));
      expect(focus.views.every((v) => v.contentOnly), isTrue);
      expect(focus.view('localClock').clockOptions.style, 'digital');
      expect(focus.view('localClock').clockOptions.hourFormat, 'system');
      expect(focus.view('localClock').clockOptions.showSeconds, isFalse);
      expect(focus.view('localClock').clockOptions.showDate, isTrue);
      expect(focus.view('focusTimer').timerOptions.durationMinutes, 25);
      expect(focus.view('localClock').toJson().containsKey('options'), isFalse);
      expect(AppSpec.parse(focus.canonical).hash, focus.hash);
      for (final entry in utilityStarterTemplates().entries) {
        final fixture = AppSpec.parse(
          File('fixtures/${entry.key}.json').readAsStringSync(),
        );
        expect(fixture.hash, entry.value.hash);
        expect(fixture.policyPresetRequest, 'personalTracker.v1');
      }
    },
  );
  test('utility options reject wrong types, unbounded durations and record bindings', () {
    for (final options in [
      {'durationMinutes': 0},
      {'durationMinutes': 181},
      {'durationMinutes': 1.5},
      {'durationMinutes': null},
      {'durationMinutes': '25'},
      {'alarm': true},
    ]) {
      expect(() => TimerOptions.fromJson(options), invalid);
    }
    for (final options in [
      {'style': 'binary'},
      {'style': null},
      {'hourFormat': '13'},
      {'showDate': 'yes'},
      {'showSeconds': null},
      {'timezone': 'UTC'},
    ]) {
      expect(() => ClockOptions.fromJson(options), invalid);
    }
    for (final change in <void Function(Map<String, dynamic>)>[
      (j) => j['views'][0]['collectionId'] = 'records',
      (j) => j['views'][0]['actionIds'] = ['fakeAction'],
      (j) => j['views'][0]['query'] = {'limit': 2},
      (j) => j.remove('navigation'),
      (j) => (j['requires'] as List).remove('views.clock.v1'),
      (j) => j['views'] = [],
      (j) => j['views'][0] = {
        'id': 'list',
        'type': 'list',
        'collectionId': 'missing',
      },
    ]) {
      final json =
          jsonDecode(focusTemplate().canonical) as Map<String, dynamic>;
      change(json);
      expect(() => AppSpec.parse(jsonEncode(json)), invalid);
    }
  });
  test(
    'utility visual patches declare capabilities and retain stable identities',
    () {
      final spec = focusTemplate();
      final view = spec.view('focusTimer').toJson()..remove('id');
      view['options'] = {'durationMinutes': 180};
      final next = spec.patch({
        'type': 'UpdateView',
        'viewId': 'focusTimer',
        'view': view,
      }, () => throw StateError('No identity allocation'));
      expect(next.view('focusTimer').timerOptions.durationMinutes, 180);
      expect(next.requires, contains('views.configured.v1'));
      expect(spec.compatibilityErrors(next), isEmpty);
    },
  );
  test(
    'UpdateReminder preserves identity and validates supported one-time rules',
    () {
      final spec = remindersTemplate(), before = spec.automationRequests.single;
      final rule = before.toJson()..remove('id');
      rule['trigger']['offsetSeconds'] = 300;
      final next = spec.patch({
        'type': 'UpdateReminder',
        'ruleId': before.id,
        'rule': rule,
      }, () => throw StateError('No identity allocation'));
      expect(next.automationRequests.single.id, before.id);
      expect(next.automationRequests.single.offsetSeconds, 300);
      expect(spec.automationRequests.single.offsetSeconds, 0);
      expect(next.diff(spec), contains('Change requested reminders'));
      expect(spec.compatibilityErrors(next), isEmpty);
      for (final badRule in [
        {...rule, 'id': before.id},
        {
          ...rule,
          'effect': {'type': 'notifyPhone', 'channel': 'push'},
        },
        {
          ...rule,
          'trigger': {...rule['trigger'] as Map, 'offsetSeconds': -1},
        },
        {
          ...rule,
          'trigger': {...rule['trigger'] as Map, 'fieldId': 'title'},
        },
        {
          ...rule,
          'trigger': {...rule['trigger'] as Map, 'type': 'recurring'},
        },
        {
          ...rule,
          'condition': {'fieldId': 'status', 'value': 'Missing'},
        },
      ]) {
        expect(
          () => spec.patch({
            'type': 'UpdateReminder',
            'ruleId': before.id,
            'rule': badRule,
          }, () => 'unexpected'),
          invalid,
        );
      }
      expect(
        () => spec.patch({
          'type': 'UpdateReminder',
          'ruleId': 'missing',
          'rule': rule,
        }, () => 'unexpected'),
        invalid,
      );
    },
  );
  test('reminder recipient errors explain the required behavior and owner alternative', () {
    final spec = remindersTemplate(), before = spec.automationRequests.single;
    final rule = before.toJson()..remove('id');
    for (final binding in {
      'notifyActiveClaimants': 'capacity.v1',
      'notifyAssignee': 'assignment.v1',
    }.entries) {
      expect(
        () => spec.patch({
          'type': 'UpdateReminder',
          'ruleId': before.id,
          'rule': {
            ...rule,
            'effect': <String, dynamic>{
              ...rule['effect'] as Map<String, dynamic>,
              'type': binding.key,
            },
          },
        }, () => 'unexpected'),
        throwsA(
          isA<SpecException>().having(
            (error) => error.toString(),
            'actionable diagnostic',
            allOf(
              contains(binding.key),
              contains(binding.value),
              contains('notifyOwner'),
              contains('personalTracker.v1'),
            ),
          ),
        ),
      );
    }
  });

  test('new notes and calendar templates expose usable detail and editor destinations', () {
    for (final spec in [notesTemplate(), calendarTemplate()]) {
      final overview = spec.view('allEntries');
      expect(overview.detailPageId, 'detailPage');
      expect(overview.formPageId, 'formPage');
      expect(spec.view('entryDetails').formPageId, 'formPage');
      expect(
        spec.view('entryEditor').actionIds,
        containsAll(['addRecord', 'editRecord']),
      );
      expect(spec.view('entryEditor').options['controls'], isNotEmpty);
    }
    final calendar = calendarTemplate(), today = DateTime(2026, 9, 23);
    expect(
      DateTime.parse(
        syntheticRecords(
              calendar.collections.single,
              now: today,
            ).first['startsAt']
            as String,
      ).toLocal().day,
      today.day,
    );
  });
}

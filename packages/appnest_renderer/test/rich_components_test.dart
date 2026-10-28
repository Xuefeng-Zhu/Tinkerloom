import 'dart:async';
import 'dart:convert';

import 'package:appnest_renderer/appnest_renderer.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime(2026, 9, 22, 12);
Future<void> mount(
  WidgetTester tester,
  RuntimeAdapter adapter,
  MiniAppController controller, {
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: const TextScaler.linear(1.5),
        ),
        child: Scaffold(
          body: MiniAppRuntime(
            adapter: adapter,
            controller: controller,
            clock: () => now,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> close(
  WidgetTester tester,
  PreviewRuntimeAdapter adapter,
  MiniAppController controller,
) async {
  await tester.pumpWidget(const SizedBox());
  adapter.dispose();
  controller.dispose();
}

AppSpec boundedEnergyForm(String kind, {int step = 1}) {
  final json = habitTrackerTemplate().toJson();
  final fields = json['collections'][0]['fields'] as List;
  fields.firstWhere((field) => field['id'] == 'loggedAt')['required'] = false;
  final editor = (json['views'] as List).firstWhere(
    (view) => view['id'] == 'editor',
  );
  editor['fieldIds'] = ['title', 'energy', 'notes'];
  editor['options'] = {
    'controls': [
      {
        'fieldId': 'energy',
        'control': kind,
        if (kind != 'rating') ...{'min': 1, 'max': 5, 'step': step},
      },
      {'fieldId': 'notes', 'control': 'multiline'},
    ],
  };
  return AppSpec.parse(jsonEncode(json));
}

Finder numericButton(String tooltip) => find.byWidgetPredicate(
  (widget) => widget is IconButton && widget.tooltip == tooltip,
);

class RecordingPreview extends PreviewRuntimeAdapter {
  RecordingPreview(super.spec, {super.pickImage}) : super(now: now);
  final queries = <Map<String, dynamic>>[];
  int writes = 0;
  bool failWrites = false;
  Completer<void>? pendingWrite;
  @override
  Future<RuntimePage> query(String collectionId, Map<String, dynamic> query) {
    queries.add(query);
    return super.query(collectionId, query);
  }

  @override
  Future<void> execute(
    ActionSpec action,
    RuntimeItem? record,
    Map<String, dynamic> input,
    String key,
  ) async {
    writes++;
    if (pendingWrite != null) await pendingWrite!.future;
    if (failWrites)
      throw const SpecException('This record changed. Refresh before saving.');
    return super.execute(action, record, input, key);
  }
}

class RevocableImages extends RecordingPreview {
  RevocableImages(super.spec);
  final events = StreamController<void>.broadcast();
  bool revoked = false;
  @override
  Stream<void> watch() => events.stream;
  @override
  Future<Uint8List> readImage(String assetId, {bool thumbnail = true}) async {
    if (revoked) throw const SpecException('Access revoked');
    return base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final size in [const Size(390, 844), const Size(1440, 1000)]) {
    for (final template in {
      ...richStarterTemplates(),
      ...utilityStarterTemplates(),
    }.entries) {
      testWidgets('${template.key} every page renders at $size and 150% text', (
        tester,
      ) async {
        final adapter = PreviewRuntimeAdapter(template.value, now: now),
            controller = MiniAppController();
        await mount(tester, adapter, controller, size: size);
        for (final page in adapter.spec.navigation!.pages) {
          final details = page.viewIds.any(
            (id) => adapter.spec.view(id).type == 'details',
          );
          await controller.navigate(
            MiniAppLocation(page.id, recordId: details ? 1 : null),
          );
          await tester.pumpAndSettle();
          expect(
            find.text('This page is unavailable'),
            findsNothing,
            reason: page.id,
          );
          expect(tester.takeException(), isNull, reason: page.id);
          expect(
            find.textContaining('preview_image_'),
            findsNothing,
            reason: page.id,
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
          expect(tester.takeException(), isNull, reason: page.id);
          expect(
            find.textContaining('preview_image_'),
            findsNothing,
            reason: page.id,
          );
        }
        await close(tester, adapter, controller);
      });
    }
  }
  test(
    'preview aggregates include all records and exclude absent averages',
    () async {
      final adapter = PreviewRuntimeAdapter(habitTrackerTemplate(), now: now);
      for (var n = 0; n < 130; n++) {
        await adapter.execute(adapter.spec.action('addRecord'), null, {
          'data': {
            'title': 'Entry $n',
            'loggedAt': now.toUtc().toIso8601String(),
            'minutes': n < 129 ? -2 : null,
            'category': n.isEven ? 'Move' : null,
          },
        }, 'new-$n');
      }
      final query = {
        'filters': [
          {'fieldId': 'title', 'operator': 'contains', 'value': 'Entry '},
        ],
        'limit': 1,
      };
      final result = await adapter.aggregate('checkins', query, {
        'metric': 'average',
        'fieldId': 'minutes',
        'groupFieldId': 'category',
      });
      expect(result['total'], 130);
      expect(result['value'], -2);
      expect(
        (result['groups'] as List)
            .map((g) => g['count'])
            .reduce((a, b) => a + b),
        130,
      );
      expect(
        (result['groups'] as List)
            .where((g) => g['key'] == 'Learn')
            .single['value'],
        isNull,
      );
      expect(
        (result['groups'] as List).where((g) => g['key'] == '').single['count'],
        65,
      );
      final times = await adapter.aggregate('checkins', query, {
        'metric': 'sum',
        'fieldId': 'minutes',
        'dateFieldId': 'loggedAt',
        'buckets': runtimeDateBuckets(now, periods: 3),
      });
      expect((times['groups'] as List).last['value'], -258);
      adapter.dispose();
    },
  );
  test('date buckets use independent local calendar boundaries', () {
    for (final day in [DateTime(2026, 3, 8), DateTime(2026, 11, 1)]) {
      final buckets = runtimeDateBuckets(day, periods: 3);
      for (var n = 0; n < buckets.length; n++) {
        final start = DateTime.parse(buckets[n]['start'] as String).toLocal(),
            end = DateTime.parse(buckets[n]['end'] as String).toLocal();
        expect(start.hour, 0);
        expect(end.hour, 0);
        expect(end, DateTime(start.year, start.month, start.day + 1));
        if (n > 0) expect(buckets[n - 1]['end'], buckets[n]['start']);
      }
    }
    expect(
      () => runtimeDateBuckets(now, periods: 367),
      throwsA(isA<SpecException>()),
    );
    expect(
      runtimeDateBuckets(now, unit: 'week', periods: 1).single['key'],
      '2026-09-21',
    );
    expect(
      runtimeDateBuckets(now, unit: 'month', periods: 1).single['key'],
      '2026-09-01',
    );
  });
  testWidgets('table sorting changes complete adapter query', (tester) async {
    final adapter = RecordingPreview(projectHubTemplate()),
        controller = MiniAppController();
    await mount(tester, adapter, controller);
    await controller.navigate(const MiniAppLocation('tablePage'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Task').first);
    await tester.pumpAndSettle();
    expect(
      adapter.queries.any(
        (q) => (q['sort'] as List? ?? []).any(
          (s) => s['fieldId'] == 'title' && s['descending'] == false,
        ),
      ),
      true,
    );
    expect(tester.takeException(), isNull);
    await close(tester, adapter, controller);
  });
  testWidgets('multi-step form writes once only on final save', (tester) async {
    final adapter = RecordingPreview(photoJournalTemplate()),
        controller = MiniAppController();
    await mount(tester, adapter, controller);
    await controller.navigate(const MiniAppLocation('formPage', editing: true));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Next step'));
    await tester.tap(find.text('Next step'));
    await tester.pumpAndSettle();
    expect(find.text('Please check the highlighted field.'), findsOneWidget);
    expect(adapter.writes, 0);
    await tester.ensureVisible(find.widgetWithText(TextField, 'Title *'));
    await tester.enterText(
      find.widgetWithText(TextField, 'Title *'),
      'A quiet afternoon',
    );
    await tester.ensureVisible(find.text('Next step'));
    await tester.tap(find.text('Next step'));
    await tester.pumpAndSettle();
    expect(find.text('The story'), findsOneWidget);
    expect(adapter.writes, 0);
    await tester.ensureVisible(find.widgetWithText(TextField, 'Caption'));
    await tester.enterText(
      find.widgetWithText(TextField, 'Caption'),
      'Kept locally until saved',
    );
    await tester.ensureVisible(find.text('Previous'));
    await tester.tap(find.text('Previous'));
    await tester.pumpAndSettle();
    expect(find.text('A quiet afternoon'), findsOneWidget);
    expect(adapter.writes, 0);
    await tester.ensureVisible(find.text('Next step'));
    await tester.tap(find.text('Next step'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(adapter.writes, 1);
    final record = (await adapter.query('memories', {
      'filters': [
        {'fieldId': 'title', 'operator': 'eq', 'value': 'A quiet afternoon'},
      ],
    })).items.single;
    expect(record.data['caption'], 'Kept locally until saved');
    expect(tester.takeException(), isNull);
    await close(tester, adapter, controller);
  });
  testWidgets('failed checklist write preserves state', (tester) async {
    final adapter = RecordingPreview(habitTrackerTemplate())..failWrites = true,
        controller = MiniAppController();
    await mount(tester, adapter, controller);
    await controller.navigate(const MiniAppLocation('checkinsPage'));
    await tester.pumpAndSettle();
    final before = await adapter.get(1);
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(adapter.writes, 1);
    expect((await adapter.get(1)).revision, before.revision);
    expect(
      find.text('This record changed. Refresh before saving.'),
      findsOneWidget,
    );
    expect(find.textContaining('SpecException'), findsNothing);
    await close(tester, adapter, controller);
  });
  testWidgets('board Move menu waits for successful acknowledgement', (
    tester,
  ) async {
    final adapter = RecordingPreview(projectHubTemplate()),
        controller = MiniAppController();
    await mount(tester, adapter, controller);
    final before = await adapter.get(1),
        target = before.data['status'] == 'Open' ? 'Done' : 'Open';
    await tester.ensureVisible(find.byTooltip('Move record').first);
    await tester.tap(find.byTooltip('Move record').first);
    await tester.pumpAndSettle();
    adapter.pendingWrite = Completer<void>();
    await tester.tap(find.text('Move to $target'));
    await tester.pump();
    expect((await adapter.get(1)).data['status'], before.data['status']);
    adapter.pendingWrite!.complete();
    await tester.pumpAndSettle();
    expect((await adapter.get(1)).data['status'], target);
    expect(tester.takeException(), isNull);
    await close(tester, adapter, controller);
  });
  test('preview image bytes and records survive presentation edits', () async {
    final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==',
    );
    final adapter = PreviewRuntimeAdapter(
      photoJournalTemplate(),
      pickImage: () async => bytes,
    );
    final image = await adapter.uploadImage(
      (await adapter.pickImage())!,
      collectionId: 'memories',
      fieldId: 'photo',
    );
    final before = await adapter.get(1), view = adapter.spec.view('intro');
    adapter.applyPresentationPatch({
      'type': 'UpdateView',
      'viewId': view.id,
      'view': (view.toJson()..remove('id'))
        ..['options'] = {'markdown': '# A new heading'},
    });
    expect((await adapter.get(1)).data, before.data);
    expect(await adapter.readImage(image), bytes);
    adapter.dispose();
  });
  testWidgets('numeric ranges preserve existing out-of-range values', (
    tester,
  ) async {
    final adapter = RecordingPreview(habitTrackerTemplate()),
        controller = MiniAppController();
    await adapter.execute(
      adapter.spec.action('editRecord'),
      await adapter.get(1),
      {
        'data': {'minutes': 999.125},
      },
      'outside',
    );
    await mount(tester, adapter, controller);
    await controller.navigate(
      const MiniAppLocation('formPage', recordId: 1, editing: true),
    );
    await tester.pumpAndSettle();
    expect(find.text('999.125'), findsOneWidget);
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect((await adapter.get(1)).data['minutes'], 999.125);
    await close(tester, adapter, controller);
  });
  for (final kind in ['slider', 'stepper', 'rating']) {
    testWidgets('$kind rejects new out-of-range values before any write', (
      tester,
    ) async {
      final adapter = RecordingPreview(boundedEnergyForm(kind));
      final controller = MiniAppController();
      await mount(tester, adapter, controller);
      await controller.navigate(
        const MiniAppLocation('formPage', editing: true),
      );
      await tester.pumpAndSettle();
      final title = find.widgetWithText(TextField, 'Activity *');
      final energy = find.widgetWithText(TextField, 'Energy');
      await tester.ensureVisible(title);
      await tester.enterText(title, 'Bounded new $kind');
      for (final invalid in ['6', '0']) {
        await tester.ensureVisible(energy);
        await tester.enterText(energy, invalid);
        await tester.ensureVisible(find.text('Save'));
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(adapter.writes, 0);
        expect(find.text('Energy must be between 1 and 5.'), findsOneWidget);
      }
      await tester.ensureVisible(energy);
      await tester.enterText(energy, '3');
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(adapter.writes, 1);
      final saved = (await adapter.query('checkins', {
        'filters': [
          {'fieldId': 'title', 'operator': 'eq', 'value': 'Bounded new $kind'},
        ],
      })).items.single;
      expect(saved.data['energy'], 3);
      expect(tester.takeException(), isNull);
      await close(tester, adapter, controller);
    });

    testWidgets(
      '$kind rejects changed out-of-range values but allows optional clearing',
      (tester) async {
        final adapter = RecordingPreview(boundedEnergyForm(kind));
        final controller = MiniAppController();
        await adapter.execute(
          adapter.spec.action('editRecord'),
          await adapter.get(1),
          {
            'data': {'energy': 3},
          },
          'prepare-valid-energy',
        );
        adapter.writes = 0;
        await mount(tester, adapter, controller);
        await controller.navigate(
          const MiniAppLocation('formPage', recordId: 1, editing: true),
        );
        await tester.pumpAndSettle();
        final energy = find.widgetWithText(TextField, 'Energy');
        await tester.ensureVisible(energy);
        await tester.enterText(energy, '6');
        await tester.ensureVisible(find.text('Save'));
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(adapter.writes, 0);
        expect((await adapter.get(1)).data['energy'], 3);
        expect(find.text('Energy must be between 1 and 5.'), findsOneWidget);
        await tester.ensureVisible(find.text('Clear value'));
        await tester.tap(find.text('Clear value'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Save'));
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(adapter.writes, 1);
        expect((await adapter.get(1)).data.containsKey('energy'), isFalse);
        expect(tester.takeException(), isNull);
        await close(tester, adapter, controller);
      },
    );

    testWidgets(
      '$kind preserves untouched legacy values on unrelated edits and permits correction',
      (tester) async {
        final adapter = RecordingPreview(boundedEnergyForm(kind));
        final controller = MiniAppController();
        await adapter.execute(
          adapter.spec.action('editRecord'),
          await adapter.get(1),
          {
            'data': {'energy': 9},
          },
          'prepare-legacy-energy',
        );
        adapter.writes = 0;
        await mount(tester, adapter, controller);
        await controller.navigate(
          const MiniAppLocation('formPage', recordId: 1, editing: true),
        );
        await tester.pumpAndSettle();
        final notes = find.widgetWithText(TextField, 'Notes');
        await tester.ensureVisible(notes);
        await tester.enterText(notes, 'An unrelated note');
        await tester.ensureVisible(find.text('Save'));
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(adapter.writes, 1);
        expect((await adapter.get(1)).data['energy'], 9);
        expect((await adapter.get(1)).data['notes'], 'An unrelated note');
        // Let the acknowledgement snackbar leave before reopening the editor.
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        await controller.navigate(
          const MiniAppLocation('formPage', recordId: 1, editing: true),
        );
        await tester.pumpAndSettle();
        if (kind == 'stepper') {
          expect(
            tester
                .widget<IconButton>(numericButton('Increase Energy'))
                .onPressed,
            isNull,
          );
          await tester.ensureVisible(find.byTooltip('Decrease Energy'));
          await tester.tap(find.byTooltip('Decrease Energy'));
        } else if (kind == 'rating') {
          await tester.ensureVisible(find.byTooltip('Energy: 5'));
          await tester.tap(find.byTooltip('Energy: 5'));
        } else {
          tester.widget<Slider>(find.byType(Slider)).onChanged!(5);
        }
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Save'));
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(adapter.writes, 2);
        expect((await adapter.get(1)).data['energy'], 5);
        expect((await adapter.get(1)).data['notes'], 'An unrelated note');
        expect(tester.takeException(), isNull);
        await close(tester, adapter, controller);
      },
    );
  }

  testWidgets(
    'stepper disables boundary buttons and never overshoots a partial final step',
    (tester) async {
      final adapter = RecordingPreview(boundedEnergyForm('stepper', step: 3));
      final controller = MiniAppController();
      await mount(tester, adapter, controller);
      await controller.navigate(
        const MiniAppLocation('formPage', editing: true),
      );
      await tester.pumpAndSettle();
      final energy = find.widgetWithText(TextField, 'Energy');
      final increase = numericButton('Increase Energy');
      final decrease = numericButton('Decrease Energy');
      String displayed() => tester.widget<TextField>(energy).controller!.text;
      expect(displayed(), '');
      expect(tester.widget<IconButton>(decrease).onPressed, isNull);
      for (final expected in ['1', '4', '5']) {
        await tester.ensureVisible(increase);
        await tester.tap(increase);
        await tester.pumpAndSettle();
        expect(displayed(), expected);
      }
      expect(tester.widget<IconButton>(increase).onPressed, isNull);
      for (final expected in ['2', '1']) {
        await tester.ensureVisible(decrease);
        await tester.tap(decrease);
        await tester.pumpAndSettle();
        expect(displayed(), expected);
      }
      expect(tester.widget<IconButton>(decrease).onPressed, isNull);
      expect(adapter.writes, 0);
      await close(tester, adapter, controller);
    },
  );

  testWidgets('optional bounded numeric create can remain unset', (
    tester,
  ) async {
    final adapter = RecordingPreview(boundedEnergyForm('rating'));
    final controller = MiniAppController();
    await mount(tester, adapter, controller);
    await controller.navigate(const MiniAppLocation('formPage', editing: true));
    await tester.pumpAndSettle();
    final title = find.widgetWithText(TextField, 'Activity *');
    await tester.ensureVisible(title);
    await tester.enterText(title, 'An unrated entry');
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(adapter.writes, 1);
    final saved = (await adapter.query('checkins', {
      'filters': [
        {'fieldId': 'title', 'operator': 'eq', 'value': 'An unrated entry'},
      ],
    })).items.single;
    expect(saved.data.containsKey('energy'), isFalse);
    await close(tester, adapter, controller);
  });
  testWidgets('bounded numeric validation also guards multi-step progression', (
    tester,
  ) async {
    final json = jsonDecode(
      jsonEncode(boundedEnergyForm('stepper').toJson()),
    ) as Map<String, dynamic>;
    final editor = (json['views'] as List).firstWhere(
      (view) => view['id'] == 'editor',
    );
    editor['options']['steps'] = [
      {
        'id': 'energyStep',
        'title': 'Choose energy',
        'fieldIds': ['title', 'energy'],
      },
      {
        'id': 'notesStep',
        'title': 'Add a note',
        'fieldIds': ['notes'],
      },
    ];
    final adapter = RecordingPreview(AppSpec.parse(jsonEncode(json)));
    final controller = MiniAppController();
    await mount(tester, adapter, controller);
    await controller.navigate(const MiniAppLocation('formPage', editing: true));
    await tester.pumpAndSettle();
    final title = find.widgetWithText(TextField, 'Activity *');
    final energy = find.widgetWithText(TextField, 'Energy');
    await tester.ensureVisible(title);
    await tester.enterText(title, 'A staged bounded entry');
    await tester.ensureVisible(energy);
    await tester.enterText(energy, '6');
    await tester.ensureVisible(find.text('Next step'));
    await tester.tap(find.text('Next step'));
    await tester.pumpAndSettle();
    expect(find.text('Step 1 of 2'), findsOneWidget);
    expect(find.text('Energy must be between 1 and 5.'), findsOneWidget);
    expect(adapter.writes, 0);
    await tester.ensureVisible(energy);
    await tester.enterText(energy, '5');
    await tester.ensureVisible(find.text('Next step'));
    await tester.tap(find.text('Next step'));
    await tester.pumpAndSettle();
    expect(find.text('Step 2 of 2'), findsOneWidget);
    expect(adapter.writes, 0);
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(adapter.writes, 1);
    final saved = (await adapter.query('checkins', {
      'filters': [
        {
          'fieldId': 'title',
          'operator': 'eq',
          'value': 'A staged bounded entry',
        },
      ],
    })).items.single;
    expect(saved.data['energy'], 5);
    await close(tester, adapter, controller);
  });
  for (final step in [0.001, 3.0]) {
    testWidgets('slider snaps to $step without rounding stored values', (
      tester,
    ) async {
      final json = habitTrackerTemplate().toJson();
      final editor = (json['views'] as List).firstWhere(
        (v) => v['id'] == 'editor',
      );
      final control = (editor['options']['controls'] as List).firstWhere(
        (v) => v['fieldId'] == 'minutes',
      );
      control['min'] = 0;
      control['max'] = step == 3 ? 10 : 1;
      control['step'] = step;
      final adapter = RecordingPreview(AppSpec.parse(jsonEncode(json))),
          controller = MiniAppController();
      await mount(tester, adapter, controller);
      await controller.navigate(
        const MiniAppLocation('formPage', recordId: 1, editing: true),
      );
      await tester.pumpAndSettle();
      tester.widget<Slider>(find.byType(Slider)).onChanged!(
        step == 3 ? 3.3333 : 0.001,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect((await adapter.get(1)).data['minutes'], step);
      await close(tester, adapter, controller);
    });
  }
  testWidgets(
    'required date timeline does not offer impossible Undated query',
    (tester) async {
      final json = habitTrackerTemplate().toJson();
      final view = (json['views'] as List).firstWhere(
        (v) => v['id'] == 'checkins',
      );
      view['type'] = 'timeline';
      view['options'] = {'dateFieldId': 'loggedAt'};
      (json['requires'] as List).add('views.timeline.v1');
      final adapter = RecordingPreview(AppSpec.parse(jsonEncode(json))),
          controller = MiniAppController();
      await mount(tester, adapter, controller);
      await controller.navigate(const MiniAppLocation('checkinsPage'));
      await tester.pumpAndSettle();
      expect(find.text('Undated'), findsNothing);
      expect(find.text('This page is unavailable'), findsNothing);
      await close(tester, adapter, controller);
    },
  );
  testWidgets(
    'calendar counts every matching record and paginates selected day',
    (tester) async {
      final adapter = RecordingPreview(projectHubTemplate()),
          controller = MiniAppController();
      for (var n = 0; n < 101; n++) {
        await adapter.execute(adapter.spec.action('addRecord'), null, {
          'data': {
            'title': 'Scheduled $n',
            'status': 'Open',
            'dueAt': now.toUtc().toIso8601String(),
          },
        }, 'scheduled-$n');
      }
      final total = (await adapter.query('projects', {
        'filters': [
          {
            'fieldId': 'dueAt',
            'operator': 'gte',
            'value': DateTime(
              now.year,
              now.month,
              now.day,
            ).toUtc().toIso8601String(),
          },
          {
            'fieldId': 'dueAt',
            'operator': 'lt',
            'value': DateTime(
              now.year,
              now.month,
              now.day + 1,
            ).toUtc().toIso8601String(),
          },
        ],
      })).total;
      await mount(tester, adapter, controller);
      await controller.navigate(const MiniAppLocation('calendarPage'));
      await tester.pumpAndSettle();
      expect(find.text('$total'), findsOneWidget);
      expect(find.text('$total records'), findsOneWidget);
      await tester.ensureVisible(find.text('Load more').first);
      await tester.tap(find.text('Load more').first);
      await tester.pumpAndSettle();
      expect(adapter.queries.any((q) => q['cursor'] != null), true);
      expect(tester.takeException(), isNull);
      await close(tester, adapter, controller);
    },
  );
  testWidgets(
    'image stream revocation removes image without uncaught futures',
    (tester) async {
      final adapter = RevocableImages(photoJournalTemplate()),
          controller = MiniAppController();
      await mount(tester, adapter, controller);
      expect(find.byType(Image), findsWidgets);
      adapter.revoked = true;
      adapter.events.addError(const SpecException('Access revoked'));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsNothing);
      expect(tester.takeException(), isNull);
      await close(tester, adapter, controller);
      await adapter.events.close();
    },
  );
  testWidgets('tiny nonzero metrics retain meaningful displayed precision', (
    tester,
  ) async {
    final adapter = RecordingPreview(habitTrackerTemplate()),
        controller = MiniAppController();
    for (final item in (await adapter.query('checkins', {})).items) {
      await adapter.execute(adapter.spec.action('editRecord'), item, {
        'data': {'minutes': item.id == 1 ? 0.001 : null},
      }, 'small-${item.id}');
    }
    await mount(tester, adapter, controller);
    expect(find.text('0.001'), findsNWidgets(2));
    expect(find.text('0.001 of 150'), findsOneWidget);
    await close(tester, adapter, controller);
  });
  testWidgets('legacy app creates replaces and clears images without raw IDs', (
    tester,
  ) async {
    final spec = starterTemplates()['reading']!.patch({
      'type': 'AddField',
      'collectionId': 'books',
      'field': {'label': 'Cover', 'type': 'image', 'required': false},
    }, () => 'cover');
    final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==',
    );
    final adapter = RecordingPreview(spec, pickImage: () async => bytes),
        controller = MiniAppController();
    await mount(tester, adapter, controller);
    await tester.tap(find.text('Add book'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Cover'), findsNothing);
    await tester.enterText(
      find.widgetWithText(TextField, 'Title *'),
      'Book with cover',
    );
    await tester.ensureVisible(find.text('Choose image'));
    await tester.tap(find.text('Choose image'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(find.text('Replace image'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final record = (await adapter.query('books', {
      'filters': [
        {'fieldId': 'title', 'operator': 'eq', 'value': 'Book with cover'},
      ],
    })).items.single;
    expect(record.data['cover'], startsWith('preview_upload_'));
    expect(find.textContaining('preview_upload_'), findsNothing);
    expect(find.textContaining('preview_image_'), findsNothing);
    Future<void> edit() async {
      final card = find
          .ancestor(
            of: find.text('Book with cover'),
            matching: find.byType(Card),
          )
          .first;
      final button = find.descendant(
        of: card,
        matching: find.text('Edit book'),
      );
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
    }

    await edit();
    await tester.ensureVisible(find.text('Replace image'));
    await tester.tap(find.text('Replace image'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(
      (await adapter.get(record.id)).data['cover'],
      isNot(record.data['cover']),
    );
    await edit();
    await tester.ensureVisible(find.text('Remove image'));
    await tester.tap(find.text('Remove image'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect((await adapter.get(record.id)).data['cover'], isNull);
    expect(tester.takeException(), isNull);
    await close(tester, adapter, controller);
  });
  testWidgets('form steps isolate EditableText state by field identity', (
    tester,
  ) async {
    final adapter = RecordingPreview(photoJournalTemplate()),
        controller = MiniAppController();
    await mount(tester, adapter, controller, size: const Size(1440, 1000));
    await controller.navigate(const MiniAppLocation('formPage', editing: true));
    await tester.pumpAndSettle();
    Finder editor(String id) => find.descendant(
      of: find.byKey(ValueKey('editor-field-$id')),
      matching: find.byType(EditableText),
    );
    final titleState = tester.state<EditableTextState>(editor('title'));
    await tester.enterText(
      find.widgetWithText(TextField, 'Title *'),
      'Title stays with title',
    );
    await tester.ensureVisible(find.text('Next step'));
    await tester.tap(find.text('Next step'));
    await tester.pumpAndSettle();
    final captionState = tester.state<EditableTextState>(editor('caption'));
    expect(identical(titleState, captionState), false);
    expect(titleState.mounted, false);
    expect(
      tester.widget<EditableText>(editor('caption')).controller.text,
      isEmpty,
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Caption'),
      'Caption stays with caption',
    );
    await tester.ensureVisible(find.text('Previous'));
    await tester.tap(find.text('Previous'));
    await tester.pumpAndSettle();
    expect(captionState.mounted, false);
    expect(
      tester.widget<EditableText>(editor('title')).controller.text,
      'Title stays with title',
    );
    await tester.ensureVisible(find.text('Next step'));
    await tester.tap(find.text('Next step'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<EditableText>(editor('caption')).controller.text,
      'Caption stays with caption',
    );
    expect(adapter.writes, 0);
    await close(tester, adapter, controller);
  });
}

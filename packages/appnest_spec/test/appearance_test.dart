import 'dart:convert';
import 'dart:io';

import 'package:appnest_spec/appnest_spec.dart';
import 'package:test/test.dart';

String noIds() => throw StateError('Presentation changes allocate no IDs');

AppSpec setAppearance(AppSpec spec, Object? appearance) =>
    spec.patch({'type': 'SetAppearance', 'appearance': appearance}, noIds);

AppSpec setLayout(AppSpec spec, String pageId, String? layout) {
  final page = spec.page(pageId).toJson()..remove('id');
  if (layout == null) {
    page.remove('layout');
  } else {
    page['layout'] = layout;
  }
  return spec.patch({
    'type': 'UpdatePage',
    'pageId': pageId,
    'page': page,
  }, noIds);
}

AppSpec setPlacement(AppSpec spec, String? placement) {
  final view = spec.view('welcome').toJson()..remove('id');
  final options = Map<String, dynamic>.from(view['options'] as Map);
  if (placement == null) {
    options.remove('imagePlacement');
  } else {
    options['imagePlacement'] = placement;
  }
  view['options'] = options;
  return spec.patch({
    'type': 'UpdateView',
    'viewId': 'welcome',
    'view': view,
  }, noIds);
}

void main() {
  final invalid = throwsA(isA<SpecException>());

  test('existing fixtures preserve their exact canonical definitions', () {
    for (final entry in starterTemplates().entries) {
      final fixture = File('fixtures/${entry.key}.json').readAsStringSync();
      final original = jsonDecode(fixture) as Map<String, dynamic>;
      final parsed = AppSpec.parse(fixture);
      expect(parsed.canonical, canonicalJson(original));
      expect(parsed.hash, entry.value.hash);
      expect(parsed.appearance, isNull);
      expect(parsed.toJson().containsKey('appearance'), isFalse);
      for (final page in parsed.navigation?.pages ?? <PageSpec>[]) {
        expect(page.layout, isNull);
        expect(page.toJson().containsKey('layout'), isFalse);
      }
    }
  });

  test('appearance normalizes only explicit choices and round-trips', () {
    final original = dailyPlannerTemplate();
    final spec = setAppearance(original, {
      'style': 'editorial',
      'accentColor': '#ab12Cd',
      'typography': 'serif',
      'density': 'spacious',
      'corners': 'square',
    });
    expect(spec.appearance!.toJson(), {
      'style': 'editorial',
      'accentColor': '#AB12CD',
      'typography': 'serif',
      'density': 'spacious',
      'corners': 'square',
    });
    expect(AppSpec.parse(spec.canonical).canonical, spec.canonical);
    expect(spec.requires, contains('appearance.v1'));
    expect(setAppearance(original, {'style': 'clean'}).appearance!.toJson(), {
      'style': 'clean',
    });
    for (final style in appearanceStyles) {
      expect(
        setAppearance(original, {'style': style}).appearance!.style,
        style,
      );
    }
    final uppercase = setAppearance(original, {
      ...spec.appearance!.toJson(),
      'accentColor': '#AB12CD',
    });
    expect(uppercase.hash, spec.hash);
  });

  test('appearance rejects invalid or unknown presentation values', () {
    final original = dailyPlannerTemplate();
    for (final appearance in <Object?>[
      {},
      {'style': 'arbitrary'},
      {'style': null},
      {'style': 'clean', 'fontUrl': 'https://example.test/font'},
      {'style': 'clean', 'typography': 'comic'},
      {'style': 'clean', 'density': 12},
      {'style': 'clean', 'corners': null},
      for (final color in [
        null,
        123,
        'red',
        '#ABC',
        '#12345678',
        ' #123456',
        '#12345G',
      ])
        {'style': 'clean', 'accentColor': color},
    ]) {
      expect(() => setAppearance(original, appearance), invalid);
    }
    expect(() => original.patch({'type': 'SetAppearance'}, noIds), invalid);
    expect(
      () => original.patch({
        'type': 'SetAppearance',
        'appearance': {'style': 'clean'},
        'script': 'anything',
      }, noIds),
      invalid,
    );
    final json = original.toJson()..['appearance'] = null;
    expect(() => AppSpec.parse(jsonEncode(json)), invalid);
  });

  test(
    'replacement and reset preserve business definitions and legacy theme',
    () {
      final original = dailyPlannerTemplate();
      final styled = setAppearance(original, {
        'style': 'editorial',
        'accentColor': '#00ABCD',
        'density': 'compact',
      });
      final replaced = setAppearance(styled, {'style': 'playful'});
      expect(replaced.appearance!.toJson(), {'style': 'playful'});
      expect(replaced.compatibilityErrors(original), isEmpty);
      expect(original.compatibilityErrors(replaced), isEmpty);
      for (final key in [
        'collections',
        'actions',
        'automationRequests',
        'views',
        'navigation',
        'policyPresetRequest',
      ]) {
        expect(replaced.toJson()[key], original.toJson()[key]);
      }
      final changedTheme = replaced.patch({
        'type': 'SetTheme',
        'theme': 'rose',
        'icon': 'book',
      }, noIds);
      expect(changedTheme.appearance!.toJson(), replaced.appearance!.toJson());
      expect(changedTheme.theme, 'rose');
      expect(changedTheme.icon, 'book');
      expect(setAppearance(replaced, null).canonical, original.canonical);
      expect(styled.diff(original), contains('Change app style to editorial'));
      expect(
        original.diff(styled),
        contains('Restore original app appearance'),
      );
    },
  );

  test(
    'layout declarations are validated and capabilities follow all pages',
    () {
      final original = dailyPlannerTemplate();
      final ids = original.navigation!.pages.map((p) => p.id).toList();
      for (final layout in pageLayouts) {
        final changed = setLayout(original, ids.first, layout);
        expect(changed.page(ids.first).layout, layout);
        expect(changed.requires, contains('navigation.layouts.v1'));
        expect(changed.requires, contains('navigation.v1'));
        expect(original.compatibilityErrors(changed), isEmpty);
        expect(AppSpec.parse(changed.canonical).canonical, changed.canonical);
      }
      var changed = setLayout(original, ids[0], 'twoColumn');
      changed = setLayout(changed, ids[1], 'featuredFirst');
      changed = setLayout(changed, ids[0], null);
      expect(changed.requires, contains('navigation.layouts.v1'));
      changed = setLayout(changed, ids[1], null);
      expect(changed.canonical, original.canonical);
      expect(() => setLayout(original, ids[0], 'absolute'), invalid);
      final page = original.page(ids[0]).toJson()..['layout'] = null;
      expect(() => PageSpec.fromJson(page), invalid);
      expect(
        setLayout(original, ids[0], 'twoColumn').diff(original),
        contains('Change ${original.page(ids[0]).title} layout to Two columns'),
      );
    },
  );

  test('adding a page with layout declares the capability atomically', () {
    var id = 0;
    final spec = starterTemplates()['reading']!.patch({
      'type': 'AddPage',
      'page': {
        'title': 'Library',
        'viewIds': ['library'],
        'layout': 'featuredFirst',
      },
    }, () => 'allocated${++id}');
    expect(spec.navigation!.pages.single.layout, 'featuredFirst');
    expect(
      spec.requires,
      containsAll(['navigation.v1', 'navigation.layouts.v1']),
    );
  });

  test('banner placement and appearance share a correctly retained capability', () {
    final original = projectHubTemplate();
    var spec = setPlacement(original, 'beside');
    expect(spec.requires, contains('appearance.v1'));
    expect(spec.view('welcome').options['imagePlacement'], 'beside');
    spec = setAppearance(spec, {'style': 'clean'});
    spec = setAppearance(spec, null);
    expect(spec.requires, contains('appearance.v1'));
    spec = setPlacement(spec, 'above');
    expect(spec.view('welcome').options['imagePlacement'], 'above');
    spec = setPlacement(spec, null);
    expect(spec.canonical, original.canonical);
    final styled = setAppearance(original, {'style': 'playful'});
    spec = setPlacement(setPlacement(styled, 'beside'), null);
    expect(spec.requires, contains('appearance.v1'));
    expect(spec.canonical, styled.canonical);
    expect(() => setPlacement(original, 'overlay'), invalid);
    expect(
      setPlacement(original, 'beside').diff(original),
      contains(
        'Change ${original.view('welcome').label} image placement to Beside text',
      ),
    );
  });

  test(
    'explicit appearance and layout features require declared capabilities',
    () {
      final original = dailyPlannerTemplate();
      for (final spec in [
        setAppearance(original, {'style': 'clean'}),
        setPlacement(projectHubTemplate(), 'beside'),
        setLayout(original, original.navigation!.pages.first.id, 'twoColumn'),
      ]) {
        final json = spec.toJson();
        (json['requires'] as List).removeWhere(
          (c) => c == 'appearance.v1' || c == 'navigation.layouts.v1',
        );
        expect(() => AppSpec.parse(jsonEncode(json)), invalid);
      }
    },
  );

  test('exported schema describes the same bounded presentation choices', () {
    final properties = appSpecSchema()['properties'] as Map;
    final appearance = properties['appearance'] as Map;
    expect(appearance['required'], ['style']);
    expect(appearance['additionalProperties'], isFalse);
    expect(
      appearance['properties']['style']['enum'],
      appearanceStyles.toList(),
    );
    expect(
      properties['navigation']['properties']['pages']['items']['properties']['layout']['enum'],
      pageLayouts.toList(),
    );
    expect(
      properties['requires']['items']['enum'],
      containsAll(['appearance.v1', 'navigation.layouts.v1']),
    );
  });
}

library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:appnest_spec/appnest_spec.dart';
part 'src/appearance.dart';
part 'src/runtime.dart';
part 'src/components.dart';
part 'src/navigation.dart';
part 'src/rich_runtime.dart';
part 'src/editor.dart';
part 'src/visual_edit.dart';
part 'src/rich_components.dart';
part 'src/utility_timer.dart';
part 'src/utility_components.dart';
part 'src/device_components.dart';

class RuntimeItem {
  final int id, revision;
  final String collectionId;
  final Map<String, dynamic> data;
  final int? capacity, allocated;
  final bool claimed;
  final List<String> allowedActions;
  RuntimeItem(
    this.id,
    this.collectionId,
    this.data, {
    this.revision = 1,
    this.capacity,
    this.allocated,
    this.claimed = false,
    this.allowedActions = const [],
  });
}

class RuntimePage {
  final List<RuntimeItem> items;
  final int total;
  final String? cursor;
  RuntimePage(this.items, this.total, this.cursor);
}

abstract class RuntimeAdapter {
  late final DeviceCapabilitiesAdapter _deviceCapabilities =
      DeviceCapabilitiesAdapter();
  DeviceCapabilitiesAdapter get deviceCapabilities => _deviceCapabilities;
  late final UtilityTimerController _timerController = UtilityTimerController();
  UtilityTimerController get timerController => _timerController;
  AppSpec get spec;
  bool get preview;
  bool get readOnly;
  bool get archived => false;
  String get role;
  String get readOnlyMessage => archived
      ? 'Archived · This app is read-only'
      : role == 'viewer'
      ? 'Read-only · Viewer access'
      : 'Read-only · Only the owner and builders can make changes';

  /// Return a message suitable for the person using the app, without transport
  /// diagnostics. Live adapters can recognize their typed service errors here.
  String errorMessage(
    Object error, {
    String fallback = 'Could not complete the request. Try again.',
  }) => error is SpecException ? error.message : fallback;

  /// A transport failure can hide a committed command's response. Typed
  /// business rejections are definite failures; adapters recognize their own
  /// service errors here so forms can distinguish correction from recovery.
  bool commandMayHaveSucceeded(Object error) => error is! SpecException;
  Future<RuntimePage> query(String collectionId, Map<String, dynamic> query);
  Future<void> execute(
    ActionSpec action,
    RuntimeItem? record,
    Map<String, dynamic> input,
    String key,
  );
  Future<List<String>> members();
  Stream<void> watch();
  bool permits(ActionSpec action);
  List<String> get approvedRuleIds => const [];
  Future<RuntimeItem> get(int recordId) =>
      Future.error(UnsupportedError('Record lookup is unavailable.'));
  Future<RuntimeSummary> summary(
    String collectionId,
    Map<String, dynamic> query,
    String groupFieldId,
  ) => Future.error(UnsupportedError('Grouped summaries are unavailable.'));
  Future<List<RuntimeReminderState>> reminderState(int recordId) =>
      Future.error(UnsupportedError('Reminder state is unavailable.'));
  Future<Map<String, dynamic>> aggregate(
    String collectionId,
    Map<String, dynamic> query,
    Map<String, dynamic> aggregate,
  ) => Future.error(UnsupportedError('Aggregates are unavailable.'));
  Future<Uint8List> readImage(String assetId, {bool thumbnail = true}) =>
      Future.error(UnsupportedError('Images are unavailable.'));
  Future<Uint8List?> pickImage() async => null;
  Future<String> uploadImage(
    Uint8List imageBytes, {
    required String collectionId,
    required String fieldId,
    RuntimeItem? record,
  }) => Future.error(UnsupportedError('Image uploads are unavailable.'));
}

class RuntimeSummary {
  final int total;
  final Map<String, int> groups;
  const RuntimeSummary(this.total, this.groups);
}

class RuntimeReminderState {
  final String ruleId, state;
  final DateTime? scheduledAt;
  final bool eligible;
  const RuntimeReminderState(
    this.ruleId,
    this.state, {
    this.scheduledAt,
    this.eligible = true,
  });
}

/// Deliberately has no Client, HTTP, invitations, storage, or scheduler dependency.
class PreviewRuntimeAdapter extends RuntimeAdapter {
  @override
  late final PreviewDeviceCapabilitiesAdapter deviceCapabilities =
      PreviewDeviceCapabilitiesAdapter(spec);
  @override
  AppSpec get spec => _spec;
  AppSpec _spec;
  final _changes = StreamController<void>.broadcast();
  final _presentationChanges = StreamController<void>.broadcast();
  final _items = <RuntimeItem>[];
  final _receipts = <String, String>{};
  final Future<Uint8List?> Function()? _pickImage;
  final Map<String, Uint8List> _imageAssets;
  int _imageSequence = 0;
  PreviewRuntimeAdapter(
    AppSpec spec, {
    DateTime? now,
    Future<Uint8List?> Function()? pickImage,
    Map<String, Uint8List> imageAssets = const {},
  }) : _spec = spec,
       _pickImage = pickImage,
       _imageAssets = Map.of(imageAssets) {
    for (final col in spec.collections) {
      for (final data in syntheticRecords(col, now: now)) {
        _items.add(
          RuntimeItem(
            _items.length + 1,
            col.id,
            data,
            capacity: col.behaviors.any((b) => b.type == 'capacity.v1')
                ? 4
                : null,
            allocated: 0,
            allowedActions: spec.actions
                .where((a) => a.collectionId == col.id)
                .map((a) => a.id)
                .toList(),
          ),
        );
      }
    }
  }
  @override
  bool get preview => true;
  @override
  bool get readOnly => false;
  @override
  String get role => 'owner';
  @override
  List<String> get approvedRuleIds =>
      spec.automationRequests.map((r) => r.id).toList();
  @override
  bool permits(ActionSpec action) => true;
  @override
  Stream<void> watch() => _changes.stream;
  @override
  Future<List<String>> members() async => ['preview_member'];
  @override
  Future<RuntimePage> query(
    String collectionId,
    Map<String, dynamic> query,
  ) async {
    final collection = spec.collection(collectionId);
    final parsed = RecordQuery.parse(collection, query);
    var items = _matchingItems(collection, parsed);
    final total = items.length;
    final fingerprint = hashJson({
      'collection': collectionId,
      'filters': parsed.filters,
      'sort': parsed.sort,
    });
    if (parsed.cursor != null) {
      final index = items.indexWhere(
        (r) => 'preview-$fingerprint-${r.id}' == parsed.cursor,
      );
      if (index < 0)
        throw const SpecException('Preview cursor is stale. Refresh the view.');
      items = items.skip(index + 1).toList();
    }
    final more = items.length > parsed.limit;
    items = items.take(parsed.limit).toList();
    return RuntimePage(
      items,
      total,
      more ? 'preview-$fingerprint-${items.last.id}' : null,
    );
  }

  List<RuntimeItem> _matchingItems(
    CollectionSpec collection,
    RecordQuery parsed,
  ) {
    Object? comparable(String fieldId, Object? value) =>
        value != null && collection.field(fieldId).type == FieldType.timestamp
        ? DateTime.parse(value as String).toUtc()
        : value;
    var items = _items.where((r) => r.collectionId == collection.id).toList();
    for (final f in parsed.filters) {
      items = items.where((r) {
        final fieldId = f['fieldId'] as String;
        final value = comparable(fieldId, r.data[fieldId]);
        final expected = comparable(
          fieldId,
          f['operator'] == 'in' ? null : f['value'],
        );
        return switch (f['operator']) {
          'eq' => value == expected,
          'in' =>
            (f['value'] as List)
                .map((item) => comparable(fieldId, item))
                .contains(value),
          'contains' =>
            value is String &&
                value.toLowerCase().contains(expected.toString().toLowerCase()),
          'gte' =>
            value != null &&
                expected != null &&
                (value as Comparable).compareTo(expected) >= 0,
          'lt' =>
            value != null &&
                expected != null &&
                (value as Comparable).compareTo(expected) < 0,
          'lte' =>
            value != null &&
                expected != null &&
                (value as Comparable).compareTo(expected) <= 0,
          _ => false,
        };
      }).toList();
    }
    items.sort((a, b) {
      for (final sort in parsed.sort) {
        final fieldId = sort['fieldId'] as String;
        final x = comparable(fieldId, a.data[fieldId]),
            y = comparable(fieldId, b.data[fieldId]);
        // PostgreSQL's runtime compiler uses NULLS LAST in both directions.
        if (x == null && y != null) return 1;
        if (y == null && x != null) return -1;
        if (x == null) continue;
        final compared = x is bool
            ? x.toString().compareTo(y.toString())
            : (x as Comparable).compareTo(y);
        if (compared != 0)
          return sort['descending'] == true ? -compared : compared;
      }
      return a.id.compareTo(b.id);
    });
    return items;
  }

  @override
  Future<RuntimeItem> get(int recordId) async =>
      _items.where((r) => r.id == recordId).firstOrNull ??
      (throw const SpecException('Record unavailable.'));

  @override
  Future<RuntimeSummary> summary(
    String collectionId,
    Map<String, dynamic> query,
    String groupFieldId,
  ) async {
    final field = spec.collection(collectionId).field(groupFieldId);
    if (field.type != FieldType.choice) {
      throw const SpecException('Summaries require a choice field.');
    }
    final groups = {for (final choice in field.choices) choice: 0};
    // Capture one synchronous snapshot, just as the live adapter aggregates in
    // one transaction. Neither pagination nor concurrent preview edits narrow it.
    final items = _matchingItems(
      spec.collection(collectionId),
      RecordQuery.parse(spec.collection(collectionId), query),
    );
    for (final item in items) {
      final value = item.data[groupFieldId];
      if (value != null) groups['$value'] = (groups['$value'] ?? 0) + 1;
    }
    return RuntimeSummary(items.length, groups);
  }

  @override
  Future<Map<String, dynamic>> aggregate(
    String collectionId,
    Map<String, dynamic> query,
    Map<String, dynamic> aggregate,
  ) async {
    final collection = spec.collection(collectionId);
    AggregateQuery.parse(collection, aggregate);
    final items = _matchingItems(
      collection,
      RecordQuery.parse(collection, query),
    );
    num? value(List<RuntimeItem> records) {
      if (aggregate['metric'] == 'count') return records.length;
      final values = records
          .map((r) => r.data[aggregate['fieldId']])
          .whereType<num>()
          .toList();
      final sum = values.fold<num>(0, (a, b) => a + b);
      return aggregate['metric'] == 'average'
          ? (values.isEmpty ? null : sum / values.length)
          : sum;
    }

    final groups = <Map<String, dynamic>>[];
    if (aggregate['groupFieldId'] case final String fieldId) {
      for (final choice in collection.field(fieldId).choices) {
        final group = items.where((r) => r.data[fieldId] == choice).toList();
        groups.add({
          'key': choice,
          'count': group.length,
          'value': value(group),
        });
      }
      final missing = items.where((r) => r.data[fieldId] == null).toList();
      if (missing.isNotEmpty)
        groups.add({
          'key': '',
          'count': missing.length,
          'value': value(missing),
        });
    }
    if (aggregate['dateFieldId'] case final String fieldId) {
      for (final raw in aggregate['buckets'] as List) {
        final bucket = Map<String, dynamic>.from(raw);
        final start = DateTime.parse(bucket['start'] as String);
        final end = DateTime.parse(bucket['end'] as String);
        final group = items.where((r) {
          final date = DateTime.tryParse('${r.data[fieldId]}');
          return date != null && !date.isBefore(start) && date.isBefore(end);
        }).toList();
        groups.add({
          'key': bucket['key'],
          'count': group.length,
          'value': value(group),
        });
      }
    }
    return {'total': items.length, 'value': value(items), 'groups': groups};
  }

  @override
  Future<Uint8List?> pickImage() async =>
      _pickImage == null ? null : await _pickImage();

  @override
  Future<Uint8List> readImage(String assetId, {bool thumbnail = true}) async =>
      _imageAssets[assetId] ??
      (throw const SpecException('Preview image unavailable.'));

  /// The builder may supply already-authorized images without giving this
  /// isolated adapter a network or storage dependency.
  void setImageAsset(String assetId, Uint8List bytes) =>
      setImageAssets({assetId: bytes});

  void setImageAssets(Map<String, Uint8List> images) {
    _imageAssets.addAll(images);
    _changes.add(null);
  }

  @override
  Future<String> uploadImage(
    Uint8List imageBytes, {
    required String collectionId,
    required String fieldId,
    RuntimeItem? record,
  }) async {
    if (spec.collection(collectionId).field(fieldId).type != FieldType.image ||
        imageBytes.isEmpty ||
        imageBytes.length > 5 * 1024 * 1024) {
      throw const SpecException('Choose an image of at most 5 MiB.');
    }
    final jpeg =
        imageBytes.length >= 3 &&
        imageBytes[0] == 255 &&
        imageBytes[1] == 216 &&
        imageBytes[2] == 255;
    final png =
        imageBytes.length >= 8 &&
        imageBytes[0] == 137 &&
        String.fromCharCodes(imageBytes.sublist(1, 4)) == 'PNG';
    final webp =
        imageBytes.length >= 12 &&
        String.fromCharCodes(imageBytes.sublist(0, 4)) == 'RIFF' &&
        String.fromCharCodes(imageBytes.sublist(8, 12)) == 'WEBP';
    if (!jpeg && !png && !webp)
      throw const SpecException('Choose a JPEG, PNG or WebP image.');
    final buffer = await ui.ImmutableBuffer.fromUint8List(imageBytes);
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      if (descriptor.width * descriptor.height > 16000000)
        throw const SpecException('Images must be at most 16 megapixels.');
      codec = await descriptor.instantiateCodec(
        targetWidth: 1,
        targetHeight: 1,
      );
      if (codec.frameCount != 1)
        throw const SpecException('Choose a single-frame image.');
    } finally {
      codec?.dispose();
      descriptor?.dispose();
      buffer.dispose();
    }
    final id = 'preview_upload_${++_imageSequence}';
    _imageAssets[id] = Uint8List.fromList(imageBytes);
    return id;
  }

  @override
  Future<List<RuntimeReminderState>> reminderState(int recordId) async {
    final item = await get(recordId);
    return [
      for (final rule in spec.automationRequests.where(
        (r) => r.collectionId == item.collectionId,
      ))
        _previewReminder(rule, item),
    ];
  }

  RuntimeReminderState _previewReminder(AutomationSpec rule, RuntimeItem item) {
    final date = DateTime.tryParse('${item.data[rule.fieldId]}');
    final condition = rule.condition;
    final eligible =
        condition == null || item.data[condition.fieldId] == condition.value;
    return RuntimeReminderState(
      rule.id,
      date == null ? 'unset' : 'pending',
      scheduledAt: date?.subtract(Duration(seconds: rule.offsetSeconds)),
      eligible: eligible,
    );
  }

  @override
  Future<void> execute(
    ActionSpec action,
    RuntimeItem? record,
    Map<String, dynamic> input,
    String key,
  ) async {
    final requestHash = hashJson({
      'action': action.id,
      'record': record?.id,
      'revision': record?.revision,
      'input': input,
    });
    if (_receipts.containsKey(key)) {
      if (_receipts[key] != requestHash)
        throw const SpecException(
          'This command key was already used for different input.',
        );
      return;
    }
    if (!permits(action) ||
        readOnly ||
        hashJson(spec.action(action.id).toJson()) !=
            hashJson(action.toJson())) {
      throw const SpecException('This action is unavailable.');
    }
    final col = spec.collection(action.collectionId);
    if (record != null) {
      final current = await get(record.id);
      if (current.collectionId != col.id ||
          current.revision != record.revision) {
        throw const SpecException(
          'This record changed. Refresh before saving.',
        );
      }
    }
    if (action.capability == 'records.create.v1') {
      final data = col.normalizeRecord(
        Map<String, dynamic>.from(input['data']),
      );
      for (final behavior in col.behaviors.where(
        (b) => b.type == 'workflow.v1',
      )) {
        if (data[behavior.fieldId] !=
            col.field(behavior.fieldId!).choices.first) {
          throw const SpecException(
            'New records must start in the initial status.',
          );
        }
      }
      _items.add(
        RuntimeItem(
          _items.length + 1,
          col.id,
          data,
          capacity: input['capacity'] as int?,
          allocated: 0,
          allowedActions: spec.actions
              .where((a) => a.collectionId == col.id)
              .map((a) => a.id)
              .toList(),
        ),
      );
    } else if (record != null) {
      final data = {...record.data};
      var cap = record.capacity,
          allocated = record.allocated,
          claimed = record.claimed;
      switch (action.capability) {
        case 'records.patch.v1':
          final patch = Map<String, dynamic>.from(input['data']);
          if (col.behaviors.any(
            (b) => b.fieldId != null && patch.containsKey(b.fieldId),
          )) {
            throw const SpecException(
              'Use the approved status or assignment action.',
            );
          }
          data.addAll(patch);
        case 'assignment.assign.v1' || 'workflow.transition.v1':
          final behavior = col.behavior(action.behaviorId!);
          if (action.capability == 'workflow.transition.v1' &&
              !(behavior.transitions[data[behavior.fieldId]] ?? []).contains(
                input['value'],
              )) {
            throw const SpecException('That status transition is not allowed.');
          }
          if (action.capability == 'assignment.assign.v1' &&
              !(await members()).contains(input['value'])) {
            throw const SpecException('Choose an eligible member.');
          }
          data[behavior.fieldId!] = input['value'];
        case 'capacity.configure.v1':
          cap = input['capacity'] as int;
          if (cap < (allocated ?? 0))
            throw const SpecException('Capacity cannot be below sign-ups.');
        case 'capacity.claim.v1':
          if (!claimed) {
            if ((allocated ?? 0) >= (cap ?? 0))
              throw const SpecException('This preview shift is full.');
            claimed = true;
            allocated = (allocated ?? 0) + 1;
          }
        case 'capacity.release.v1':
          if (claimed) {
            claimed = false;
            allocated = (allocated ?? 1) - 1;
          }
      }
      _items[_items.indexWhere((r) => r.id == record.id)] = RuntimeItem(
        record.id,
        col.id,
        col.normalizeRecord(data),
        revision: record.revision + 1,
        capacity: cap,
        allocated: allocated,
        claimed: claimed,
        allowedActions: record.allowedActions,
      );
    }
    _receipts[key] = requestHash;
    _changes.add(null);
  }

  /// Applies a validated presentation patch without replacing sample records.
  void applyPresentationPatch(Map<String, dynamic> patch) {
    if (!{
      'RenameLabel',
      'RenameField',
      'SetTheme',
      'SetAppearance',
      'UpdatePage',
      'UpdateView',
      'ReorderView',
    }.contains(patch['type'])) {
      throw ArgumentError('Not a presentation patch');
    }
    final next = spec.patch(patch, () => throw StateError('No new IDs'));
    applyPresentationSpec(next);
  }

  /// Reuses this sandbox for a validated design change, retaining user-created
  /// sample records, claims, uploaded images and command receipts.
  void applyPresentationSpec(AppSpec next) {
    _checkPresentationSpec(next);
    _spec = next;
    deviceCapabilities.updateSpec(next);
    _presentationChanges.add(null);
    _changes.add(null);
  }

  /// Independent, deep copy for style thumbnails. No synthetic data is reseeded.
  PreviewRuntimeAdapter forkPresentation(AppSpec next) {
    _checkPresentationSpec(next);
    final fork = PreviewRuntimeAdapter(
      next,
      imageAssets: {
        for (final entry in _imageAssets.entries)
          entry.key: Uint8List.fromList(entry.value),
      },
    );
    fork._items
      ..clear()
      ..addAll(
        _items.map(
          (item) => RuntimeItem(
            item.id,
            item.collectionId,
            Map<String, dynamic>.from(_copyPreviewValue(item.data) as Map),
            revision: item.revision,
            capacity: item.capacity,
            allocated: item.allocated,
            claimed: item.claimed,
            allowedActions: List.of(item.allowedActions),
          ),
        ),
      );
    fork._receipts.addAll(_receipts);
    fork._imageSequence = _imageSequence;
    return fork;
  }

  void _checkPresentationSpec(AppSpec next) {
    // Reparse to enforce schema/capability validation on directly constructed specs.
    AppSpec.parse(canonicalJson(next.toJson()));
    final before = spec.toJson(), after = next.toJson();
    Map<String, dynamic> behavior(Map<String, dynamic> value) {
      final result = Map<String, dynamic>.from(value)
        ..remove('name')
        ..remove('theme')
        ..remove('appearance')
        ..remove('icon');
      result['collections'] = [
        for (final c in value['collections'])
          {
            ...c as Map<String, dynamic>,
            'label': '',
            'fields': [
              for (final f in c['fields'])
                {...f as Map<String, dynamic>, 'label': ''},
            ],
          },
      ];
      result['views'] = [
        for (final v in value['views'])
          {
            ...v as Map<String, dynamic>,
            'label': '',
            'presentation': null,
            'options': _bindingOptions(v),
          },
      ]..sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
      if (value['navigation'] != null)
        result['navigation'] = {
          ...value['navigation'] as Map<String, dynamic>,
          'pages': [
            for (final p in value['navigation']['pages'])
              {
                ...p as Map<String, dynamic>,
                'title': '',
                'showDate': false,
                'layout': null,
                'viewIds': [...p['viewIds'] as List]..sort(),
              },
          ],
        };
      // Presentation may opt into configured-view capability.
      result['requires'] = [...value['requires'] as List]
        ..remove('views.configured.v1')
        ..remove('views.interactive.v1')
        ..remove('appearance.v1')
        ..remove('navigation.layouts.v1');
      return result;
    }

    if (canonicalJson(behavior(before)) != canonicalJson(behavior(after))) {
      throw ArgumentError('Patch changes preview behavior');
    }
  }

  Map<String, dynamic> _bindingOptions(Map<String, dynamic> view) {
    final options = Map<String, dynamic>.from(view['options'] as Map? ?? {});
    final presentationKeys = switch (view['type']) {
      'clock' => ['style', 'hourFormat', 'showSeconds', 'showDate'],
      'timer' => ['durationMinutes'],
      'chart' => ['style'],
      'metric' => ['target'],
      'richText' => ['markdown'],
      'banner' => [
        'title',
        'body',
        'imageAssetId',
        'imageAlt',
        'tone',
        'imagePlacement',
      ],
      'form' => ['controls', 'steps'],
      _ => <String>[],
    };
    for (final key in presentationKeys) {
      options.remove(key);
    }
    return options;
  }

  void dispose() {
    deviceCapabilities.dispose();
    timerController.dispose();
    _imageAssets.clear();
    _presentationChanges.close();
    _changes.close();
  }
}

Object? _copyPreviewValue(Object? value) => switch (value) {
  Map() => {
    for (final entry in value.entries)
      entry.key: _copyPreviewValue(entry.value),
  },
  List() => value.map(_copyPreviewValue).toList(),
  _ => value,
};

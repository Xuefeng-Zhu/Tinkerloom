// Hand-authored connected verification. This file is not generated protocol code.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:appnest_client/appnest_client.dart';
import 'package:appnest_spec/appnest_spec.dart';

class _DemoKey implements ClientAuthKeyProvider {
  final String token;
  _DemoKey(this.token);
  @override
  Future<String?> get authHeaderValue async =>
      wrapAsBearerAuthHeaderValue(token);
}

void _check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> _denied(
  Future<Object?> Function() operation,
  String category,
) async {
  try {
    await operation();
  } on NestError catch (error) {
    _check(
      error.category == category,
      'Expected $category, got ${error.category}.',
    );
    return;
  }
  throw StateError('Expected the server to reject $category.');
}

/// A visibly synthetic 600x400 PNG. Uncompressed pixel data deliberately exceeds
/// the old 512 KiB request ceiling; no files or external image services are used.
Uint8List _syntheticPng() {
  const width = 600, height = 400;
  final pixels = BytesBuilder(copy: false);
  for (var y = 0; y < height; y++) {
    pixels.addByte(0);
    for (var x = 0; x < width; x++) {
      final accent = (x ~/ 50 + y ~/ 50).isEven;
      pixels.add(accent ? [29, 115, 102] : [236, 204, 125]);
    }
  }
  Uint8List uint32(int value) =>
      (ByteData(4)..setUint32(0, value)).buffer.asUint8List();
  Uint8List chunk(String type, List<int> data) {
    final content = [...ascii.encode(type), ...data];
    var crc = 0xffffffff;
    for (final byte in content) {
      crc ^= byte;
      for (var bit = 0; bit < 8; bit++) {
        crc = (crc & 1) == 1 ? 0xedb88320 ^ (crc >> 1) : crc >> 1;
      }
    }
    return Uint8List.fromList([
      ...uint32(data.length),
      ...content,
      ...uint32(crc ^ 0xffffffff),
    ]);
  }

  return Uint8List.fromList([
    137,
    80,
    78,
    71,
    13,
    10,
    26,
    10,
    ...chunk('IHDR', [...uint32(width), ...uint32(height), 8, 2, 0, 0, 0]),
    ...chunk('IDAT', ZLibEncoder(level: 0).convert(pixels.takeBytes())),
    ...chunk('IEND', []),
  ]);
}

class _Smoke {
  final String url;
  final String runId = DateTime.now()
      .toUtc()
      .toIso8601String()
      .replaceAll(':', '')
      .replaceAll('.', '');
  final Set<Client> clients = {};
  final List<Map<String, Object?>> created = [];
  String phase = 'sign in';
  _Smoke(this.url);

  Future<Client> login(String name) async {
    final client = Client(url);
    clients.add(client);
    final auth = await client.emailIdp.login(
      email: '$name@appnest.local',
      password: 'AppNest-local-demo-2026!',
    );
    client.authKeyProvider = _DemoKey(auth.token);
    _check(
      (await client.builder.platform()).development,
      'Only a development server is allowed.',
    );
    return client;
  }

  void close(Client client) {
    client.close();
    clients.remove(client);
  }

  Future<BuilderSnapshot> draft(
    Client owner,
    int workspace,
    String template,
    String label,
  ) async {
    var value = await owner.builder.begin(workspace, template, null);
    final name = 'Rich smoke $runId · $label';
    // Record each new app immediately so an interrupted run is identifiable.
    created.add({'appId': value.appId, 'template': template, 'name': name});
    value = await owner.builder.patch(
      value.draftId,
      value.mutation,
      jsonEncode({'type': 'RenameLabel', 'targetId': 'app', 'label': name}),
    );
    return value;
  }

  Future<int> publish(Client owner, BuilderSnapshot value) =>
      owner.builder.publish(
        PublishRequest(
          draftId: value.draftId,
          candidateHash: value.candidateHash,
          expectedCurrentVersionId: value.baseVersionId,
          enabledRuleIds: [],
          activateExistingRecordIds: [],
          reviewHash: hashJson({
            'candidateHash': value.candidateHash,
            'enabledRuleIds': [],
            'activateExistingRecordIds': [],
          }),
          idempotencyKey:
              'rich-smoke-publish-${value.draftId}-${value.candidateHash}',
        ),
      );

  Future<Map<String, dynamic>> aggregate(
    Client owner,
    int appId,
    Map<String, dynamic> metric, {
    Map<String, dynamic> query = const {'limit': 1},
  }) async => jsonDecode(
    await owner.runtime.aggregate(
      appId,
      'checkins',
      jsonEncode(query),
      jsonEncode(metric),
    ),
  ) as Map<String, dynamic>;

  Future<void> run() async {
    var owner = await login('morgan');
    var participant = await login('alex');
    final participantId = (await participant.builder.platform()).actorId;
    final workspace = (await owner.apps.workspaces()).firstWhere(
      (w) => w.name == 'AppNest demo',
    );
    stdout.writeln(
      'Connected synthetic rich smoke $runId. Template/manual path; no AI calls or reminders.',
    );

    phase = 'private draft upload and Photo Journal publication';
    var photos = await draft(owner, workspace.id, 'photoJournal', 'Photos');
    final png = _syntheticPng();
    _check(
      png.length > 512 * 1024 && png.length < 5 * 1024 * 1024,
      'Synthetic PNG must exercise the expanded upload limit.',
    );
    final uploadRequest = MediaUploadRequest(
      appId: photos.appId,
      draftId: photos.draftId,
      byteLength: png.length,
      contentType: 'image/png',
      idempotencyKey: 'rich-smoke-image',
    );
    final ticket = await owner.media.beginUpload(uploadRequest);
    _check(
      (await owner.media.beginUpload(uploadRequest)).assetId == ticket.assetId,
      'Repeated upload preparation must return the same asset.',
    );
    _check(
      await FileUploader(ticket.uploadDescription)
          .uploadByteData(ByteData.sublistView(png)),
      'Upload transport did not succeed.',
    );
    final image = await owner.media.completeUpload(
      photos.appId,
      ticket.assetId,
    );
    _check(
      image.width == 600 && image.height == 400,
      'Sanitized image dimensions changed unexpectedly.',
    );
    _check(
      (await owner.media.completeUpload(
            photos.appId,
            ticket.assetId,
          )).assetId ==
          ticket.assetId,
      'Completion retry must be idempotent.',
    );
    final display = await owner.media.readImage(
      photos.appId,
      ticket.assetId,
      'display',
    );
    final imageFingerprint = hashJson(Uint8List.sublistView(display));
    _check(
      (await owner.media.readImage(
            photos.appId,
            ticket.assetId,
            'thumbnail',
          )).lengthInBytes >
          0,
      'Thumbnail missing.',
    );
    photos = await owner.builder.patch(
      photos.draftId,
      photos.mutation,
      jsonEncode({
        'type': 'AddPage',
        'page': {'title': 'Synthetic image'},
        'tab': {'label': 'Image proof', 'icon': 'spark'},
        'newViews': [
          {
            'type': 'banner',
            'label': 'Connected upload',
            'options': {
              'title': 'A privately stored image',
              'body': 'Synthetic checkerboard uploaded by the connected smoke script.',
              'imageAssetId': ticket.assetId,
              'imageAlt': 'Teal and gold synthetic checkerboard',
            },
          },
        ],
      }),
    );
    final photoVersion = await publish(owner, photos);
    final memory = await owner.runtime.execute(
      ActionRequest(
        appId: photos.appId,
        actionId: 'addRecord',
        expectedDefinitionVersionId: photoVersion,
        input: {
          'data': {
            'title': 'Connected private image',
            'photo': ticket.assetId,
            'caption': 'Synthetic evidence; safe to remove with this test app.',
            'takenAt': DateTime.now().toUtc().toIso8601String(),
            'rating': 4,
            'favorite': true,
          },
        },
        idempotencyKey: 'rich-smoke-memory',
      ),
    );
    _check(
      (await owner.runtime.get(photos.appId, memory.recordId)).data['photo'] ==
          ticket.assetId,
      'Saved record lost the image reference.',
    );
    await _denied(
      () =>
          participant.media.readImage(photos.appId, ticket.assetId, 'display'),
      'notFound',
    );
    await participant.apps.acceptInvitation(
      await owner.apps.invite(photos.appId, 'viewer', null),
    );
    _check(
      (await participant.media.readImage(
            photos.appId,
            ticket.assetId,
            'display',
          )).lengthInBytes >
          0,
      'Viewer cannot read an approved app image.',
    );
    await _denied(
      () => participant.runtime.execute(
        ActionRequest(
          appId: photos.appId,
          actionId: 'addRecord',
          expectedDefinitionVersionId: photoVersion,
          input: {
            'data': {'title': 'Must not be saved'},
          },
          idempotencyKey: 'denied-viewer',
        ),
      ),
      'forbidden',
    );
    await owner.apps.setGrant(photos.appId, participantId, null);
    await _denied(
      () =>
          participant.media.readImage(photos.appId, ticket.assetId, 'display'),
      'notFound',
    );
    stdout.writeln(
      'PASS private image: ${png.length} input bytes, sanitized display/thumbnail, draft banner, record reference, viewer access and revocation. App ${photos.appId}.',
    );

    phase = 'Project Hub workflow, revision checks and action receipts';
    final projects = await draft(owner, workspace.id, 'projectHub', 'Workflow');
    final projectVersion = await publish(owner, projects);
    await _denied(
      () => owner.media.readImage(projects.appId, ticket.assetId, 'display'),
      'notFound',
    );
    await participant.apps.acceptInvitation(
      await owner.apps.invite(projects.appId, 'member', null),
    );
    final task = await owner.runtime.execute(
      ActionRequest(
        appId: projects.appId,
        actionId: 'addRecord',
        expectedDefinitionVersionId: projectVersion,
        input: {
          'data': {
            'title': 'Move this synthetic task',
            'status': 'Open',
            'priority': 'Normal',
            'effort': 3,
            'dueAt': DateTime.now().toUtc().toIso8601String(),
            'notes': 'Created by connected verification.',
          },
        },
        idempotencyKey: 'rich-smoke-task',
      ),
    );
    final move = ActionRequest(
      appId: projects.appId,
      actionId: 'moveRecord',
      targetRecordId: task.recordId,
      expectedDefinitionVersionId: projectVersion,
      expectedRecordRevision: task.revision,
      input: {'value': 'Done'},
      idempotencyKey: 'rich-smoke-move-once',
    );
    final moved = await participant.runtime.execute(move);
    final repeated = await participant.runtime.execute(move);
    _check(
      moved.revision == task.revision + 1 &&
          repeated.revision == moved.revision,
      'Workflow receipt replay changed the revision.',
    );
    await _denied(
      () => owner.runtime.execute(
        ActionRequest(
          appId: projects.appId,
          actionId: 'editRecord',
          targetRecordId: task.recordId,
          expectedDefinitionVersionId: projectVersion,
          expectedRecordRevision: task.revision,
          input: {
            'data': {'notes': 'Stale write must fail'},
          },
          idempotencyKey: 'rich-smoke-stale',
        ),
      ),
      'recordConflict',
    );
    await _denied(
      () => owner.runtime.execute(
        ActionRequest(
          appId: projects.appId,
          actionId: 'editRecord',
          targetRecordId: task.recordId,
          expectedDefinitionVersionId: projectVersion,
          expectedRecordRevision: moved.revision,
          input: {
            'data': {'status': 'Open'},
          },
          idempotencyKey: 'rich-smoke-protected',
        ),
      ),
      'forbidden',
    );
    await _denied(
      () =>
          participant.runtime.execute(move.copyWith(input: {'value': 'Open'})),
      'invalidInput',
    );
    final edited = await owner.runtime.execute(
      ActionRequest(
        appId: projects.appId,
        actionId: 'editRecord',
        targetRecordId: task.recordId,
        expectedDefinitionVersionId: projectVersion,
        expectedRecordRevision: moved.revision,
        input: {
          'data': {'notes': 'Persist this note across reconnect.'},
        },
        idempotencyKey: 'rich-smoke-edit',
      ),
    );
    await participant.runtime.execute(move);
    final persistedTask = await owner.runtime.get(
      projects.appId,
      task.recordId,
    );
    _check(
      persistedTask.revision == edited.revision &&
          persistedTask.data['status'] == 'Done',
      'Old receipt replay changed current record state.',
    );
    _check(
      (await owner.apps.activity(projects.appId))
              .where((event) => event.action == 'workflow.transition.v1')
              .length ==
          1,
      'Workflow transition was audited more than once.',
    );
    stdout.writeln(
      'PASS workflow: member transition, repeated receipt, stale revision, protected-field rejection, and later edit preservation. App ${projects.appId}.',
    );

    phase = 'Habit Tracker database-wide aggregates and cursor pagination';
    final habits = await draft(owner, workspace.id, 'habitTracker', 'Metrics');
    final habitVersion = await publish(owner, habits);
    final now = DateTime.now().toUtc();
    final start = DateTime.utc(now.year, now.month, now.day);
    for (var i = 0; i < 106; i++) {
      await owner.runtime.execute(
        ActionRequest(
          appId: habits.appId,
          actionId: 'addRecord',
          expectedDefinitionVersionId: habitVersion,
          input: {
            'data': {
              'title': 'Synthetic metric ${i + 1}',
              'loggedAt':
                  (i == 105
                          ? start.add(const Duration(days: 1))
                          : start.add(Duration(minutes: i)))
                      .toIso8601String(),
              if (i < 105) 'minutes': i.isEven ? 2 : -1,
              'energy': 3,
              'category': i.isEven ? 'Move' : 'Rest',
              'completed': i.isEven,
              'notes': 'Synthetic arithmetic sample; negative values deliberately test chart math.',
            },
          },
          idempotencyKey: 'rich-smoke-metric-$i',
        ),
      );
    }
    final first = await owner.runtime.query(
      habits.appId,
      'checkins',
      '{"limit":100}',
    );
    final next = await owner.runtime.query(
      habits.appId,
      'checkins',
      jsonEncode({'limit': 100, 'cursor': first.nextCursor}),
    );
    _check(
      first.total == 106 &&
          first.records.length == 100 &&
          first.nextCursor != null &&
          next.records.length == 6,
      'Pagination did not cover 106 records.',
    );
    _check(
      {
            ...first.records.map((r) => r.id),
            ...next.records.map((r) => r.id),
          }.length ==
          106,
      'Pagination duplicated records.',
    );
    final count = await aggregate(owner, habits.appId, {'metric': 'count'});
    final sum = await aggregate(owner, habits.appId, {
      'metric': 'sum',
      'fieldId': 'minutes',
      'groupFieldId': 'category',
    });
    final average = await aggregate(owner, habits.appId, {
      'metric': 'average',
      'fieldId': 'minutes',
    });
    _check(
      count['total'] == 106 && count['value'] == 106 && sum['value'] == 54,
      'Aggregates narrowed to the loaded page or lost negative values.',
    );
    _check(
      ((average['value'] as num) - 54 / 105).abs() < .000001,
      'Average must ignore the missing numeric value.',
    );
    final empty = await aggregate(
      owner,
      habits.appId,
      {'metric': 'average', 'fieldId': 'minutes'},
      query: {
        'filters': [
          {'fieldId': 'category', 'operator': 'eq', 'value': 'Learn'},
        ],
      },
    );
    _check(
      empty['total'] == 0 && empty['value'] == null,
      'An empty average must be null.',
    );
    final series = await aggregate(owner, habits.appId, {
      'metric': 'sum',
      'fieldId': 'minutes',
      'dateFieldId': 'loggedAt',
      'buckets': [
        for (var i = 0; i < 3; i++)
          {
            'key': 'day-$i',
            'start': start.add(Duration(days: i)).toIso8601String(),
            'end': start.add(Duration(days: i + 1)).toIso8601String(),
          },
      ],
    });
    final groups = series['groups'] as List;
    _check(
      groups[0]['count'] == 105 &&
          groups[0]['value'] == 54 &&
          groups[1]['count'] == 1 &&
          groups[1]['value'] == 0 &&
          groups[2]['count'] == 0,
      'Time-series boundaries or empty buckets are incorrect.',
    );
    stdout.writeln(
      'PASS data: 106 persisted records, 100+6 cursor pages, count106, sum54, average54/105, empty average and three time buckets. App ${habits.appId}.',
    );

    phase = 'fresh-client reconnect persistence';
    close(owner);
    close(participant);
    owner = await login('morgan');
    participant = await login('alex');
    for (final value in [photos, projects, habits]) {
      final manifest = await owner.apps.manifest(value.appId);
      _check(
        AppSpec.parse(manifest.specJson!).hash == value.candidateHash,
        'Published definition did not survive fresh-client reload.',
      );
    }
    _check(
      hashJson(
            Uint8List.sublistView(
              await owner.media.readImage(
                photos.appId,
                ticket.assetId,
                'display',
              ),
            ),
          ) ==
          imageFingerprint,
      'Image bytes changed across reconnect.',
    );
    _check(
      (await owner.runtime.get(photos.appId, memory.recordId)).data['photo'] ==
          ticket.assetId,
      'Image reference did not persist.',
    );
    final reopenedTask = await owner.runtime.get(projects.appId, task.recordId);
    _check(
      reopenedTask.revision == edited.revision &&
          reopenedTask.data['notes'] == 'Persist this note across reconnect.',
      'Task changes did not persist.',
    );
    _check(
      (await aggregate(owner, habits.appId, {
            'metric': 'sum',
            'fieldId': 'minutes',
          }))['value'] ==
          54,
      'Aggregate changed after reconnect.',
    );
    await _denied(
      () =>
          participant.media.readImage(photos.appId, ticket.assetId, 'display'),
      'notFound',
    );
    stdout.writeln(
      'PASS fresh logins: definitions, private image bytes/references, workflow revision, notes, metrics and revoked access persist.',
    );
    stdout.writeln(
      jsonEncode({
        'result': 'passed',
        'runId': runId,
        'apps': created,
        'photoRecordId': memory.recordId,
        'projectRecordId': task.recordId,
        'metricRecords': 106,
        'limitations': [
          'Client reconnect verified; this script does not restart the server.',
          'No live AI, reminder delivery, or browser UI evidence from this script.',
        ],
      }),
    );
  }
}

Future<void> main(List<String> args) async {
  if (!args.contains('--run-rich-smoke')) {
    stderr.writeln(
      'Pass --run-rich-smoke. Creates three clearly labelled synthetic apps and 108 records on the local development server; it never deletes existing data.',
    );
    exitCode = 64;
    return;
  }
  final argument = args
      .where((arg) => arg.startsWith('--base-url='))
      .firstOrNull;
  final uri = Uri.parse(
    argument?.substring('--base-url='.length) ?? 'http://localhost:8180/',
  );
  if (!{'localhost', '127.0.0.1', '::1'}.contains(uri.host) ||
      !{'http', 'https'}.contains(uri.scheme) ||
      uri.userInfo.isNotEmpty) {
    stderr.writeln(
      'This synthetic verification script accepts only loopback HTTP(S) servers.',
    );
    exitCode = 64;
    return;
  }
  final smoke = _Smoke(uri.toString().endsWith('/') ? uri.toString() : '$uri/');
  try {
    await smoke.run();
  } catch (error) {
    // Never print authentication tokens, upload descriptions, or raw transport errors.
    stderr.writeln(
      'FAIL during ${smoke.phase}: ${error is NestError
          ? '${error.category}: ${error.message}'
          : error is StateError
          ? error.message
          : error.runtimeType}.',
    );
    stdout.writeln(
      jsonEncode({
        'result': 'failed',
        'runId': smoke.runId,
        'phase': smoke.phase,
        'appsCreated': smoke.created,
      }),
    );
    exitCode = 1;
  } finally {
    for (final client in smoke.clients.toList()) {
      smoke.close(client);
    }
  }
}

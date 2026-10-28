import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:appnest_spec/appnest_spec.dart' as spec;
import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as image;

import '../lib/service.dart';
import 'memory_store.dart';
import 'spec_engine_check.dart' as engine;

void check(bool value, String message) => engine.check(value, message);
String digest(List<int> bytes) => sha256.convert(bytes).toString();
Row copy(Row row) => jsonDecode(jsonEncode(row)) as Row;

class Files implements PrivateFileStore {
  final values = <String, Uint8List>{};
  Future<void> Function(String)? beforeRead, beforePut, beforeRemove;
  bool losePut = false, failRemove = false;
  int puts = 0;
  @override
  Future<void> put(String id, Uint8List bytes, String contentType) async {
    if (beforePut != null) await beforePut!(id);
    puts++;
    final old = values[id];
    if (old != null && digest(old) != digest(bytes))
      throw const ServiceException('operation_conflict', 409);
    values[id] = Uint8List.fromList(bytes);
    if (losePut) {
      losePut = false;
      throw const RestException(502);
    }
  }

  @override
  Future<Uint8List> read(String id, {required int maximumBytes}) async {
    if (beforeRead != null) await beforeRead!(id);
    final bytes = values[id];
    if (bytes == null) throw const RestException(404);
    if (bytes.length > maximumBytes)
      throw const ServiceException('media_integrity', 502);
    return Uint8List.fromList(bytes);
  }

  @override
  Future<void> remove(String id) async {
    if (beforeRemove != null) await beforeRemove!(id);
    if (failRemove) throw const RestException(502);
    values.remove(id);
  }
}

/// Counts physical staged creates/updates, including repeated writes to one row.
/// This models the Free 100-operation budget; it is not an Appwrite receipt.
class BudgetStore extends MemoryStore {
  final operations = <String, int>{};
  int peak = 0;
  void count(String? tx) {
    if (tx == null) return;
    final next = (operations[tx] ?? 0) + 1;
    operations[tx] = next;
    if (next > peak) peak = next;
    if (next > 100)
      throw StateError('Transaction exceeded 100 staged operations');
  }

  @override
  Future<String> beginTransaction() async {
    final tx = await super.beginTransaction();
    operations[tx] = 0;
    return tx;
  }

  @override
  Future<Row> create(
    String table,
    String id,
    Row data, {
    String? transactionId,
  }) {
    count(transactionId);
    return super.create(table, id, data, transactionId: transactionId);
  }

  @override
  Future<Row> update(
    String table,
    String id,
    Row data, {
    String? transactionId,
  }) {
    count(transactionId);
    return super.update(table, id, data, transactionId: transactionId);
  }

  @override
  Future<void> finishTransaction(String tx, {required bool commit}) async {
    try {
      await super.finishTransaction(tx, commit: commit);
    } finally {
      operations.remove(tx);
    }
  }
}

class Fixture {
  Fixture({MemoryStore? memory, int projectBytes = MediaLimits.maxProjectBytes})
    : store = memory ?? MemoryStore() {
    api = PlatformService(
      store,
      media: files,
      clock: () => now,
      mediaProjectBytes: projectBytes,
    );
  }
  final MemoryStore store;
  final files = Files();
  late final PlatformService api;
  DateTime now = DateTime.utc(2030, 1, 1);
  String? version;
  Future<void> setup({bool publish = true, bool workflow = false}) async {
    await api.execute('alice', {
      'op': 'createWorkspace',
      'id': 'ws',
      'name': 'QA',
    });
    await api.execute('alice', {
      'op': 'spec.createApp',
      'workspaceId': 'ws',
      'id': 'app',
      'name': 'QA images',
      'operationId': 'new-app',
    });
    await api.execute('alice', {
      'op': 'spec.saveDraft',
      'appId': 'app',
      'operationId': 'draft',
      'expectedRevision': 0,
      'expectedVersionId': null,
      'spec': {
        ...spec.photoJournalTemplate().toJson(),
        if (workflow) 'policyPresetRequest': 'groupWorkflow.v1',
      },
    });
    if (publish)
      version = await engine.publish(api, 'alice', 1, null, 'publish');
  }

  Row begin(
    String operation,
    List<int> bytes, {
    String actor = 'alice',
    int? draft,
    String mime = 'image/png',
    String? action,
    String? field,
    String? record,
    int? revision,
  }) => {
    'op': 'spec.media.begin',
    'appId': 'app',
    'operationId': operation,
    'byteLength': bytes.length,
    'contentType': mime,
    'sha256': digest(bytes),
    if (draft != null) 'draftRevision': draft,
    if (draft == null) ...{
      'versionId': version,
      'actionId': action ?? 'addRecord',
      'fieldId': field ?? 'photo',
    },
    if (record != null) 'targetRecordId': record,
    if (revision != null) 'expectedRecordRevision': revision,
  };
  Future<String> reserve(
    String operation,
    List<int> bytes, {
    String actor = 'alice',
    int? draft,
    String mime = 'image/png',
  }) async =>
      ((await api.execute(
                actor,
                begin(operation, bytes, draft: draft, mime: mime),
              ))['asset']
              as Map)['assetId']
          as String;
  Row chunk(String id, List<int> bytes, {int offset = 0}) => {
    'op': 'spec.media.chunk',
    'appId': 'app',
    'assetId': id,
    'offset': offset,
    'sha256': digest(bytes),
    'dataBase64': base64Encode(bytes),
  };
  Future<void> upload(
    String id,
    List<int> bytes, {
    String actor = 'alice',
  }) async {
    for (
      var offset = 0;
      offset < bytes.length;
      offset += MediaLimits.chunkBytes
    ) {
      final end = (offset + MediaLimits.chunkBytes).clamp(0, bytes.length);
      await api.execute(
        actor,
        chunk(id, bytes.sublist(offset, end), offset: offset),
      );
    }
  }

  Future<void> complete(String id, {String actor = 'alice'}) async {
    await api.execute(actor, {
      'op': 'spec.media.complete',
      'appId': 'app',
      'assetId': id,
      'operationId': 'c${digest(utf8.encode(id)).substring(0, 32)}',
    });
  }

  Future<String> ready(
    String operation,
    List<int> bytes, {
    String actor = 'alice',
    int? draft,
  }) async {
    final id = await reserve(operation, bytes, actor: actor, draft: draft);
    await upload(id, bytes, actor: actor);
    await complete(id, actor: actor);
    await api.processMedia(id);
    return id;
  }

  Future<Row> status(String id, {String actor = 'alice'}) async =>
      (await api.execute(actor, {
            'op': 'spec.media.status',
            'appId': 'app',
            'assetId': id,
          }))['asset']
          as Row;
  Future<Row> read(
    String id, {
    String actor = 'alice',
    int offset = 0,
    String variant = 'display',
  }) => api.execute(actor, {
    'op': 'spec.media.read',
    'appId': 'app',
    'assetId': id,
    'variant': variant,
    'offset': offset,
  });
  Future<String> record(
    String id, {
    String actor = 'alice',
    String operation = 'record',
  }) async {
    final result = await api.execute(
      actor,
      engine.action(operation, version!, 'addRecord', {
        'data': {'title': 'QA', 'photo': id},
      }),
    );
    return (result['outcome'] as Map)['recordId'] as String;
  }
}

Uint8List png({int width = 8, int height = 5}) {
  final frame = image.Image(width: width, height: height, numChannels: 4);
  for (final p in frame) {
    p
      ..r = p.x * 20
      ..g = p.y * 25
      ..b = 42
      ..a = 180;
  }
  frame.textData = {'private': 'never retain QA metadata'};
  return image.encodePng(frame);
}

Row banner(spec.AppSpec source, String asset) {
  final json = copy(source.toJson());
  (json['views'] as List).add({
    'id': 'cover',
    'type': 'banner',
    'label': 'Cover',
    'options': {
      'title': 'Private image',
      'imageAssetId': asset,
      'imageAlt': 'QA image',
    },
  });
  (json['requires'] as List).add('views.banner.v1');
  return spec.AppSpec.parse(jsonEncode(json)).toJson();
}

Future<void> grant(
  Fixture f,
  String actor, {
  String? role,
  int revision = 1,
  String operation = 'change',
}) async {
  await f.api.execute('alice', {
    'op': 'setGrant',
    'appId': 'app',
    'actorId': actor,
    'role': role,
    'expectedRevision': revision,
    'operationId': operation,
  });
}

Future<int> runMediaChecks() async {
  var passed = 0;
  Future<void> test(String label, Future<void> Function() body) async {
    await body();
    passed++;
    print('PASS $label');
  }

  await test(
    'private media fails closed without storage and preserves the bounded engine',
    () async {
      final (_, api, version) = await engine.fixture('photoJournal');
      check(
        (await api.execute('alice', {
              'op': 'spec.capabilities',
            }))['privateMedia'] ==
            false,
        'False storage claim',
      );
      await engine.error(
        () => api.execute('alice', {
          'op': 'spec.media.begin',
          'appId': 'app',
          'operationId': 'begin',
          'byteLength': 3,
          'sha256': digest([1, 2, 3]),
          'contentType': 'image/png',
          'versionId': version,
          'actionId': 'addRecord',
          'fieldId': 'photo',
        }),
        'capability_unavailable',
      );
    },
  );
  await test(
    'image reservations bind exact intent and receipts reserve worst-case bytes once',
    () async {
      final f = Fixture();
      await f.setup();
      final bytes = png(), command = f.begin('reserve', png());
      final first = await f.api.execute('alice', command);
      check(
        jsonEncode(await f.api.execute('alice', command)) == jsonEncode(first),
        'Begin receipt changed',
      );
      check(f.store.rows['media_assets']!.length == 1, 'Duplicate reservation');
      final quotas = f.store.rows['media_quotas']!.values;
      final reserved =
          bytes.length +
          MediaLimits.maxOriginalBytes +
          MediaLimits.maxThumbnailBytes;
      check(
        quotas.every((q) => q['bytes'] == reserved && q['assets'] == 1),
        'Reservation excludes staging or variants',
      );
      await engine.error(
        () => f.api.execute('alice', {
          ...command,
          'byteLength': bytes.length + 1,
        }),
        'operation_conflict',
      );
      check(
        !jsonEncode(first).contains('requestJson') &&
            !jsonEncode(first).contains('bucket'),
        'Provider/private intent leaked',
      );
      await engine.error(() => f.api.execute('mallory', command), 'not_found');
    },
  );
  await test(
    'upload binding enforces author drafts published version approved image action and target revisions',
    () async {
      final f = Fixture();
      await f.setup(publish: false);
      final bytes = png();
      await engine.error(
        () => f.api.execute('alice', f.begin('old-draft', bytes, draft: 0)),
        'revision_conflict',
      );
      await engine.error(
        () => f.api.execute('alice', {
          ...f.begin('mixed', bytes, draft: 1),
          'versionId': 'v',
        }),
        'invalid_request',
      );
      final id = await f.reserve('draft-img', bytes, draft: 1);
      await f.upload(id, bytes);
      await f.complete(id);
      await f.api.processMedia(id);
      f.version = await engine.publish(f.api, 'alice', 1, null, 'pub');
      await engine.error(
        () => f.api.execute('alice', f.begin('consumed', bytes, draft: 1)),
        'revision_conflict',
      );
      await engine.error(
        () => f.api.execute('alice', f.begin('text', bytes, field: 'title')),
        'invalid_media',
      );
      await engine.error(
        () => f.api.execute(
          'alice',
          f.begin('target', bytes, record: 'made', revision: 1),
        ),
        'invalid_request',
      );
      await engine.join(f.api, 'bob', 1, role: 'viewer');
      await engine.error(
        () => f.api.execute('bob', f.begin('viewer', bytes)),
        'forbidden',
      );
      final record = await f.record(id);
      await engine.error(
        () => f.api.execute(
          'alice',
          f.begin(
            'stale-record',
            bytes,
            action: 'editRecord',
            record: record,
            revision: 0,
          ),
        ),
        'revision_conflict',
      );
      await f.api.execute(
        'alice',
        f.begin(
          'valid-edit',
          bytes,
          action: 'editRecord',
          record: record,
          revision: 1,
        ),
      );
    },
  );
  await test(
    'chunk broker requires bounded canonical base64 sha order exact length and immutable retries',
    () async {
      final f = Fixture();
      await f.setup();
      final bytes = Uint8List(MediaLimits.chunkBytes + 7);
      for (var i = 0; i < bytes.length; i++) bytes[i] = i % 251;
      final id = await f.reserve('chunks', bytes);
      await engine.error(
        () => f.api.execute(
          'alice',
          f.chunk(
            id,
            bytes.sublist(MediaLimits.chunkBytes),
            offset: MediaLimits.chunkBytes,
          ),
        ),
        'revision_conflict',
      );
      await engine.error(
        () => f.api.execute('alice', {
          ...f.chunk(id, bytes.sublist(0, MediaLimits.chunkBytes)),
          'sha256': '0' * 64,
        }),
        'invalid_media',
      );
      await engine.error(
        () => f.api.execute('alice', f.chunk(id, bytes.sublist(0, 5))),
        'invalid_media',
      );
      final first = f.chunk(id, bytes.sublist(0, MediaLimits.chunkBytes));
      await f.api.execute('alice', first);
      final puts = f.files.puts;
      await f.api.execute('alice', first);
      check(f.files.puts == puts, 'Retry repeated Storage write');
      final changed = Uint8List(MediaLimits.chunkBytes)..[0] = 1;
      await engine.error(
        () => f.api.execute('alice', f.chunk(id, changed)),
        'operation_conflict',
      );
      await engine.error(() => f.complete(id), 'media_incomplete');
      await f.api.execute(
        'alice',
        f.chunk(
          id,
          bytes.sublist(MediaLimits.chunkBytes),
          offset: MediaLimits.chunkBytes,
        ),
      );
      check(
        (await f.status(id))['uploadedBytes'] == bytes.length,
        'Status cannot recover upload offset',
      );
      await f.complete(id);
    },
  );
  await test(
    'a lost Storage put response recovers identical private chunks without replacement',
    () async {
      final f = Fixture();
      await f.setup();
      final bytes = png(), id = await f.reserve('lost-put', png());
      f.files.losePut = true;
      try {
        await f.upload(id, bytes);
        throw StateError('Expected transport failure');
      } on RestException {}
      check(
        f.files.values.length == 1 &&
            (await f.status(id))['uploadedBytes'] == 0,
        'Failed write falsely acknowledged',
      );
      await f.upload(id, bytes);
      check(f.files.values.length == 1, 'Retry allocated another file');
      await f.complete(id);
      await f.api.processMedia(id);
      check((await f.status(id))['status'] == 'ready', 'Recovery failed');
    },
  );
  await test(
    'actual sanitizer produces private variants strips metadata and removes staging quota only after removal',
    () async {
      final f = Fixture();
      await f.setup();
      final bytes = png(width: 2200, height: 2);
      final id = await f.reserve('sanitize', bytes);
      await f.upload(id, bytes);
      await f.complete(id);
      f.files.failRemove = true;
      await f.api.processMedia(id);
      var row = f.store.rows['media_assets']![id]!;
      check(
        row['status'] == 'ready' && row['width'] == 2048 && row['height'] == 2,
        'No actual downsample',
      );
      check(
        row['originalRemoved'] == false && f.files.values.length == 3,
        'Failed deletion lost retry paths',
      );
      check(
        row['storedBytes'] ==
            bytes.length +
                (row['displayBytes'] as int) +
                (row['thumbnailBytes'] as int),
        'Original quota released early',
      );
      final response = await f.read(id),
          display = base64Decode(response['dataBase64'] as String);
      check(image.decodeImage(display)!.textData == null, 'Metadata retained');
      check(
        response['chunkSha256'] == digest(display) &&
            response['sha256'] == digest(display) &&
            response['contentType'] == 'image/png' &&
            response['cacheControl'] == 'private, no-store',
        'Unsafe image response',
      );
      f.files.failRemove = false;
      await f.api.cleanupMedia();
      check(
        f.store.rows['media_assets']![id]!['originalRemoved'] == false,
        'Original reservation released before quiet period',
      );
      f.now = f.now.add(
        MediaLimits.deletionQuietPeriod + const Duration(seconds: 1),
      );
      await f.api.cleanupMedia();
      row = f.store.rows['media_assets']![id]!;
      check(
        row['originalRemoved'] == true && f.files.values.length == 2,
        'Original cleanup not resumable',
      );
      check(
        f.store.rows['media_quotas']!.values.every(
          (q) => q['bytes'] == row['storedBytes'],
        ),
        'Quota cleanup mismatch',
      );
      await engine.error(
        () => f.read(id, variant: 'original'),
        'invalid_media',
      );
      await engine.error(() => f.read(id, offset: 1), 'invalid_media');
    },
  );
  await test(
    'declared whole digest MIME corruption and unsupported formats cannot become ready',
    () async {
      for (final mode in ['mime', 'digest', 'corrupt']) {
        final f = Fixture();
        await f.setup();
        final bytes = mode == 'corrupt'
            ? Uint8List.fromList([1, 2, 3, 4])
            : png();
        final command = f.begin(
          'invalid-$mode',
          bytes,
          mime: mode == 'mime' ? 'image/jpeg' : 'image/png',
        );
        if (mode == 'digest') command['sha256'] = '0' * 64;
        final id =
            ((await f.api.execute('alice', command))['asset'] as Map)['assetId']
                as String;
        await f.upload(id, bytes);
        await f.complete(id);
        try {
          await f.api.processMedia(id);
        } on ServiceException catch (e) {
          check(e.code == 'invalid_media', 'Unexpected failure');
        }
        check(
          (await f.status(id))['status'] == 'failed',
          'Malformed bytes became readable',
        );
        await engine.error(() => f.read(id), 'not_found');
      }
    },
  );
  await test(
    'distributed image admission permits two actors but only one concurrent decode per actor',
    () async {
      final f = Fixture();
      await f.setup();
      await engine.join(f.api, 'bob', 2, role: 'builder');
      await engine.join(f.api, 'carol', 3, role: 'builder');
      final ids = <String>[];
      for (final actor in ['alice', 'alice', 'bob', 'carol']) {
        final id = await f.reserve('slot-${ids.length}', png(), actor: actor);
        await f.upload(id, png(), actor: actor);
        await f.complete(id, actor: actor);
        ids.add(id);
      }
      final gate = Completer<void>(),
          first = Completer<void>(),
          second = Completer<void>();
      var calls = 0;
      f.files.beforeRead = (_) async {
        calls++;
        if (calls == 1) first.complete();
        if (calls == 2) second.complete();
        await gate.future;
      };
      final a = f.api.processMedia(ids[0]);
      await first.future;
      await engine.error(() => f.api.processMedia(ids[1]), 'media_busy');
      final b = f.api.processMedia(ids[2]);
      await second.future;
      await engine.error(() => f.api.processMedia(ids[3]), 'media_busy');
      check(
        (jsonDecode(
                      f.store.rows['media_quotas']!['global']!['leasesJson']
                          as String,
                    )
                    as List)
                .length ==
            2,
        'Admission is only process-local',
      );
      gate.complete();
      await Future.wait([a, b]);
      f.files.beforeRead = null;
      await f.api.processMedia(ids[1]);
      await f.api.processMedia(ids[3]);
      check(
        f.store.rows['media_assets']!.values.every(
          (r) => r['status'] == 'ready',
        ),
        'Slots did not release',
      );
      check(
        f.store.rows['media_quotas']!['global']!['leasesJson'] == '[]',
        'Leases leaked',
      );
    },
  );
  await test(
    'image worker reauthorizes uploader intent after Storage IO and stale workers cannot mark ready',
    () async {
      final f = Fixture();
      await f.setup();
      await engine.join(f.api, 'bob', 4, role: 'builder');
      final id = await f.reserve('revoked-worker', png(), actor: 'bob');
      await f.upload(id, png(), actor: 'bob');
      await f.complete(id, actor: 'bob');
      f.files.beforeRead = (_) async {
        f.files.beforeRead = null;
        await grant(f, 'bob', role: 'viewer');
      };
      await engine.error(() => f.api.processMedia(id), 'forbidden');
      check(
        f.store.rows['media_assets']![id]!['status'] == 'failed',
        'Revoked worker published bytes',
      );
      await engine.error(() => f.read(id, actor: 'bob'), 'not_found');
    },
  );
  await test(
    'current private references gate viewer downloads and revocation during byte hydration denies response',
    () async {
      final f = Fixture();
      await f.setup();
      await engine.join(f.api, 'bob', 5, role: 'viewer');
      final id = await f.ready('visible', png());
      await engine.error(() => f.read(id, actor: 'bob'), 'not_found');
      await f.record(id);
      await f.read(id, actor: 'bob');
      f.files.beforeRead = (_) async {
        f.files.beforeRead = null;
        await grant(f, 'bob', role: null);
      };
      await engine.error(() => f.read(id, actor: 'bob'), 'not_found');
      check(f.files.values.length == 2, 'Revocation destroyed owner bytes');
    },
  );
  await test(
    'draft and historical image references retain bytes but do not grant runtime viewer access',
    () async {
      final f = Fixture();
      await f.setup();
      await engine.join(f.api, 'bob', 6, role: 'viewer');
      final id = await f.ready('draft-ref', png());
      await f.api.execute('alice', {
        'op': 'spec.saveDraft',
        'appId': 'app',
        'operationId': 'image-draft',
        'expectedRevision': 1,
        'expectedVersionId': f.version,
        'spec': banner(spec.photoJournalTemplate(), id),
      });
      await engine.error(() => f.read(id, actor: 'bob'), 'not_found');
      f.version = await engine.publish(
        f.api,
        'alice',
        2,
        f.version,
        'image-publish',
      );
      await f.read(id, actor: 'bob');
      await f.api.execute('alice', {
        'op': 'spec.saveDraft',
        'appId': 'app',
        'operationId': 'remove-cover',
        'expectedRevision': 2,
        'expectedVersionId': f.version,
        'spec': spec.photoJournalTemplate().toJson(),
      });
      f.version = await engine.publish(
        f.api,
        'alice',
        3,
        f.version,
        'cover-removed',
      );
      await engine.error(() => f.read(id, actor: 'bob'), 'not_found');
      f.now = f.now.add(const Duration(days: 2));
      await f.api.cleanupMedia();
      check(
        f.store.rows['media_assets']![id]!['status'] == 'ready',
        'Historical version lost retained asset',
      );
    },
  );
  await test(
    'image record writes and references commit atomically and never accept invented or cross-app IDs',
    () async {
      final f = Fixture();
      await f.setup();
      final id = await f.ready('record-image', png());
      final before = jsonEncode(f.store.rows);
      f.store.failBeforeCommit = true;
      try {
        await f.record(id);
        throw StateError('Expected rollback');
      } on RestException {}
      f.store.failBeforeCommit = false;
      check(
        jsonEncode(f.store.rows) == before,
        'Reference or audit escaped rollback',
      );
      final record = await f.record(id);
      check(
        f.store.rows['media_refs']!.values.any(
          (r) =>
              r['ownerKind'] == 'record' &&
              r['ownerId'] == record &&
              (jsonDecode(r['assetIdsJson'] as String) as List).contains(id),
        ),
        'Record has no retention',
      );
      await engine.error(
        () => f.record('made_up', operation: 'invented'),
        'not_found',
      );
      await f.api.execute('alice', {
        'op': 'spec.createApp',
        'workspaceId': 'ws',
        'id': 'other',
        'name': 'Other',
        'operationId': 'other',
      });
      await f.api.execute('alice', {
        'op': 'spec.saveDraft',
        'appId': 'other',
        'operationId': 'other-draft',
        'expectedRevision': 0,
        'expectedVersionId': null,
        'spec': spec.photoJournalTemplate().toJson(),
      });
      await engine.error(
        () => f.api.execute('alice', {
          'op': 'spec.saveDraft',
          'appId': 'other',
          'operationId': 'cross-ref',
          'expectedRevision': 1,
          'expectedVersionId': null,
          'spec': banner(spec.photoJournalTemplate(), id),
        }),
        'not_found',
      );
    },
  );
  await test(
    'generated definitions preserve only ready same-app references in their exact captured source',
    () async {
      final f = Fixture();
      await f.setup();
      final first = await f.ready('ai-one', png()),
          second = await f.ready('ai-two', png());
      final source = spec.AppSpec.parse(
        jsonEncode(banner(spec.photoJournalTemplate(), first)),
      );
      final candidate = spec.AppSpec.parse(
        jsonEncode(banner(spec.photoJournalTemplate(), second)),
      );
      final access = AppAccess(
        f.store.rows['apps']!['app']!,
        f.store.rows['workspaces']!['ws']!,
        'owner',
      );
      final tx = await f.store.beginTransaction();
      try {
        await f.api.validateGeneratedMedia('alice', access, source, source, tx);
        await engine.error(
          () => f.api.validateGeneratedMedia(
            'alice',
            access,
            source,
            candidate,
            tx,
          ),
          'invalid_media',
        );
        await engine.error(
          () => f.api.validateGeneratedMedia('alice', access, null, source, tx),
          'invalid_media',
        );
        await f.api.syncGeneratedMedia('alice', access, source, tx);
        await f.store.finishTransaction(tx, commit: true);
        check(
          f.store.rows['media_refs']!.values.single['ownerKind'] == 'draft',
          'AI reference not retained',
        );
      } catch (_) {
        await f.store.finishTransaction(tx, commit: false);
        rethrow;
      }
    },
  );
  await test(
    'cleanup respects all owner references restarts grace on removal and resumes partial deletion',
    () async {
      final f = Fixture();
      await f.setup();
      final id = await f.ready('cleanup', png());
      final actual = await f.record(id);
      f.now = f.now.add(const Duration(days: 2));
      await f.api.cleanupMedia();
      check(
        f.store.rows['media_assets']![id]!['status'] == 'ready',
        'Live referenced asset removed',
      );
      await f.api.execute(
        'alice',
        engine.action(
          'remove-image',
          f.version!,
          'editRecord',
          {
            'data': {'photo': null},
          },
          record: actual,
          revision: 1,
        ),
      );
      await f.api.cleanupMedia();
      check(
        f.store.rows['media_assets']![id]!['status'] == 'ready',
        'Grace started at upload rather than detach',
      );
      f.now = f.now.add(const Duration(days: 2));
      f.files.failRemove = true;
      await f.api.cleanupMedia();
      check(
        f.store.rows['media_assets']![id]!['status'] == 'deleting' &&
            (f.store.rows['media_assets']![id]!['storedBytes'] as int) > 0,
        'Failed cleanup released quota',
      );
      f.files.failRemove = false;
      await f.api.cleanupMedia();
      check(
        f.store.rows['media_assets']![id]!['status'] == 'deleting',
        'Deletion reservation released before quiet period',
      );
      f.now = f.now.add(
        MediaLimits.deletionQuietPeriod + const Duration(seconds: 1),
      );
      await f.api.cleanupMedia();
      check(
        f.files.values.isEmpty &&
            f.store.rows['media_assets']![id]!['status'] == 'deleted',
        'Cleanup could not resume',
      );
      check(
        f.store.rows['media_quotas']!.values.every(
          (q) => q['bytes'] == 0 && q['assets'] == 0,
        ),
        'Cleanup double-released reservation',
      );
      await f.api.cleanupMedia();
      check(
        f.store.rows['media_quotas']!.values.every(
          (q) => q['bytes'] == 0 && q['assets'] == 0,
        ),
        'Tombstone sweep released twice',
      );
    },
  );
  await test(
    'expired partial uploads cannot continue and are reclaimed with deterministic staging IDs',
    () async {
      final f = Fixture();
      await f.setup();
      final id = await f.reserve('expired', png());
      await f.upload(id, png());
      f.now = f.now.add(const Duration(minutes: 11));
      await engine.error(() => f.complete(id), 'media_expired');
      await f.api.cleanupMedia();
      check(f.files.values.isEmpty, 'Expired originals leaked');
      await engine.error(() => f.read(id), 'not_found');
      check(
        f.store.rows['media_assets']![id]!['status'] == 'deleting',
        'Expired deletion did not preserve draining reservation',
      );
      f.now = f.now.add(
        MediaLimits.deletionQuietPeriod + const Duration(seconds: 1),
      );
      await f.api.cleanupMedia();
      check(
        f.store.rows['media_assets']![id]!['status'] == 'deleted',
        'No durable cleanup tombstone',
      );
    },
  );
  await test(
    'concurrent reservations serialize the final per-app asset slot and failed admission is atomic',
    () async {
      final memory = engine.BarrierStore(), f = Fixture(memory: memory);
      await f.setup();
      await f.reserve('initial', png());
      final appQuota = f.store.rows['media_quotas']!.values.singleWhere(
        (q) => q[r'$id'] != 'global',
      );
      await f.store.update('media_quotas', appQuota[r'$id'] as String, {
        'assets': 499,
      });
      memory.barrier(2);
      Future<String> attempt(String operation) async {
        try {
          await f.reserve(operation, png());
          return 'ok';
        } on ServiceException catch (e) {
          return e.code;
        }
      }

      final results = await Future.wait([
        attempt('last-one'),
        attempt('last-two'),
      ]);
      check(
        results.where((r) => r == 'ok').length == 1 &&
            results.contains('transaction_conflict'),
        'Two final slots committed',
      );
      check(
        f.store.rows['media_assets']!.length == 2,
        'Losing reservation escaped transaction',
      );
      final before = jsonEncode(f.store.rows);
      await engine.error(() => f.reserve('over', png()), 'quota_exceeded');
      check(
        jsonEncode(f.store.rows) == before,
        'Quota failure partially changed state',
      );
    },
  );
  await test(
    'project reservation budget spans apps and is trusted configuration only',
    () async {
      final bytes = png();
      final reserved =
          bytes.length +
          MediaLimits.maxOriginalBytes +
          MediaLimits.maxThumbnailBytes;
      final f = Fixture(projectBytes: reserved);
      await f.setup();
      await f.reserve('project-first', bytes);
      await f.api.execute('alice', {
        'op': 'spec.createApp',
        'id': 'other',
        'workspaceId': 'ws',
        'name': 'Other',
        'operationId': 'new-other',
      });
      await f.api.execute('alice', {
        'op': 'spec.saveDraft',
        'appId': 'other',
        'operationId': 'draft-other',
        'expectedRevision': 0,
        'expectedVersionId': null,
        'spec': spec.photoJournalTemplate().toJson(),
      });
      final before = jsonEncode(f.store.rows);
      await engine.error(
        () => f.api.execute('alice', {
          ...f.begin('over-project', bytes, draft: 1),
          'appId': 'other',
        }),
        'quota_exceeded',
      );
      check(
        jsonEncode(f.store.rows) == before,
        'Cross-app project quota changed partial state',
      );
      await engine.error(
        () => f.api.execute('alice', {
          ...f.begin('raise-limit', bytes),
          'mediaProjectBytes': 2147483647,
        }),
        'invalid_request',
      );
    },
  );
  await test(
    'cleanup never underflows inconsistent counters and retains a recoverable deletion',
    () async {
      final f = Fixture();
      await f.setup();
      final id = await f.ready('counter-check', png());
      final used = f.store.rows['media_assets']![id]!['storedBytes'] as int;
      await f.store.update('media_quotas', 'global', {'bytes': 0});
      f.now = f.now.add(const Duration(days: 2));
      await f.api.cleanupMedia();
      check(
        f.store.rows['media_quotas']!['global']!['bytes'] == 0 &&
            f.store.rows['media_assets']![id]!['status'] == 'deleting' &&
            f.store.rows['media_assets']![id]!['storedBytes'] == used,
        'Corrupt counter produced a negative or lost tombstone',
      );
      f.now = f.now.add(
        MediaLimits.deletionQuietPeriod + const Duration(seconds: 1),
      );
      await f.api.cleanupMedia();
      check(
        f.store.rows['media_quotas']!.values.every(
              (row) =>
                  (row['bytes'] as int) >= 0 && (row['assets'] as int) >= 0,
            ) &&
            f.store.rows['media_assets']![id]!['status'] == 'deleting' &&
            f.store.rows['media_assets']![id]!['storedBytes'] == used,
        'Actual underflow debit did not roll back',
      );
      await f.store.update('media_quotas', 'global', {'bytes': used});
      await f.api.cleanupMedia();
      check(
        f.store.rows['media_quotas']!.values.every(
          (row) => row['bytes'] == 0 && row['assets'] == 0,
        ),
        'Recovery did not release exactly once',
      );
    },
  );
  await test(
    'multi-chunk downloads bind exact offsets MIME and whole/chunk digests',
    () async {
      final f = Fixture();
      await f.setup();
      final frame = image.Image(width: 330, height: 260, numChannels: 4);
      var seed = 21;
      for (final p in frame) {
        for (var channel = 0; channel < 4; channel++) {
          seed = (seed * 1664525 + 1013904223) & 0xffffffff;
          p[channel] = seed >> 24;
        }
      }
      final bytes = image.encodePng(frame);
      check(
        bytes.length > MediaLimits.chunkBytes,
        'Fixture does not cross chunk boundary',
      );
      final id = await f.ready('large-image', bytes),
          assembled = BytesBuilder();
      var offset = 0, parts = 0;
      String? whole;
      while (true) {
        final response = await f.read(id, offset: offset),
            chunk = base64Decode(response['dataBase64'] as String);
        check(
          response['offset'] == offset &&
              chunk.length <= MediaLimits.chunkBytes &&
              response['chunkSha256'] == digest(chunk) &&
              response['contentType'] == 'image/png',
          'Unbound or oversized chunk',
        );
        whole ??= response['sha256'] as String;
        check(whole == response['sha256'], 'Hash changed between chunks');
        assembled.add(chunk);
        parts++;
        if (response['nextOffset'] == null) {
          check(
            assembled.length == response['byteLength'],
            'Whole length mismatch',
          );
          break;
        }
        check(
          response['nextOffset'] == offset + chunk.length,
          'Cursor skipped or repeated bytes',
        );
        offset = response['nextOffset'] as int;
      }
      check(
        parts > 1 && digest(assembled.takeBytes()) == whole,
        'Whole image verification failed',
      );
      final file = f.files.values.keys.first;
      f.files.values[file]![0] ^= 1;
      try {
        await f.read(id);
        throw StateError('Expected integrity failure');
      } on ServiceException catch (e) {
        check(e.code == 'media_integrity', 'Wrong corruption failure');
      }
    },
  );
  await test(
    'approved workflow members upload own images while viewers and foreign pending uploads stay private',
    () async {
      final f = Fixture();
      await f.setup(workflow: true);
      await engine.join(f.api, 'bob', 10);
      await engine.join(f.api, 'carol', 11, role: 'viewer');
      final id = await f.reserve('member-image', png(), actor: 'bob');
      await engine.error(() => f.status(id, actor: 'carol'), 'not_found');
      await engine.error(
        () => f.upload(id, png(), actor: 'alice'),
        'not_found',
      );
      await f.upload(id, png(), actor: 'bob');
      await f.complete(id, actor: 'bob');
      await f.api.processMedia(id);
      await f.read(id, actor: 'bob');
      await engine.error(() => f.read(id, actor: 'carol'), 'not_found');
      await f.record(id, actor: 'bob');
      await f.read(id, actor: 'carol');
      final usage = await f.api.execute('alice', {
        'op': 'spec.media.usage',
        'appId': 'app',
      });
      check(
        (usage['reservedBytes'] as int) > 0 &&
            usage['assetCount'] == 1 &&
            (usage['pendingReleaseBytes'] as int) > 0,
        'Pending reservations claimed freed space',
      );
      await engine.error(
        () =>
            f.api.execute('carol', {'op': 'spec.media.usage', 'appId': 'app'}),
        'forbidden',
      );
    },
  );
  await test(
    'a worker that loses its lease after external IO cannot mark ready and recovery uses immutable outputs',
    () async {
      final f = Fixture();
      await f.setup();
      final id = await f.reserve('stale-lease', png());
      await f.upload(id, png());
      await f.complete(id);
      f.files.beforePut = (_) async {
        f.files.beforePut = null;
        f.now = f.now.add(const Duration(minutes: 3));
      };
      await engine.error(() => f.api.processMedia(id), 'media_state_conflict');
      check(
        f.store.rows['media_assets']![id]!['status'] == 'processing',
        'Stale generation marked ready',
      );
      await engine.error(() => f.read(id), 'not_found');
      await f.api.recoverMedia(limit: 1);
      check((await f.status(id))['status'] == 'ready', 'Lease recovery failed');
    },
  );
  await test(
    'cross-app actors cannot reserve the same remaining project slot concurrently',
    () async {
      final memory = engine.BarrierStore(), bytes = png();
      final reserved =
          bytes.length +
          MediaLimits.maxOriginalBytes +
          MediaLimits.maxThumbnailBytes;
      final f = Fixture(memory: memory, projectBytes: reserved * 2);
      await f.setup();
      await f.reserve('project-initial', bytes);
      await f.api.execute('bob', {
        'op': 'createWorkspace',
        'id': 'other-ws',
        'name': 'QA Bob',
      });
      await f.api.execute('bob', {
        'op': 'spec.createApp',
        'id': 'other',
        'workspaceId': 'other-ws',
        'name': 'Other',
        'operationId': 'bob-app',
      });
      await f.api.execute('bob', {
        'op': 'spec.saveDraft',
        'appId': 'other',
        'operationId': 'bob-draft',
        'expectedRevision': 0,
        'expectedVersionId': null,
        'spec': spec.photoJournalTemplate().toJson(),
      });
      memory.barrier(2);
      Future<String> attempt(String actor, Row command) async {
        try {
          await f.api.execute(actor, command);
          return 'ok';
        } on ServiceException catch (e) {
          return e.code;
        }
      }

      final result = await Future.wait([
        attempt('alice', f.begin('alice-last', bytes)),
        attempt('bob', {
          ...f.begin('bob-last', bytes, draft: 1),
          'appId': 'other',
        }),
      ]);
      check(
        result.where((s) => s == 'ok').length == 1 &&
            result.contains('transaction_conflict'),
        'Global last slot double-reserved',
      );
      check(
        f.store.rows['media_quotas']!['global']!['bytes'] == reserved * 2 &&
            f.store.rows['media_assets']!.length == 2,
        'Losing cross-app actor escaped rollback',
      );
    },
  );
  await test(
    'full forty-field image edits keep references projections and detach grace within Free transaction budget',
    () async {
      final memory = BudgetStore(), f = Fixture(memory: memory);
      await f.setup(publish: false);
      final seed = await f.ready('budget-seed', png(), draft: 1);
      // Ready metadata seeds isolate transaction-size accounting from image codec
      // tests. They do not claim eighty actual uploads or provider acceptance.
      for (var i = 0; i < 80; i++) {
        final row = Map<String, dynamic>.from(
          f.store.rows['media_assets']![seed]!,
        )..remove(r'$id');
        await f.store.create('media_assets', 'budget-$i', row);
      }
      final definition = spec.AppSpec.parse(
        jsonEncode({
          'formatVersion': 1,
          'name': 'Forty image fields',
          'theme': 'rose',
          'icon': 'spark',
          'requires': [
            'collections.v1',
            'fields.image.v1',
            'records.create.v1',
            'records.patch.v1',
            'views.details.v1',
          ],
          'policyPresetRequest': 'personalTracker.v1',
          'automationRequests': <Row>[],
          'collections': [
            {
              'id': 'images',
              'label': 'Images',
              'behaviors': <Row>[],
              'fields': [
                for (var i = 0; i < 40; i++)
                  {
                    'id': 'image$i',
                    'label': 'Image $i',
                    'type': 'image',
                    'required': false,
                  },
              ],
            },
          ],
          'actions': [
            {
              'id': 'addBook',
              'label': 'Add',
              'collectionId': 'images',
              'capability': 'records.create.v1',
            },
            {
              'id': 'editBook',
              'label': 'Edit',
              'collectionId': 'images',
              'capability': 'records.patch.v1',
            },
          ],
          'views': [
            {
              'id': 'details',
              'type': 'details',
              'collectionId': 'images',
              'label': 'Images',
            },
          ],
        }),
      ).toJson();
      await f.api.execute('alice', {
        'op': 'spec.saveDraft',
        'appId': 'app',
        'operationId': 'budget-draft',
        'expectedRevision': 1,
        'expectedVersionId': null,
        'spec': definition,
      });
      f.version = await engine.publish(
        f.api,
        'alice',
        2,
        null,
        'budget-publish',
      );
      final made = await f.api.execute(
        'alice',
        engine.action('budget-create', f.version!, 'addBook', {
          'data': {for (var i = 0; i < 40; i++) 'image$i': 'budget-$i'},
        }),
      );
      final id = (made['outcome'] as Map)['recordId'] as String;
      final result = await f.api.execute(
        'alice',
        engine.action(
          'budget-edit',
          f.version!,
          'editBook',
          {
            'data': {
              for (var i = 0; i < 40; i++) 'image$i': 'budget-${i + 40}',
            },
          },
          record: id,
          revision: 1,
        ),
      );
      check(
        (result['outcome'] as Map)['revision'] == 2 && memory.peak <= 100,
        'Maximum-shape write exceeded Free budget',
      );
      final refs = f.store.rows['media_refs']!.values.singleWhere(
        (r) => r['ownerKind'] == 'record',
      );
      check(
        (jsonDecode(refs['assetIdsJson'] as String) as List).length == 40,
        'Grouped reference set lost images',
      );
    },
  );
  await test(
    'storage REST broker uses key-only immutable private multipart binary IO and rejects grants',
    () async {
      await storageTransport();
    },
  );
  await test(
    'media provisioning retains Free one-bucket privacy lossless types and bounded reservation columns',
    () async {
      final schema =
          jsonDecode(await File('schema.json').readAsString()) as Row;
      final tables = (schema['tables'] as List).cast<Row>();
      for (final name in ['media_assets', 'media_refs', 'media_quotas']) {
        final table = tables.singleWhere((t) => t['tableId'] == name);
        check(
          table['rowSecurity'] == true &&
              (table['permissions'] as List).isEmpty,
          'Media table public',
        );
      }
      final bucket = schema['storage'] as Row;
      check(
        bucket['fileSecurity'] == true &&
            (bucket['permissions'] as List).isEmpty &&
            bucket['maximumFileSize'] == MediaLimits.maxOriginalBytes,
        'Unsafe bucket policy',
      );
      check(
        (schema['functionScopes'] as List).contains('files.read') &&
            (schema['functionScopes'] as List).contains('files.write'),
        'Missing ephemeral scopes',
      );
      check(
        MediaLimits.maxChunks == 20 && MediaLimits.chunkBytes == 262144,
        'Transport bounds changed',
      );
    },
  );
  return passed;
}

Future<void> storageTransport() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final binary = <String, Uint8List>{};
  var public = false, overflow = false, downloads = 0;
  final subscription = server.listen((request) async {
    try {
      check(
        request.headers.value('X-Appwrite-Key') == 'synthetic-ephemeral-key' &&
            request.headers.value('X-Appwrite-JWT') == null,
        'Credential mixing',
      );
      final parts = request.uri.pathSegments,
          id = parts.length > 5 ? parts[5] : null;
      if (request.method == 'POST') {
        final bytes = BytesBuilder();
        await for (final chunk in request) bytes.add(chunk);
        final data = bytes.takeBytes(), text = latin1.decode(data);
        final name = RegExp(
          'name="fileId"\\r\\n\\r\\n([^\\r]+)',
        ).firstMatch(text)!.group(1)!;
        if (binary.containsKey(name)) {
          request.response.statusCode = 409;
          await request.response.close();
          return;
        }
        check(
          !text.contains('read("any")') && !text.contains('permissions[]'),
          'Client grant escaped broker',
        );
        final header = text.indexOf('name="file";'),
            start = text.indexOf('\r\n\r\n', header) + 4;
        final end = text.lastIndexOf('\r\n--');
        binary[name] = Uint8List.fromList(data.sublist(start, end));
        request.response.statusCode = 201;
        request.response.write(
          jsonEncode({
            '\$id': name,
            'bucketId': 'private',
            '\$permissions': <String>[],
            'sizeOriginal': binary[name]!.length,
            'mimeType': 'application/octet-stream',
            'chunksTotal': 1,
            'chunksUploaded': 1,
          }),
        );
      } else if (id == null || !binary.containsKey(id)) {
        request.response.statusCode = 404;
      } else if (request.method == 'DELETE') {
        binary.remove(id);
        request.response.statusCode = 204;
      } else if (parts.last == 'download') {
        downloads++;
        request.response.add(overflow ? [...binary[id]!, 0] : binary[id]!);
      } else {
        request.response.write(
          jsonEncode({
            '\$id': id,
            'bucketId': 'private',
            '\$permissions': public ? ['read("any")'] : <String>[],
            'sizeOriginal': binary[id]!.length,
            'mimeType': 'application/octet-stream',
            'chunksTotal': 1,
            'chunksUploaded': 1,
          }),
        );
      }
      await request.response.close();
    } catch (error, stack) {
      request.response.statusCode = 500;
      await request.response.close();
      Zone.current.handleUncaughtError(error, stack);
    }
  });
  final files = AppwritePrivateFiles(
    Uri.parse('http://127.0.0.1:${server.port}/v1'),
    'synthetic-project',
    'private',
    'synthetic-ephemeral-key',
  );
  try {
    final bytes = Uint8List.fromList([0, 255, 128, 13, 10, 1, 0]);
    await engine.error(
      () => files.put('bad\r\nheader', bytes, 'application/octet-stream'),
      'invalid_id',
    );
    await files.put('file', bytes, 'application/octet-stream');
    await files.put('file', bytes, 'application/octet-stream');
    check(
      digest(await files.read('file', maximumBytes: 7)) == digest(bytes),
      'Binary transport changed bytes',
    );
    await engine.error(
      () => files.put(
        'file',
        Uint8List.fromList([1]),
        'application/octet-stream',
      ),
      'operation_conflict',
    );
    final before = downloads;
    public = true;
    await engine.error(
      () => files.read('file', maximumBytes: 7),
      'media_integrity',
    );
    check(downloads == before, 'Public file read before metadata rejected');
    public = false;
    overflow = true;
    await engine.error(
      () => files.read('file', maximumBytes: 7),
      'media_integrity',
    );
    overflow = false;
    await files.remove('file');
    await files.remove('file');
    check(binary.isEmpty, 'Missing delete not idempotent');
  } finally {
    files.close();
    await subscription.cancel();
    await server.close(force: true);
  }
}

Future<void> main() async {
  final count = await runMediaChecks();
  print(
    '$count media service groups passed (simulated store, synthetic images and local HTTP; live Cloud is separate).',
  );
}

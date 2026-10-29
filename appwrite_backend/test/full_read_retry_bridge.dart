// Test-only stdio bridge: actual PlatformService/WorkerEngine and loopback
// AppwriteRest/optimistic MemoryStore. No Cloud/auth endpoint or production path.
import 'dart:convert';
import 'dart:io';
import '../lib/service.dart';
import 'confirmed_abort_test.dart' as fixtures;

Future<Row> call(fixtures.LocalDatabase f, String actor, Row input) async {
  try {
    return {'status': 200, 'data': await f.service.execute(actor, input)};
  } on ServiceException catch (error) {
    return {
      'status': error.status,
      'data': {'error': error.code},
    };
  }
}

Future<void> main() async {
  final f = await fixtures.LocalDatabase.create();
  try {
    final api = f.service;
    await api.execute('alice', {
      'op': 'createWorkspace',
      'id': 'ws',
      'name': 'Synthetic read fixture',
    });
    await api.execute('alice', {
      'op': 'spec.createApp',
      'id': 'app-one',
      'workspaceId': 'ws',
      'name': 'Reading',
      'operationId': 'initial-create',
    });
    final catalog =
        (await api.execute('alice', {'op': 'spec.templates'}))['templates']
            as List;
    final spec = (catalog.cast<Map>().singleWhere(
      (x) => x['key'] == 'reading',
    ))['spec'];
    final saved =
        (await api.execute('alice', {
              'op': 'spec.saveDraft',
              'appId': 'app-one',
              'operationId': 'initial-save',
              'expectedRevision': 0,
              'expectedVersionId': null,
              'spec': spec,
            }))['app']
            as Map;
    final draft = saved['draft'] as Map;
    final review =
        (await api.execute('alice', {
              'op': 'spec.review',
              'appId': 'app-one',
              'expectedRevision': draft['revision'],
              'enabledRuleIds': [],
              'activateExistingRecordIds': [],
            }))['review']
            as Map;
    await api.execute('alice', {
      'op': 'spec.publish',
      'appId': 'app-one',
      'operationId': 'initial-publish',
      'expectedRevision': draft['revision'],
      'expectedVersionId': null,
      'candidateHash': review['candidateHash'],
      'reviewHash': review['reviewHash'],
      'enabledRuleIds': [],
      'activateExistingRecordIds': [],
    });
    final token = base64Url
        .encode(List.generate(32, (i) => i))
        .replaceAll('=', '');
    await api.execute('alice', {
      'op': 'createInvitation',
      'appId': 'app-one',
      'id': 'builder-invite',
      'operationId': 'builder-invite',
      'role': 'builder',
      'recipientId': 'bob',
      'token': token,
    });
    await api.execute('bob', {
      'op': 'acceptInvitation',
      'operationId': 'builder-accept',
      'token': token,
    });
    stdout.writeln(
      jsonEncode({
        'ready': true,
        'app': (await api.execute('alice', {
          'op': 'spec.getApp',
          'appId': 'app-one',
        }))['app'],
        'proof': 'actual_service_worker_local_rest_memory_only',
      }),
    );
    await for (final line
        in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
      try {
        if (line.length > 65536) throw const FormatException();
        final envelope = jsonDecode(line) as Row;
        final actor = envelope['actor'] as String;
        final input = Map<String, dynamic>.from(envelope['input'] as Map);
        final before = {
          'receipts': f.memory.rows['receipts']?.length ?? 0,
          'audit': f.memory.rows['audit']?.length ?? 0,
          'outbox': f.memory.rows['outbox']?.length ?? 0,
        };
        final failedBefore = f.states.values.where((s) => s == 'failed').length;
        Row result;
        if (envelope['raceRead'] == true) {
          if (input['op'] != 'spec.getApp') throw const FormatException();
          f.memory.arm();
          final pending = call(f, actor, input);
          await f.memory.paused!.future.timeout(const Duration(seconds: 5));
          try {
            await WorkerEngine(api).reminders();
          } finally {
            f.memory.resume!.complete();
          }
          result = await pending;
          if (envelope['revokeAfterRace'] == true) {
            final grant = f.memory.rows['grants']!.values.singleWhere(
              (g) => g['actorId'] == actor,
            );
            await api.execute('alice', {
              'op': 'setGrant',
              'appId': 'app-one',
              'actorId': actor,
              'role': null,
              'expectedRevision': grant['revision'],
              'operationId': 'revoke-after-read-race',
            });
          }
        } else {
          result = await call(f, actor, input);
        }
        stdout.writeln(
          jsonEncode({
            ...result,
            'localEvidence': {
              'businessBefore': before,
              'businessAfter': {
                'receipts': f.memory.rows['receipts']?.length ?? 0,
                'audit': f.memory.rows['audit']?.length ?? 0,
                'outbox': f.memory.rows['outbox']?.length ?? 0,
              },
              'newFailedTransactions':
                  f.states.values.where((s) => s == 'failed').length -
                  failedBefore,
            },
          }),
        );
      } catch (_) {
        stdout.writeln(
          jsonEncode({
            'status': 500,
            'data': {'error': 'offline_bridge_failure'},
          }),
        );
      }
    }
  } finally {
    await f.close();
  }
}

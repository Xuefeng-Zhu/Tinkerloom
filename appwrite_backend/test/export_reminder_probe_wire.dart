import 'dart:convert';
import 'dart:io';
import 'package:appnest_spec/appnest_spec.dart' as spec;
import '../lib/service.dart';
import 'workers_test.dart' as workers;
import 'spec_engine_check.dart' as base;

Future<Row> state(workers.Fixture f, String v, String id) => f.service.execute(
  'alice',
  {'op': 'spec.reminderState', 'appId': 'app', 'versionId': v, 'recordId': id},
);
Future<Row> runs(workers.Fixture f) =>
    f.service.execute('alice', {'op': 'spec.runs', 'appId': 'app'});
Future<void> main(List<String> args) async {
  final f = await workers.fixture(),
      definition = spec.starterTemplates()['reminders']!;
  await f.save(definition, 0, null, 'd1');
  final v1 = await f.publish(1, null, 'p1');
  final old = await f.task(
        v1,
        'old',
        date: f.clock.value.add(const Duration(seconds: 180)).toIso8601String(),
      ),
      unset = await f.task(v1, 'unset');
  final disabled = await state(f, v1, old['id'] as String);
  await f.save(definition, 1, v1, 'd2');
  final v2 = await f.publish(
    2,
    v1,
    'p2',
    enabled: ['taskReminder'],
    records: [unset['id'] as String],
  );
  final unenrolled = await state(f, v2, old['id'] as String),
      empty = await state(f, v2, unset['id'] as String);
  final deliver = await f.task(
    v2,
    'deliver',
    date: f.clock.value.add(const Duration(seconds: 180)).toIso8601String(),
  );
  final clear = await f.task(
    v2,
    'clear',
    date: f.clock.value.add(const Duration(seconds: 180)).toIso8601String(),
  );
  final condition = await f.task(
    v2,
    'condition',
    date: f.clock.value.add(const Duration(seconds: 180)).toIso8601String(),
  );
  await f.worker.reminders();
  final pending = await state(f, v2, deliver['id'] as String),
      pendingRuns = await runs(f);
  await base.run(
    f.service,
    'alice',
    base.action(
      'clear-date',
      v2,
      'editTask',
      {
        'data': {'reminderAt': null},
      },
      record: clear['id'] as String,
      revision: 1,
    ),
  );
  await base.run(
    f.service,
    'alice',
    base.action(
      'done',
      v2,
      'moveTask',
      {'value': 'Done'},
      record: condition['id'] as String,
      revision: 1,
    ),
  );
  f.clock.advance();
  await f.worker.reminders();
  await f.worker.reminders();
  final delivered = await state(f, v2, deliver['id'] as String),
      suppressed = await state(f, v2, condition['id'] as String),
      ownerRuns = await runs(f);
  final ownerInbox = await f.service.execute('alice', {'op': 'spec.inbox'});
  if ((ownerInbox['items'] as List).length != 1)
    throw StateError('Duplicate owner delivery');
  final item = (ownerInbox['items'] as List).single as Row;
  final read = {
    'op': 'spec.readNotification',
    'appId': 'app',
    'runId': item['runId'],
    'notificationId': item['id'],
    'operationId': 'read',
  };
  final ack = await f.service.execute('alice', read);
  if (jsonEncode(await f.service.execute('alice', read)) != jsonEncode(ack))
    throw StateError('Read replay changed');
  final member = await workers.fixture();
  await member.save(spec.starterTemplates()['chores']!, 0, null, 'd');
  final mv = await member.publish(1, null, 'p', enabled: ['dueReminder']);
  await base.join(member.service, 'bob', 9);
  Future<String> chore(String op) async {
    final created = await base.run(
      member.service,
      'bob',
      base.action(op, mv, 'addChore', {
        'data': {
          'title': 'Synthetic self opt-in',
          'status': 'Open',
          'dueAt': member.clock.value
              .add(const Duration(hours: 1, seconds: 180))
              .toIso8601String(),
        },
      }),
    );
    final id = created['recordId'] as String;
    await base.run(
      member.service,
      'bob',
      base.action(
        '$op-assign',
        mv,
        'assignChore',
        {'value': 'bob'},
        record: id,
        revision: 1,
      ),
    );
    return id;
  }

  await chore('member-record');
  await member.worker.reminders();
  member.clock.advance();
  await member.worker.reminders();
  final memberInbox = await member.service.execute('bob', {'op': 'spec.inbox'}),
      ownerCannotSeeMember = await member.service.execute('alice', {
        'op': 'spec.inbox',
      });
  if ((memberInbox['items'] as List).length != 1 ||
      (ownerCannotSeeMember['items'] as List).isNotEmpty)
    throw StateError('Recipient isolation failed');
  final other = (memberInbox['items'] as List).single as Row;
  Row denied;
  try {
    await member.service.execute('alice', {
      'op': 'spec.readNotification',
      'appId': 'app',
      'runId': other['runId'],
      'notificationId': other['id'],
      'operationId': 'deny',
    });
    throw StateError('Cross recipient accepted');
  } on ServiceException catch (error) {
    denied = {'error': error.code, 'status': error.status};
  }
  final revoked = await chore('revoked-record');
  await member.worker.reminders();
  await member.service.execute('alice', {
    'op': 'setGrant',
    'appId': 'app',
    'actorId': 'bob',
    'role': null,
    'expectedRevision': 1,
    'operationId': 'revoke',
  });
  member.clock.advance();
  await member.worker.reminders();
  final revokedRuns = await runs(member),
      rr =
          (revokedRuns['runs'] as List)
                  .where((run) => (run as Row)['recordId'] == revoked)
                  .single
              as Row;
  if (rr['recipientCount'] != 0 || rr['status'] != 'succeeded')
    throw StateError('Revoked recipient not skipped');
  final output = {
    'proof':
        'Actual PlatformService and trusted WorkerEngine with synthetic MemoryStore/clock; no Cloud, HTTP, provider, credentials or real recipients',
    'templates': {
      'reminders': definition.toJson(),
      'chores': spec.starterTemplates()['chores']!.toJson(),
    },
    'ownerVersionId': v2,
    'memberVersionId': mv,
    'states': {
      'disabled': disabled,
      'unenrolled': unenrolled,
      'unset': empty,
      'pending': pending,
      'delivered': delivered,
      'suppressed': suppressed,
    },
    'pendingRuns': pendingRuns,
    'ownerRuns': ownerRuns,
    'ownerInbox': ownerInbox,
    'readAcknowledgement': ack,
    'memberInbox': memberInbox,
    'ownerCannotSeeMemberInbox': ownerCannotSeeMember,
    'crossRecipientReadDenied': denied,
    'revokedRecipientRun': rr,
    'afterRevocationInbox': await member.service.execute('bob', {
      'op': 'spec.inbox',
    }),
  };
  if (args.length != 1) throw ArgumentError('One output fixture path required');
  File(args.single).writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(output)}\n',
  );
  print(
    jsonEncode({
      'status': 'passed',
      'states': 6,
      'duplicateWorkerDrains': 2,
      'ownerNotifications': 1,
      'memberNotifications': 1,
      'revokedRecipientCount': 0,
      'fixture': args.single,
    }),
  );
}

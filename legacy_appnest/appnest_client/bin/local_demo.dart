import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appnest_client/appnest_client.dart';
import 'package:appnest_spec/appnest_spec.dart';

class DemoKey implements ClientAuthKeyProvider {
  final String token;
  DemoKey(this.token);
  @override
  Future<String?> get authHeaderValue async =>
      wrapAsBearerAuthHeaderValue(token);
}

Future<Client> login(String name) async {
  final client = Client('http://localhost:8180/');
  final auth = await client.emailIdp.login(
    email: '$name@appnest.local',
    password: 'AppNest-local-demo-2026!',
  );
  client.authKeyProvider = DemoKey(auth.token);
  if (!(await client.builder.platform()).development) {
    throw StateError('Development server required.');
  }
  return client;
}

Future<int> publish(Client owner, BuilderSnapshot draft) =>
    owner.builder.publish(
      PublishRequest(
        draftId: draft.draftId,
        candidateHash: draft.candidateHash,
        expectedCurrentVersionId: draft.baseVersionId,
        enabledRuleIds: ['shiftReminder'],
        activateExistingRecordIds: [],
        reviewHash: hashJson({
          'candidateHash': draft.candidateHash,
          'enabledRuleIds': ['shiftReminder'],
          'activateExistingRecordIds': [],
        }),
        idempotencyKey: 'demo-publish-${draft.draftId}-${draft.candidateHash}',
      ),
    );

Future<void> main(List<String> args) async {
  if (!args.contains('--accelerated-template-demo')) {
    throw ArgumentError(
      'Pass --accelerated-template-demo. Creates a fresh local synthetic app; does not delete data.',
    );
  }
  var owner = await login('morgan');
  final platform = await owner.builder.platform();
  stdout.writeln(
    'Explicit TEMPLATE demo (not live AI). Provider configured: ${platform.aiAvailable}. Reminder due in about 35 seconds.',
  );
  final workspace = (await owner.apps.workspaces()).firstWhere(
    (w) => w.name == 'AppNest demo',
  );
  var draft = await owner.builder.begin(workspace.id, 'volunteer', null);
  draft = await owner.builder.patch(
    draft.draftId,
    draft.mutation,
    jsonEncode({
      'type': 'RenameLabel',
      'targetId': 'app',
      'label':
          'Neighborhood helpers ${DateTime.now().toUtc().toIso8601String().substring(11, 19)}',
    }),
  );
  var version = await publish(owner, draft);
  final app = draft.appId;
  final record = await owner.runtime.execute(
    ActionRequest(
      appId: app,
      actionId: 'addShift',
      expectedDefinitionVersionId: version,
      input: {
        'data': {
          'title': 'Food pantry · accelerated reminder demo',
          'startsAt': DateTime.now()
              .toUtc()
              .add(const Duration(hours: 1, seconds: 35))
              .toIso8601String(),
          'notes': 'Synthetic demo. Reminder offset is one hour; intended delivery is in 35 seconds.',
        },
        'capacity': 1,
      },
      idempotencyKey: 'create',
    ),
  );
  final alex = await login('alex'), sam = await login('sam');
  for (final participant in [alex, sam]) {
    await participant.apps.acceptInvitation(
      await owner.apps.invite(app, 'member', null),
    );
  }
  final attempts = await Future.wait(
    [alex, sam].map((participant) async {
      try {
        await participant.runtime.execute(
          ActionRequest(
            appId: app,
            actionId: 'join',
            targetRecordId: record.recordId,
            expectedDefinitionVersionId: version,
            input: {},
            idempotencyKey: 'final-place',
          ),
        );
        return true;
      } on NestError catch (e) {
        if (e.category != 'exhaustedCapacity') rethrow;
        return false;
      }
    }),
  );
  if (attempts.where((ok) => ok).length != 1) {
    throw StateError('Final-place invariant failed.');
  }
  stdout.writeln(
    'PASS: two independently authenticated participants raced; exactly one accepted.',
  );
  draft = await owner.builder.begin(workspace.id, 'volunteer', app);
  draft = await owner.builder.patch(
    draft.draftId,
    draft.mutation,
    jsonEncode({
      'type': 'AddField',
      'collectionId': 'shifts',
      'field': {'label': 'Meeting point', 'type': 'text', 'required': false},
    }),
  );
  version = await publish(owner, draft);
  if ((await owner.runtime.get(app, record.recordId)).allocated != 1) {
    throw StateError('Safe edit lost allocation.');
  }
  stdout.writeln(
    'PASS: explicit optional-field publication preserved the sign-up. AI editing remains a separate credential-gated check.',
  );
  owner.close();
  alex.close();
  sam.close();
  stdout.writeln(
    'All demo clients closed; Serverpod Future Calls must perform the effect.',
  );
  await Future<void>.delayed(const Duration(seconds: 48));
  final winner = await login(attempts.first ? 'alex' : 'sam');
  owner = await login('morgan');
  final notifications = (await winner.runtime.inbox())
      .where((n) => n.appId == app)
      .toList();
  final runs = await owner.builder.runs(app);
  if (notifications.length != 1 ||
      runs.where((r) => r.status == 'succeeded').length != 1) {
    throw StateError(
      'Expected one persisted notification and one successful run. Actual notifications=${notifications.length}, statuses=${runs.map((r) => r.status)}',
    );
  }
  stdout.writeln(
    'PASS: clients reopened to one durable notification and one successful scheduled run. App $app, version $version, record ${record.recordId}.',
  );
  winner.close();
  owner.close();
}

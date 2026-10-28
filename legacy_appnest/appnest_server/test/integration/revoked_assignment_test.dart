import 'package:appnest_server/src/generated/protocol.dart';
import 'package:appnest_server/src/modules/collaboration/sharing.dart';
import 'package:appnest_server/src/modules/definitions/apps.dart';
import 'package:appnest_server/src/modules/runtime/access.dart';
import 'package:appnest_server/src/modules/runtime/commands.dart';
import 'package:appnest_server/src/modules/runtime/integrity.dart';
import 'package:appnest_server/src/modules/runtime/queries.dart';
import 'package:serverpod/serverpod.dart';
import 'package:test/test.dart';

import 'test_tools/serverpod_test_tools.dart';

void main() {
  withServerpod('Revoked assignments remain historical references', (
    sessions,
    endpoints,
  ) {
    Session user(String id) => sessions
        .copyWith(
          authentication: AuthenticationOverride.authenticationInfo(id, {}),
        )
        .build();
    late Session owner, assignee, member;
    late int appId, version, recordId;
    var sequence = 0;

    setUpAll(() async => Integrity.ensure(sessions.build()));
    setUp(() async {
      final prefix = randomToken();
      owner = user('assignment-owner-$prefix');
      assignee = user('assignee-$prefix');
      member = user('other-member-$prefix');
      final workspace = await Apps.createWorkspace(owner, 'Assignments');
      appId = await Apps.instantiate(owner, workspace, 'chores');
      version = (await Apps.manifest(owner, appId)).versionId!;
      for (final account in [assignee, member]) {
        await Sharing.accept(
          account,
          await Sharing.invite(owner, appId, 'member', actor(account)),
        );
      }
      recordId = (await Commands.execute(
        owner,
        ActionRequest(
          appId: appId,
          actionId: 'addChore',
          expectedDefinitionVersionId: version,
          input: {
            'data': {
              'title': 'Garden work',
              'status': 'Open',
              'assignee': actor(assignee),
            },
          },
          idempotencyKey: 'create',
        ),
      )).recordId;
      await Sharing.setGrant(owner, appId, actor(assignee), null);
    });

    Future<void> command(
      Session account,
      String action,
      Map<String, dynamic> input,
    ) async {
      final row = await Queries.get(account, appId, recordId);
      await Commands.execute(
        account,
        ActionRequest(
          appId: appId,
          actionId: action,
          targetRecordId: recordId,
          expectedDefinitionVersionId: version,
          expectedRecordRevision: row.revision,
          input: input,
          idempotencyKey: 'command-${sequence++}',
        ),
      );
    }

    test(
      'owner and remaining members can edit notes and move workflow',
      () async {
        await command(owner, 'editChore', {
          'data': {'notes': 'Owner note'},
        });
        await command(member, 'editChore', {
          'data': {'notes': 'Member note'},
        });
        await command(owner, 'moveChore', {'value': 'Doing'});
        final row = await Queries.get(owner, appId, recordId);
        expect(row.data['notes'], 'Member note');
        expect(row.data['status'], 'Doing');
        expect(row.data['assignee'], actor(assignee));
        expect(row.revision, 4);
        await expectLater(
          Queries.get(assignee, appId, recordId),
          throwsA(
            isA<NestError>().having((e) => e.category, 'category', 'notFound'),
          ),
        );
        expect(
          (await Sharing.members(owner, appId)).map((m) => m.actorId),
          isNot(contains(actor(assignee))),
        );
      },
    );

    test(
      'inactive references cannot be assigned again or used in creates',
      () async {
        await expectLater(
          command(owner, 'assignChore', {'value': actor(assignee)}),
          throwsA(
            isA<NestError>().having(
              (e) => e.category,
              'category',
              'invalidInput',
            ),
          ),
        );
        await expectLater(
          Commands.execute(
            owner,
            ActionRequest(
              appId: appId,
              actionId: 'addChore',
              expectedDefinitionVersionId: version,
              input: {
                'data': {
                  'title': 'Another chore',
                  'status': 'Open',
                  'assignee': actor(assignee),
                },
              },
              idempotencyKey: 'inactive-create',
            ),
          ),
          throwsA(
            isA<NestError>().having(
              (e) => e.category,
              'category',
              'invalidInput',
            ),
          ),
        );
        await command(owner, 'assignChore', {'value': actor(member)});
        await expectLater(
          command(owner, 'assignChore', {'value': actor(assignee)}),
          throwsA(
            isA<NestError>().having(
              (e) => e.category,
              'category',
              'invalidInput',
            ),
          ),
        );
        await command(member, 'assignChore', {'value': null});
        expect(
          (await Queries.get(owner, appId, recordId)).data['assignee'],
          isNull,
        );
        expect(
          await ActionReceipt.db.count(
            owner,
            where: (t) => t.appId.equals(appId),
          ),
          3,
        );
      },
    );
  }, rollbackDatabase: RollbackDatabase.disabled);
}

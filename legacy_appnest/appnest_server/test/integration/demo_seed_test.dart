import 'package:appnest_server/src/generated/protocol.dart';
import 'package:appnest_server/src/modules/definitions/apps.dart';
import 'package:appnest_server/src/modules/definitions/demo_seed.dart';
import 'package:appnest_server/src/modules/runtime/access.dart';
import 'package:appnest_server/src/modules/runtime/commands.dart';
import 'package:appnest_server/src/modules/runtime/integrity.dart';
import 'package:appnest_server/src/modules/runtime/queries.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:test/test.dart';

import 'test_tools/serverpod_test_tools.dart';

void main() {
  withServerpod('Development demo templates', (sessions, endpoints) {
    test(
      'full seed supports collection-free utilities and stays non-destructive',
      () async {
        final ownerId = 'seed-owner-${randomToken()}';
        final owner = sessions
            .copyWith(
              authentication: AuthenticationOverride.authenticationInfo(
                ownerId,
                {},
              ),
            )
            .build();
        await Integrity.ensure(owner);
        final workspace = await Apps.createWorkspace(owner, 'Seed regression');
        final members = [
          'seed-alex-${randomToken()}',
          'seed-sam-${randomToken()}',
        ];
        await DemoSeed.seedTemplates(owner, workspace, members);

        final apps = await Apps.list(owner, workspace);
        expect(apps, hasLength(starterTemplates().length));
        for (final entry in starterTemplates().entries) {
          final app = apps.singleWhere((app) => app.name == entry.value.name);
          final spec = AppSpec.parse(app.specJson!);
          expect(app.recordCount, 3 * spec.collections.length);
          for (final collection in spec.collections) {
            final records = await Queries.query(
              owner,
              app.appId,
              collection.id,
              '{}',
            );
            expect(records.total, 3);
            for (final record in records.records) {
              for (final image in collection.fields.where(
                (field) => field.type == FieldType.image,
              )) {
                expect((record.data as Map).containsKey(image.id), isFalse);
              }
            }
          }
          if (spec.policyPresetRequest != 'personalTracker.v1') {
            final grants = await MiniAppGrant.db.find(
              owner,
              where: (t) => t.appId.equals(app.appId),
            );
            expect(
              grants.map((grant) => grant.actorId).toSet(),
              members.toSet(),
            );
          }
          expect(
            await Template.db.findFirstRow(
              owner,
              where: (t) => t.key.equals(entry.key),
            ),
            isNotNull,
          );
        }

        final notes = apps.singleWhere(
          (app) => app.name == starterTemplates()['notes']!.name,
        );
        final notesSpec = AppSpec.parse(notes.specJson!);
        final collection = notesSpec.collections.single;
        final first = (await Queries.query(
          owner,
          notes.appId,
          collection.id,
          '{}',
        )).records.first;
        await Commands.execute(
          owner,
          ActionRequest(
            appId: notes.appId,
            actionId: notesSpec.actions
                .singleWhere(
                  (action) => action.capability == 'records.patch.v1',
                )
                .id,
            targetRecordId: first.id,
            expectedDefinitionVersionId: notes.versionId!,
            expectedRecordRevision: first.revision,
            input: {
              'data': {'title': 'Keep my edited example'},
            },
            idempotencyKey: 'seed-test-edit',
          ),
        );
        await Commands.execute(
          owner,
          ActionRequest(
            appId: notes.appId,
            actionId: notesSpec.actions
                .singleWhere(
                  (action) => action.capability == 'records.create.v1',
                )
                .id,
            expectedDefinitionVersionId: notes.versionId!,
            input: {
              'data': {
                'title': 'Keep my extra record',
                'body': 'A personal addition',
              },
            },
            idempotencyKey: 'seed-test-extra',
          ),
        );
        final originalClock = clock;
        clock = () => originalClock().add(const Duration(days: 7));
        try {
          await DemoSeed.seedTemplates(owner, workspace, members);
        } finally {
          clock = originalClock;
        }
        expect(await Apps.list(owner, workspace), hasLength(apps.length));
        final records = await Queries.query(
          owner,
          notes.appId,
          collection.id,
          '{}',
        );
        expect(records.total, 4);
        expect(
          (await Queries.get(owner, notes.appId, first.id)).data as Map,
          containsPair('title', 'Keep my edited example'),
        );
        expect(
          records.records.map((record) => (record.data as Map)['title']),
          contains('Keep my extra record'),
        );
      },
    );

    test('repeat seed skips archived and customized name collisions without receipts', () async {
      final owner = sessions
          .copyWith(
            authentication: AuthenticationOverride.authenticationInfo(
              'seed-preserve-${randomToken()}',
              {},
            ),
          )
          .build();
      await Integrity.ensure(owner);
      final workspace = await Apps.createWorkspace(
        owner,
        'Preserve my demo apps',
      );
      final archived = await Apps.instantiate(owner, workspace, 'notes');
      await Apps.archive(owner, archived);
      final archivedBefore = await Apps.manifest(owner, archived);
      final archivedCollection = AppSpec.parse(
        archivedBefore.specJson!,
      ).collections.single.id;
      expect(
        (await Queries.query(owner, archived, archivedCollection, '{}')).total,
        0,
      );

      final customized = starterTemplates()['reading']!.patch({
        'type': 'RenameLabel',
        'targetId': 'app',
        'label': starterTemplates()['chores']!.name,
      }, () => throw StateError('Rename allocates no IDs'));
      final customApp = await Apps.create(owner, workspace, customized);
      final customBefore = await Apps.manifest(owner, customApp);
      final collection = customized.collections.single;
      final data = syntheticRecords(collection).first;
      for (final behavior in collection.behaviors.where(
        (b) => b.type == 'workflow.v1',
      )) {
        data[behavior.fieldId!] = collection
            .field(behavior.fieldId!)
            .choices
            .first;
      }
      final created = await Commands.execute(
        owner,
        ActionRequest(
          appId: customApp,
          actionId: customized.actions
              .singleWhere((a) => a.capability == 'records.create.v1')
              .id,
          expectedDefinitionVersionId: customBefore.versionId!,
          input: {'data': data},
          idempotencyKey: 'my-saved-custom-record',
        ),
      );
      final recordBefore = await Queries.get(
        owner,
        customApp,
        created.recordId,
      );
      final members = ['seed-invite-${randomToken()}'];
      await DemoSeed.seedTemplates(owner, workspace, members);
      await DemoSeed.seedTemplates(owner, workspace, members);

      final archivedAfter = await Apps.manifest(owner, archived);
      expect(archivedAfter.archived, isTrue);
      expect(archivedAfter.versionId, archivedBefore.versionId);
      expect(archivedAfter.specJson, archivedBefore.specJson);
      expect(
        (await Queries.query(owner, archived, archivedCollection, '{}')).total,
        0,
      );
      final customAfter = await Apps.manifest(owner, customApp);
      expect(customAfter.versionId, customBefore.versionId);
      expect(customAfter.specJson, customized.canonical);
      expect(
        (await Queries.query(owner, customApp, collection.id, '{}')).total,
        1,
      );
      final recordAfter = await Queries.get(owner, customApp, created.recordId);
      expect(recordAfter.revision, recordBefore.revision);
      expect(recordAfter.data, recordBefore.data);
      for (final appId in [archived, customApp]) {
        expect(
          await MiniAppGrant.db.count(
            owner,
            where: (t) => t.appId.equals(appId),
          ),
          0,
        );
        expect(
          await ActionReceipt.db.count(
            owner,
            where: (t) =>
                t.appId.equals(appId) & t.idempotencyKey.like('seed-%'),
          ),
          0,
        );
      }
      expect(
        (await Apps.list(
          owner,
          workspace,
        )).where((app) => app.name == customBefore.name),
        hasLength(1),
      );
    });

    test('public account seeding remains development-only', () async {
      final session = sessions.build();
      await expectLater(DemoSeed.run(session), throwsStateError);
      expect(session.authenticated, isNull);
    });
  }, rollbackDatabase: RollbackDatabase.disabled);
}

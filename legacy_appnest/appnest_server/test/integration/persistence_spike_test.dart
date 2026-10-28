import 'package:appnest_server/src/generated/protocol.dart';
import 'package:appnest_server/src/modules/definitions/apps.dart';
import 'package:serverpod/serverpod.dart';
import 'package:test/test.dart';

import 'test_tools/serverpod_test_tools.dart';

void main() {
  withServerpod('PostgreSQL serialization and transaction spike', (
    sessions,
    endpoints,
  ) {
    test('dynamic JSONB round trips all external JSON values', () async {
      final s = sessions
          .copyWith(
            authentication: AuthenticationOverride.authenticationInfo(
              'serialization-spike',
              {},
            ),
          )
          .build();
      final workspaceId = await Apps.createWorkspace(s, 'Serialization spike');
      final appId = await Apps.instantiate(s, workspaceId, 'reading');
      final versionId = (await Apps.manifest(s, appId)).versionId!;
      final data = {
        'text': 'hello',
        'integer': 3,
        'number': 1.5,
        'flag': true,
        'optional': null,
        'nested': {
          'items': ['x', 2],
        },
      };
      final row = await EntityRecord.db.insertRow(
        s,
        EntityRecord(
          appId: appId,
          workspaceId: workspaceId,
          collectionId: 'spike',
          data: data,
          creatorId: 'spike',
          revision: 1,
          writtenUnderVersionId: versionId,
          createdAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
        ),
      );
      final loaded = await EntityRecord.db.findById(s, row.id!);
      expect(loaded!.data, data);
      final raw = await s.db.unsafeQuery(
        'SELECT data FROM nest_record WHERE id = @id',
        parameters: QueryParameters.named({'id': row.id}),
      );
      expect(raw, isNotEmpty); // Stored representation is deliberately opaque.
    });
    test('failed transaction rolls back business rows', () async {
      final s = sessions.build();
      await expectLater(
        s.db.transaction((tx) async {
          await Workspace.db.insertRow(
            s,
            Workspace(
              name: 'rollback',
              ownerId: 'spike',
              createdAt: DateTime.now().toUtc(),
            ),
            transaction: tx,
          );
          throw StateError('fault after insert');
        }),
        throwsStateError,
      );
      expect(
        await Workspace.db.count(s, where: (t) => t.name.equals('rollback')),
        0,
      );
    });
  }, rollbackDatabase: RollbackDatabase.disabled);
}

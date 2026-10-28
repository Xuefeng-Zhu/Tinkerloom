import 'dart:convert';

import 'package:appnest_server/src/modules/builder/builder.dart';
import 'package:appnest_server/src/modules/definitions/apps.dart';
import 'package:appnest_server/src/modules/runtime/access.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:test/test.dart';

import 'test_tools/serverpod_test_tools.dart';

void main() {
  withServerpod('Visual definition edits', (sessions, endpoints) {
    test(
      'authenticated field rename persists and rejects stale/foreign edits',
      () async {
        final owner = sessions
            .copyWith(
              authentication: AuthenticationOverride.authenticationInfo(
                'visual-${randomToken()}',
                {},
              ),
            )
            .build();
        final stranger = sessions
            .copyWith(
              authentication: AuthenticationOverride.authenticationInfo(
                'other-${randomToken()}',
                {},
              ),
            )
            .build();
        final workspace = await Apps.createWorkspace(owner, 'Visual edit test');
        final before = await Builder.begin(owner, workspace, 'reading', null);
        final patch = jsonEncode({
          'type': 'RenameField',
          'collectionId': 'books',
          'fieldId': 'title',
          'label': 'Book title',
        });
        final after = await Builder.patch(
          owner,
          before.draftId,
          before.mutation,
          patch,
        );
        expect(after.mutation, before.mutation + 1);
        final read = await Builder.get(owner, before.draftId);
        expect(
          AppSpec.parse(read.candidateJson)
              .collection('books')
              .field('title')
              .label,
          'Book title',
        );
        expect(read.candidateHash, after.candidateHash);
        await expectLater(
          Builder.patch(owner, before.draftId, before.mutation, patch),
          throwsA(anything),
        );
        await expectLater(
          Builder.patch(stranger, after.draftId, after.mutation, patch),
          throwsA(anything),
        );
        expect(
          (await Builder.get(owner, before.draftId)).mutation,
          after.mutation,
        );
      },
    );
  });
}

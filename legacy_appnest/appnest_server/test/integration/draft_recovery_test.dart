import 'dart:convert';

import 'package:appnest_server/src/generated/protocol.dart';
import 'package:appnest_server/src/modules/builder/builder.dart';
import 'package:appnest_server/src/modules/definitions/apps.dart';
import 'package:appnest_server/src/modules/runtime/access.dart';
import 'package:appnest_server/src/modules/runtime/integrity.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:serverpod/serverpod.dart';
import 'package:test/test.dart';

import 'test_tools/serverpod_test_tools.dart';

void main() {
  withServerpod('Durable private draft recovery', (sessions, endpoints) {
    Session user(String name) => sessions
        .copyWith(
          authentication: AuthenticationOverride.authenticationInfo(name, {}),
        )
        .build();
    late Session owner;
    late int workspace;
    late BuilderSnapshot initial;

    setUpAll(() => Integrity.ensure(sessions.build()));
    setUp(() async {
      owner = user('draft-owner-${randomToken()}');
      workspace = await Apps.createWorkspace(owner, 'Recovery workspace');
      initial = await Builder.begin(owner, workspace, 'notes', null);
    });

    Future<Session> collaborator(String role) async {
      final member = user('draft-$role-${randomToken()}');
      await WorkspaceMember.db.insertRow(
        owner,
        WorkspaceMember(
          workspaceId: workspace,
          actorId: actor(member),
          role: 'member',
        ),
      );
      await MiniAppGrant.db.insertRow(
        owner,
        MiniAppGrant(
          workspaceId: workspace,
          appId: initial.appId,
          actorId: actor(member),
          role: role,
        ),
      );
      return member;
    }

    Matcher unavailable = throwsA(
      isA<NestError>().having((e) => e.category, 'category', 'notFound'),
    );

    test(
      'fresh authenticated session resumes latest persisted candidate',
      () async {
        final changed = await Builder.patch(
          owner,
          initial.draftId,
          initial.mutation,
          jsonEncode({
            'type': 'RenameLabel',
            'targetId': 'app',
            'label': 'My saved notes',
          }),
        );
        final fresh = user(actor(owner));
        final listed = (await Apps.list(fresh, workspace)).single;
        expect(listed.appId, initial.appId);
        expect(listed.versionId, isNull);
        expect(listed.name, 'My saved notes');
        expect(listed.specJson, changed.candidateJson);
        final manifest = await Apps.manifest(fresh, initial.appId);
        expect(manifest.specJson, changed.candidateJson);
        final resumed = await Builder.begin(
          fresh,
          workspace,
          'ignored',
          initial.appId,
        );
        expect(resumed.draftId, initial.draftId);
        expect(resumed.mutation, changed.mutation);
        expect(resumed.candidateHash, changed.candidateHash);
        expect(
          await AppDraft.db.count(
            owner,
            where: (t) => t.appId.equals(initial.appId),
          ),
          1,
        );
      },
    );

    test(
      'concurrent resumes reuse one draft without creating extra rows',
      () async {
        final count = await AppDraft.db.count(
          owner,
          where: (t) => t.appId.equals(initial.appId),
        );
        final results = await Future.wait([
          Builder.begin(user(actor(owner)), workspace, 'notes', initial.appId),
          Builder.begin(user(actor(owner)), workspace, 'notes', initial.appId),
        ]);
        expect(results.map((r) => r.draftId).toSet(), {initial.draftId});
        expect(
          await AppDraft.db.count(
            owner,
            where: (t) => t.appId.equals(initial.appId),
          ),
          count,
        );
      },
    );

    test(
      'draft content stays author private with app builder access',
      () async {
        final builder = await collaborator('builder');
        final viewer = await collaborator('viewer');
        expect(await Apps.list(builder, workspace), isEmpty);
        expect(await Apps.list(viewer, workspace), isEmpty);
        await expectLater(Apps.manifest(builder, initial.appId), unavailable);
        await expectLater(
          Builder.begin(builder, workspace, 'notes', initial.appId),
          unavailable,
        );
        await expectLater(Builder.get(builder, initial.draftId), unavailable);
        await expectLater(
          Builder.patch(builder, initial.draftId, 0, '{}'),
          unavailable,
        );
        await expectLater(
          Builder.publish(
            builder,
            PublishRequest(
              draftId: initial.draftId,
              candidateHash: initial.candidateHash,
              enabledRuleIds: [],
              activateExistingRecordIds: [],
              reviewHash: 'unavailable',
              idempotencyKey: 'another-authors-draft',
            ),
          ),
          unavailable,
        );

        final spec = dailyPlannerTemplate();
        final own = await AppDraft.db.insertRow(
          owner,
          AppDraft(
            appId: initial.appId,
            workspaceId: workspace,
            actorId: actor(builder),
            candidateJson: spec.canonical,
            candidateHash: spec.hash,
            updatedAt: clock().add(const Duration(seconds: 1)),
          ),
        );
        expect(
          (await Apps.list(builder, workspace)).single.specJson,
          spec.canonical,
        );
        expect((await Apps.manifest(builder, initial.appId)).name, spec.name);
        expect(
          (await Builder.begin(
            builder,
            workspace,
            'notes',
            initial.appId,
          )).draftId,
          own.id,
        );
        expect(
          (await Apps.manifest(owner, initial.appId)).specJson,
          initial.candidateJson,
        );
        await expectLater(Builder.get(owner, own.id!), unavailable);
      },
    );

    test(
      'revocation, workspace removal and archive prevent draft recovery',
      () async {
        final builder = await collaborator('builder');
        final d = await AppDraft.db.findById(owner, initial.draftId);
        await AppDraft.db.insertRow(
          owner,
          d!.copyWith(id: null, actorId: actor(builder)),
        );
        final grant = await MiniAppGrant.db.findFirstRow(
          owner,
          where: (t) =>
              t.appId.equals(initial.appId) & t.actorId.equals(actor(builder)),
        );
        grant!.revoked = true;
        await MiniAppGrant.db.updateRow(owner, grant);
        expect(await Apps.list(builder, workspace), isEmpty);
        await expectLater(Apps.manifest(builder, initial.appId), unavailable);
        await expectLater(
          Builder.begin(builder, workspace, 'notes', initial.appId),
          unavailable,
        );

        await Apps.archive(owner, initial.appId);
        expect(await Apps.list(owner, workspace), isEmpty);
        await expectLater(
          Apps.manifest(owner, initial.appId),
          throwsA(
            isA<NestError>().having((e) => e.category, 'category', 'forbidden'),
          ),
        );
        await WorkspaceMember.db.deleteWhere(
          owner,
          where: (t) =>
              t.workspaceId.equals(workspace) & t.actorId.equals(actor(owner)),
        );
        await expectLater(Builder.get(owner, initial.draftId), unavailable);
        await expectLater(Apps.list(owner, workspace), unavailable);
      },
    );

    test(
      'latest author draft is selected and published launcher stays live',
      () async {
        final spec = dailyPlannerTemplate();
        final newer = await AppDraft.db.insertRow(
          owner,
          AppDraft(
            appId: initial.appId,
            workspaceId: workspace,
            actorId: actor(owner),
            candidateJson: spec.canonical,
            candidateHash: spec.hash,
            updatedAt: clock().add(const Duration(seconds: 1)),
          ),
        );
        expect(
          (await Builder.begin(
            owner,
            workspace,
            'notes',
            initial.appId,
          )).draftId,
          newer.id,
        );
        final publishedId = await Apps.instantiate(owner, workspace, 'notes');
        final published = await Apps.manifest(owner, publishedId);
        final edit = await Builder.begin(
          owner,
          workspace,
          'notes',
          publishedId,
        );
        await Builder.patch(
          owner,
          edit.draftId,
          edit.mutation,
          jsonEncode({
            'type': 'RenameLabel',
            'targetId': 'app',
            'label': 'Unpublished edit',
          }),
        );
        final launcher = (await Apps.list(
          owner,
          workspace,
        )).singleWhere((app) => app.appId == publishedId);
        expect(launcher.versionId, published.versionId);
        expect(launcher.specJson, published.specJson);
        expect(launcher.name, published.name);
      },
    );

    test('resume rejects a different authorized workspace', () async {
      final other = await Apps.createWorkspace(owner, 'Another workspace');
      await expectLater(
        Builder.begin(owner, other, 'notes', initial.appId),
        unavailable,
      );
    });
  }, rollbackDatabase: RollbackDatabase.disabled);
}

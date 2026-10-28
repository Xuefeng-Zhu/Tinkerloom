import 'package:appnest_server/src/generated/protocol.dart';
import 'package:appnest_server/src/modules/builder/builder.dart';
import 'package:appnest_server/src/modules/builder/provider.dart';
import 'package:appnest_server/src/modules/collaboration/sharing.dart';
import 'package:appnest_server/src/modules/definitions/apps.dart';
import 'package:appnest_server/src/modules/runtime/access.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:serverpod/serverpod.dart';
import 'package:test/test.dart';

import 'test_tools/serverpod_test_tools.dart';

class _GuidanceStub implements GuidanceProvider {
  int calls = 0;
  AppSpec? definition;
  List<GuidanceQuestion> response = [
    GuidanceQuestion(
      question: 'Who will use this app?',
      options: ['Members', 'Organizers', 'Both groups'],
    ),
    GuidanceQuestion(
      question: 'What should they track?',
      options: ['Events', 'Membership', 'Shared tasks'],
    ),
  ];

  @override
  Future<List<GuidanceQuestion>> suggestQuestions(
    String idea, {
    AppSpec? definition,
  }) async {
    calls++;
    this.definition = definition;
    return response;
  }
}

void main() {
  withServerpod('Guidance authorization and quota', (sessions, endpoints) {
    Session user(String name) => sessions
        .copyWith(
          authentication: AuthenticationOverride.authenticationInfo(
            '$name-${randomToken()}',
            {},
          ),
        )
        .build();

    Matcher category(String name) => isA<NestError>().having(
      (e) => e.category,
      'category',
      name,
    );

    test(
      'new idea and draft guidance neither create nor mutate apps',
      () async {
        final owner = user('guidance-owner');
        final stranger = user('guidance-stranger');
        final workspace = await Apps.createWorkspace(
          owner,
          'Guidance workspace',
        );
        final ai = _GuidanceStub();
        final beforeApps = await MiniApp.db.count(
          owner,
          where: (t) => t.workspaceId.equals(workspace),
        );
        final beforeDrafts = await AppDraft.db.count(
          owner,
          where: (t) => t.workspaceId.equals(workspace),
        );
        final suggestions = await Builder.suggestQuestions(
          owner,
          'A library app',
          workspace,
          null,
          provider: ai,
        );
        expect(suggestions, hasLength(2));
        expect(suggestions.first.question, 'Who will use this app?');
        expect(suggestions.first.options, [
          'Members',
          'Organizers',
          'Both groups',
        ]);
        expect(ai.definition, isNull);
        expect(
          await MiniApp.db.count(
            owner,
            where: (t) => t.workspaceId.equals(workspace),
          ),
          beforeApps,
        );
        expect(
          await AppDraft.db.count(
            owner,
            where: (t) => t.workspaceId.equals(workspace),
          ),
          beforeDrafts,
        );
        ai.response = [];
        expect(
          await Builder.suggestQuestions(
            owner,
            'A book club app for members to track books and share notes',
            workspace,
            null,
            provider: ai,
          ),
          isEmpty,
        );
        expect(
          await MiniApp.db.count(
            owner,
            where: (t) => t.workspaceId.equals(workspace),
          ),
          beforeApps,
        );
        expect(
          await AppDraft.db.count(
            owner,
            where: (t) => t.workspaceId.equals(workspace),
          ),
          beforeDrafts,
        );
        expect(
          await GuidanceRequest.db.count(
            owner,
            where: (t) => t.actorId.equals(actor(owner)),
          ),
          2,
        );
        ai.response = [
          GuidanceQuestion(
            question: 'Who will use this app?',
            options: ['Members', 'Organizers', 'Both groups'],
          ),
          GuidanceQuestion(
            question: 'What should they track?',
            options: ['Events', 'Membership', 'Shared tasks'],
          ),
        ];
        await expectLater(
          Builder.suggestQuestions(
            stranger,
            'A library app',
            workspace,
            null,
            provider: ai,
          ),
          throwsA(category('notFound')),
        );
        expect(ai.calls, 2);

        final draft = await Builder.begin(owner, workspace, 'reading', null);
        final before = await AppDraft.db.findById(owner, draft.draftId);
        final jobs = await GenerationJob.db.count(
          owner,
          where: (t) => t.draftId.equals(draft.draftId),
        );
        await Builder.suggestQuestions(
          owner,
          'Make it useful',
          null,
          draft.draftId,
          provider: ai,
        );
        expect(ai.definition!.canonical, draft.candidateJson);
        expect(ai.definition!.toJson().keys, isNot(contains('records')));
        final after = await AppDraft.db.findById(owner, draft.draftId);
        expect(after!.mutation, before!.mutation);
        expect(after.candidateHash, before.candidateHash);
        expect(after.activeJobId, before.activeJobId);
        expect(
          await GenerationJob.db.count(
            owner,
            where: (t) => t.draftId.equals(draft.draftId),
          ),
          jobs,
        );
        await expectLater(
          Builder.suggestQuestions(
            owner,
            'bad',
            workspace,
            draft.draftId,
            provider: ai,
          ),
          throwsA(category('invalidInput')),
        );
      },
    );

    test(
      'draft guidance is private to its author with builder access',
      () async {
        final owner = user('guidance-owner');
        final workspace = await Apps.createWorkspace(owner, 'Guidance roles');
        final draft = await Builder.begin(owner, workspace, 'reading', null);
        final ai = _GuidanceStub();
        final collaborators = <String, Session>{};
        for (final role in ['builder', 'member', 'viewer']) {
          final member = user('guidance-$role');
          collaborators[role] = member;
          final token = await Sharing.invite(owner, draft.appId, role, null);
          await Sharing.accept(member, token);
          await expectLater(
            Builder.suggestQuestions(
              member,
              'Improve this library',
              null,
              draft.draftId,
              provider: ai,
            ),
            throwsA(category('notFound')),
          );
        }
        final stranger = user('guidance-stranger');
        await expectLater(
          Builder.suggestQuestions(
            stranger,
            'Improve this library',
            null,
            draft.draftId,
            provider: ai,
          ),
          throwsA(category('notFound')),
        );
        expect(ai.calls, 0);
        expect(
          await Builder.suggestQuestions(
            owner,
            'Improve this library',
            null,
            draft.draftId,
            provider: ai,
          ),
          hasLength(2),
        );
        expect(ai.definition!.canonical, draft.candidateJson);
        expect(ai.calls, 1);

        await Builder.publish(
          owner,
          PublishRequest(
            draftId: draft.draftId,
            candidateHash: draft.candidateHash,
            enabledRuleIds: [],
            activateExistingRecordIds: [],
            reviewHash: hashJson({
              'candidateHash': draft.candidateHash,
              'enabledRuleIds': [],
              'activateExistingRecordIds': [],
            }),
            idempotencyKey: 'guidance-publication',
          ),
        );
        final builderDraft = await Builder.begin(
          collaborators['builder']!,
          workspace,
          'reading',
          draft.appId,
        );
        expect(builderDraft.draftId, isNot(draft.draftId));
        expect(
          await Builder.suggestQuestions(
            collaborators['builder']!,
            'Improve my library draft',
            null,
            builderDraft.draftId,
            provider: ai,
          ),
          hasLength(2),
        );
        expect(ai.definition!.canonical, builderDraft.candidateJson);
        expect(ai.calls, 2);
        for (final role in ['member', 'viewer']) {
          await expectLater(
            Builder.begin(
              collaborators[role]!,
              workspace,
              'reading',
              draft.appId,
            ),
            throwsA(category('forbidden')),
          );
        }
      },
    );

    test(
      'rolling quota atomically allows one final concurrent request',
      () async {
        final owner = user('guidance-quota');
        final workspace = await Apps.createWorkspace(owner, 'Guidance quota');
        final ai = _GuidanceStub();
        for (var i = 0; i < 19; i++) {
          await Builder.suggestQuestions(
            owner,
            'An app idea',
            workspace,
            null,
            provider: ai,
          );
        }
        final outcomes = await Future.wait(
          List.generate(2, (_) async {
            try {
              await Builder.suggestQuestions(
                owner,
                'An app idea',
                workspace,
                null,
                provider: ai,
              );
              return 'accepted';
            } on NestError catch (e) {
              return e.category;
            }
          }),
        );
        expect(outcomes, unorderedEquals(['accepted', 'quotaExceeded']));
        expect(
          await GuidanceRequest.db.count(
            owner,
            where: (t) => t.actorId.equals(actor(owner)),
          ),
          20,
        );
        final other = user('guidance-other');
        final otherWorkspace = await Apps.createWorkspace(
          other,
          'Other guidance',
        );
        expect(
          await Builder.suggestQuestions(
            other,
            'Another app idea',
            otherWorkspace,
            null,
            provider: ai,
          ),
          hasLength(2),
        );
      },
    );
  }, rollbackDatabase: RollbackDatabase.disabled);
}

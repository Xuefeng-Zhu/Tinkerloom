import 'dart:convert';

import 'package:appnest_server/src/endpoints/builder_endpoint.dart';
import 'package:appnest_server/src/generated/protocol.dart';
import 'package:appnest_server/src/modules/builder/builder.dart';
import 'package:appnest_server/src/modules/builder/provider.dart';
import 'package:appnest_server/src/modules/definitions/apps.dart';
import 'package:appnest_server/src/modules/runtime/access.dart';
import 'package:appnest_server/src/modules/runtime/commands.dart';
import 'package:appnest_server/src/modules/runtime/integrity.dart';
import 'package:appnest_server/src/modules/runtime/queries.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:serverpod/serverpod.dart';
import 'package:serverpod/protocol.dart' show FutureCallEntry;
import 'package:test/test.dart';

import 'test_tools/serverpod_test_tools.dart';

class _GuidanceSpy implements GuidanceProvider {
  int calls = 0;

  @override
  Future<List<GuidanceQuestion>> suggestQuestions(
    String idea, {
    AppSpec? definition,
  }) async {
    calls++;
    return [];
  }
}

void main() {
  withServerpod(
    'AI unavailable without background execution',
    (sessions, endpoints) {
      late Session owner;
      late int workspace;
      late Map<String, String> originalPasswords;

      setUpAll(() async => Integrity.ensure(sessions.build()));
      setUp(() async {
        owner = sessions
            .copyWith(
              authentication: AuthenticationOverride.authenticationInfo(
                'ai-disabled-${randomToken()}',
                {},
              ),
            )
            .build();
        originalPasswords = owner.server.passwords;
        // Valid synthetic configuration proves the runtime guard wins even when
        // an operator has configured a provider. No external request is made.
        owner.server.passwords = {
          ...originalPasswords,
          'AI_BASE_URL': 'https://example.invalid/v1',
          'AI_MODEL': 'test-only',
          'AI_API_KEY': 'test-only',
        };
        workspace = await Apps.createWorkspace(owner, 'AI disabled tests');
      });
      tearDown(() => owner.server.passwords = originalPasswords);

      final unavailable = throwsA(
        isA<NestError>()
            .having((e) => e.category, 'category', 'providerUnavailable')
            .having(
              (e) => e.message,
              'message',
              contains('background processing is disabled'),
            ),
      );

      test(
        'configured provider is unavailable through the platform endpoint',
        () async {
          expect(ChatCompletionProvider.configured(owner), isNotNull);
          final platform = await BuilderEndpoint().platform(owner);
          expect(platform.aiAvailable, isFalse);
          expect(
            platform.aiMode,
            contains('background processing is disabled'),
          );
          expect(platform.actorId, actor(owner));
        },
      );

      test('generation rejects both modes without changing the draft or creating a wakeup', () async {
        final draft = await Builder.begin(owner, workspace, 'notes', null);
        final before = (await AppDraft.db.findById(
          owner,
          draft.draftId,
        ))!.toJson();
        final wakeups = await FutureCallEntry.db.count(owner);
        for (final startFromScratch in [true, false]) {
          await expectLater(
            Builder.generate(
              owner,
              draft.draftId,
              draft.mutation,
              'Add optional Priority',
              startFromScratch: startFromScratch,
            ),
            unavailable,
          );
        }
        await expectLater(
          Builder.generate(
            owner,
            draft.draftId,
            draft.mutation + 1,
            'Stale draft',
          ),
          throwsA(
            isA<NestError>().having(
              (e) => e.category,
              'category',
              'recordConflict',
            ),
          ),
        );
        expect(
          (await AppDraft.db.findById(owner, draft.draftId))!.toJson(),
          before,
        );
        expect(
          await GenerationJob.db.count(
            owner,
            where: (t) => t.actorId.equals(actor(owner)),
          ),
          0,
        );
        expect(await FutureCallEntry.db.count(owner), wakeups);
        final stranger = sessions
            .copyWith(
              authentication: AuthenticationOverride.authenticationInfo(
                'stranger-${randomToken()}',
                {},
              ),
            )
            .build();
        await expectLater(
          Builder.generate(
            stranger,
            draft.draftId,
            draft.mutation,
            'Foreign draft',
          ),
          throwsA(
            isA<NestError>().having((e) => e.category, 'category', 'notFound'),
          ),
        );
      });

      test(
        'guidance rejects before provider calls or quota reservations',
        () async {
          final draft = await Builder.begin(owner, workspace, 'notes', null);
          final before = (await AppDraft.db.findById(
            owner,
            draft.draftId,
          ))!.toJson();
          final provider = _GuidanceSpy();
          await expectLater(
            Builder.suggestQuestions(
              owner,
              'A personal notes app',
              workspace,
              null,
              provider: provider,
            ),
            unavailable,
          );
          await expectLater(
            Builder.suggestQuestions(
              owner,
              'Add a priority field',
              null,
              draft.draftId,
              provider: provider,
            ),
            unavailable,
          );
          expect(provider.calls, 0);
          expect(
            await GuidanceRequest.db.count(
              owner,
              where: (t) => t.actorId.equals(actor(owner)),
            ),
            0,
          );
          expect(
            await GenerationJob.db.count(
              owner,
              where: (t) => t.actorId.equals(actor(owner)),
            ),
            0,
          );
          expect(
            (await AppDraft.db.findById(owner, draft.draftId))!.toJson(),
            before,
          );
          final stranger = sessions
              .copyWith(
                authentication: AuthenticationOverride.authenticationInfo(
                  'guidance-stranger-${randomToken()}',
                  {},
                ),
              )
              .build();
          await expectLater(
            Builder.suggestQuestions(
              stranger,
              'Foreign workspace',
              workspace,
              null,
              provider: provider,
            ),
            throwsA(
              isA<NestError>().having(
                (e) => e.category,
                'category',
                'notFound',
              ),
            ),
          );
          expect(provider.calls, 0);
        },
      );

      test('templates and manual changes publish and persist without AI or enabled reminders', () async {
        expect(Apps.templates().map((t) => t.key), contains('notes'));
        final draft = await Builder.begin(owner, workspace, 'notes', null);
        final edited = await Builder.patch(
          owner,
          draft.draftId,
          draft.mutation,
          jsonEncode({
            'type': 'RenameLabel',
            'targetId': 'app',
            'label': 'Manual Notes',
          }),
        );
        final version = await Builder.publish(
          owner,
          PublishRequest(
            draftId: edited.draftId,
            candidateHash: edited.candidateHash,
            enabledRuleIds: [],
            activateExistingRecordIds: [],
            reviewHash: hashJson({
              'candidateHash': edited.candidateHash,
              'enabledRuleIds': [],
              'activateExistingRecordIds': [],
            }),
            idempotencyKey: 'manual-publication',
          ),
        );
        final manifest = await Apps.manifest(owner, draft.appId);
        expect(manifest.versionId, version);
        expect(AppSpec.parse(manifest.specJson!).name, 'Manual Notes');
        final created = await Commands.execute(
          owner,
          ActionRequest(
            appId: draft.appId,
            actionId: 'addRecord',
            expectedDefinitionVersionId: version,
            input: {
              'data': {'title': 'Template note', 'body': 'Saved without AI'},
            },
            idempotencyKey: 'manual-note',
          ),
        );
        final saved = await Queries.get(owner, draft.appId, created.recordId);
        expect(saved.data, {
          'title': 'Template note',
          'body': 'Saved without AI',
        });
        expect(saved.revision, 1);
        expect(
          await GenerationJob.db.count(
            owner,
            where: (t) => t.actorId.equals(actor(owner)),
          ),
          0,
        );
        expect(
          await GuidanceRequest.db.count(
            owner,
            where: (t) => t.actorId.equals(actor(owner)),
          ),
          0,
        );
      });

      test(
        'enabled runtime still exposes configured AI and permits guidance',
        () async {
          final originalConfig = owner.serverpod.config;
          owner.serverpod.config = originalConfig.copyWith(
            futureCallExecutionEnabled: true,
          );
          try {
            expect(Builder.platform(owner).aiAvailable, isTrue);
            expect(Builder.platform(owner).aiMode, 'Live AI');
            final provider = _GuidanceSpy();
            expect(
              await Builder.suggestQuestions(
                owner,
                'A personal notes app',
                workspace,
                null,
                provider: provider,
              ),
              isEmpty,
            );
            expect(provider.calls, 1);
            expect(
              await GuidanceRequest.db.count(
                owner,
                where: (t) => t.actorId.equals(actor(owner)),
              ),
              1,
            );
          } finally {
            owner.serverpod.config = originalConfig;
          }
        },
      );
    },
    configOverride: (config) =>
        config.copyWith(futureCallExecutionEnabled: false),
    rollbackDatabase: RollbackDatabase.disabled,
  );
}

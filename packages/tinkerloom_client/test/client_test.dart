import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:appnest_spec/appnest_spec.dart' as spec;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:tinkerloom_client/tinkerloom_client.dart';

import '../../../appwrite_backend/lib/service.dart' as backend;
import '../../../appwrite_backend/lib/providers/provider.dart' as ai;
import '../../../appwrite_backend/test/memory_store.dart';

Future<Map<String, dynamic>> executeFixture(
  Fixture fixture,
  String actor,
  Map<String, dynamic> input,
) async {
  try {
    return await fixture.service.execute(actor, input);
  } on backend.ServiceException catch (error) {
    throw NestError(
      category: error.code,
      status: error.status,
      message: 'Draft unavailable',
    );
  }
}

class MemoryFiles implements backend.PrivateFileStore {
  final files = <String, Uint8List>{};
  @override
  Future<void> put(String id, Uint8List bytes, String type) async {
    files[id] = Uint8List.fromList(bytes);
  }

  @override
  Future<Uint8List> read(String id, {required int maximumBytes}) async {
    final bytes = files[id]!;
    if (bytes.length > maximumBytes) throw StateError('bounded');
    return Uint8List.fromList(bytes);
  }

  @override
  Future<void> remove(String id) async {
    files.remove(id);
  }
}

class OfflineRejectedProvider implements ai.AiProvider {
  int calls = 0;
  @override
  Future<ai.AiResult> generate(
    String request,
    spec.AppSpec current, {
    required bool editing,
    List<String> diagnostics = const [],
    String? rejectedOutput,
  }) async {
    calls++;
    throw const ai.AiResponseException(
      'provider_auth',
      'Synthetic offline provider rejection',
      statusCode: 401,
      retryable: false,
    );
  }
}

class OfflineIndeterminateProvider implements ai.AiProvider {
  int calls = 0;
  @override
  Future<ai.AiResult> generate(
    String request,
    spec.AppSpec current, {
    required bool editing,
    List<String> diagnostics = const [],
    String? rejectedOutput,
  }) async {
    calls++;
    throw const ai.AiResponseException(
      'indeterminate',
      'Synthetic outcome unknown',
      statusCode: 202,
      retryable: false,
    );
  }
}

class Fixture {
  Fixture({ai.AiProvider? provider}) {
    service = backend.PlatformService(
      store,
      media: files,
      aiProvider: provider,
      remindersEnabled: true,
      clock: () => DateTime.utc(2030),
    );
    client = forActor('alice');
  }
  final store = MemoryStore();
  final files = MemoryFiles();
  late final backend.PlatformService service;
  late final Client client;
  final calls = <Map<String, dynamic>>[];
  bool loseNextMutation = false;
  String? loseNextOp;
  String? loseBeforeOp;
  Client forActor(String actor) => Client(
    'https://offline.invalid/v1',
    auth: ClientAuth()..setSession({'id': actor}),
    transport: (input) async {
      calls.add(jsonDecode(jsonEncode(input)) as Map<String, dynamic>);
      try {
        if (input['op'] == loseBeforeOp) {
          loseBeforeOp = null;
          throw BackendNetworkException(
            'Synthetic unknown before commit',
            uncertain: true,
          );
        }
        final result = await service.execute(actor, input);
        if ((loseNextMutation && input['op'] == 'spec.execute') ||
            input['op'] == loseNextOp) {
          loseNextOp = null;
          loseNextMutation = false;
          throw BackendNetworkException(
            'Synthetic lost reply',
            uncertain: true,
          );
        }
        return result;
      } on backend.ServiceException catch (error) {
        throw NestError(
          category: error.code,
          message: 'Synthetic ${input['op']}: ${error.code}',
          status: error.status,
        );
      }
    },
  );
  Future<(String, BuilderSnapshot)> draft([String template = 'reading']) async {
    final workspace = await client.apps.createWorkspace(
      'Synthetic offline workspace',
    );
    return (workspace, await client.builder.begin(workspace, template, null));
  }

  Future<(String, String)> published([String template = 'reading']) async {
    final (_, draft) = await this.draft(template);
    final version = await client.builder.publish(
      PublishRequest(
        draftId: draft.draftId,
        candidateHash: draft.candidateHash,
        expectedCurrentVersionId: null,
        enabledRuleIds: [],
        activateExistingRecordIds: [],
        reviewHash: spec.hashJson({
          'candidateHash': draft.candidateHash,
          'enabledRuleIds': <String>[],
          'activateExistingRecordIds': <String>[],
        }),
        idempotencyKey: 'publish-${draft.appId}',
      ),
    );
    return (draft.appId, version);
  }

  Future<ActionOutcome> add(
    String app,
    String version, {
    String key = 'create-record',
    Map<String, dynamic>? data,
  }) => client.runtime.execute(
    ActionRequest(
      appId: app,
      actionId: spec.AppSpec.parse(jsonEncode((clientManifest(app))['spec']))
          .actions
          .firstWhere((a) => a.capability == 'records.create.v1')
          .id,
      expectedDefinitionVersionId: version,
      input: {
        'data': data ?? {'title': 'A book', 'status': 'Reading'},
      },
      idempotencyKey: key,
    ),
  );
  Map<String, dynamic> clientManifest(String app) {
    final row = store.rows['apps']![app]!,
        version = store.rows['spec_versions']![row['specVersionId']]!;
    return {'spec': jsonDecode(version['specJson'] as String)};
  }
}

void main() {
  test(
    'receipt confirmation and exact mutation retry are mutually exclusive',
    () async {
      final calls = <String>[];
      final retry = Completer<Map<String, dynamic>>();
      final receipt = Completer<Map<String, dynamic>>();
      final auth = ClientAuth()..setSession({'id': 'alice'});
      final client = Client(
        'https://offline.invalid',
        auth: auth,
        transport: (input) {
          final op = input['op'] as String;
          calls.add(op);
          if (op == 'spec.commandReceipt') return receipt.future;
          if (op == 'spec.capabilities') return Future.value({});
          if (calls.where((v) => v == 'spec.generate').length == 1) {
            return Future.error(
              BackendNetworkException('lost', uncertain: true),
            );
          }
          return retry.future;
        },
      );
      addTearDown(client.close);
      final command = {
        'op': 'spec.generate',
        'appId': 'app',
        'operationId': 'op1',
        'expectedRevision': 0,
        'request': 'idea',
        'startFromScratch': false,
      };
      Future<RetainedCommandStatus> confirm() =>
          client.confirmRetainedBuilderCommand(
            appId: 'app',
            operation: 'spec.generate',
            expectedRevision: 0,
            request: 'idea',
            startFromScratch: false,
          );
      await expectLater(
        client.request(command),
        throwsA(isA<BackendNetworkException>()),
      );
      final retried = client.request(command);
      final retryFailure = expectLater(
        retried,
        throwsA(isA<BackendNetworkException>()),
      );
      await expectLater(
        confirm(),
        throwsA(
          isA<NestError>().having(
            (e) => e.category,
            'category',
            'command_in_progress',
          ),
        ),
      );
      expect(calls, ['spec.generate', 'spec.generate']);
      retry.completeError(
        BackendNetworkException('lost again', uncertain: true),
      );
      await retryFailure;
      final checking = confirm();
      await expectLater(
        client.request(command),
        throwsA(
          isA<NestError>().having(
            (e) => e.category,
            'category',
            'command_in_progress',
          ),
        ),
      );
      final capabilities = client.request({'op': 'spec.capabilities'});
      expect(calls, ['spec.generate', 'spec.generate', 'spec.commandReceipt']);
      receipt.complete({'confirmed': true});
      expect(await checking, RetainedCommandStatus.confirmed);
      await capabilities;
      expect(calls, [
        'spec.generate',
        'spec.generate',
        'spec.commandReceipt',
        'spec.capabilities',
      ]);
    },
  );
  for (final lose in [false, true]) {
    test(
      'mutation admission rejects concurrent dispatch after ${lose ? 'uncertain' : 'successful'} first result',
      () async {
        final first = Completer<Map<String, dynamic>>();
        final calls = <Map<String, dynamic>>[];
        final auth = ClientAuth()..setSession({'id': 'alice'});
        final client = Client(
          'https://offline.invalid',
          auth: auth,
          transport: (input) {
            calls.add(input);
            if (input['op'] == 'spec.capabilities') return Future.value({});
            if (calls.where((v) => v['op'] == 'createWorkspace').length == 1) {
              return first.future;
            }
            return Future.value({
              'workspace': {'id': input['id'], 'name': input['name']},
            });
          },
        );
        addTearDown(client.close);
        final command = {'op': 'createWorkspace', 'id': 'one', 'name': 'One'};
        final inFlight = client.request(command);
        final assertion = lose
            ? expectLater(inFlight, throwsA(isA<BackendNetworkException>()))
            : expectLater(inFlight, completion(isA<Map<String, dynamic>>()));
        for (final other in [
          command,
          {'op': 'createWorkspace', 'id': 'two', 'name': 'Two'},
        ]) {
          await expectLater(
            client.request(other),
            throwsA(
              isA<NestError>().having(
                (e) => e.category,
                'category',
                'command_in_progress',
              ),
            ),
          );
        }
        await client.request({'op': 'spec.capabilities'});
        expect(calls.where((v) => v['op'] == 'createWorkspace'), hasLength(1));
        if (lose) {
          first.completeError(BackendNetworkException('lost', uncertain: true));
        } else {
          first.complete({
            'workspace': {'id': 'one', 'name': 'One'},
          });
        }
        await assertion;
        if (lose) {
          await expectLater(
            client.request({
              'op': 'createWorkspace',
              'id': 'two',
              'name': 'Two',
            }),
            throwsA(
              isA<NestError>().having(
                (e) => e.category,
                'category',
                'pending_command',
              ),
            ),
          );
          await client.request(
            command,
          ); // Explicit exact-envelope retry after settlement.
        } else {
          await client.request({
            'op': 'createWorkspace',
            'id': 'two',
            'name': 'Two',
          });
        }
        expect(calls.where((v) => v['op'] == 'createWorkspace'), hasLength(2));
      },
    );
  }

  test(
    'mutation admission survives session change until transport settles',
    () async {
      final first = Completer<Map<String, dynamic>>();
      final calls = <Map<String, dynamic>>[];
      final auth = ClientAuth()..setSession({'id': 'alice'});
      final client = Client(
        'https://offline.invalid',
        auth: auth,
        transport: (input) {
          calls.add(input);
          if (calls.length == 1) return first.future;
          return Future.value({
            'workspace': {'id': input['id'], 'name': input['name']},
          });
        },
      );
      addTearDown(client.close);
      final previous = client.request({
        'op': 'createWorkspace',
        'id': 'one',
        'name': 'One',
      });
      final rejected = expectLater(
        previous,
        throwsA(isA<BackendUnauthorized>()),
      );
      auth.setSession({'id': 'bob'});
      await expectLater(
        client.request({'op': 'createWorkspace', 'id': 'two', 'name': 'Two'}),
        throwsA(
          isA<NestError>().having(
            (e) => e.category,
            'category',
            'command_in_progress',
          ),
        ),
      );
      expect(calls, hasLength(1));
      first.complete({
        'workspace': {'id': 'one', 'name': 'One'},
      });
      await rejected;
      await client.request({
        'op': 'createWorkspace',
        'id': 'two',
        'name': 'Two',
      });
      expect(calls, hasLength(2));
    },
  );
  for (final operation in ['spec.saveDraft', 'spec.generate']) {
    test(
      'confirmed $operation receipt unlocks without replay or wake',
      () async {
        final provider = OfflineRejectedProvider();
        final f = Fixture(provider: provider);
        addTearDown(f.client.close);
        final (_, draft) = await f.draft();
        f.loseNextOp = operation;
        Future<BuilderSnapshot> send() => operation == 'spec.saveDraft'
            ? f.client.builder.patch(
                draft.draftId,
                draft.mutation,
                jsonEncode({
                  'type': 'RenameLabel',
                  'targetId': 'title',
                  'label': 'Book title',
                }),
              )
            : f.client.builder.generate(
                draft.draftId,
                draft.mutation,
                'Offline edit',
                startFromScratch: false,
              );
        await expectLater(send(), throwsA(isA<BackendNetworkException>()));
        final readback = await f.client.builder.get(draft.draftId);
        expect(readback.mutation, draft.mutation + 1);
        await expectLater(
          f.client.builder.patch(
            readback.draftId,
            readback.mutation,
            jsonEncode({
              'type': 'RenameLabel',
              'targetId': 'title',
              'label': 'Second',
            }),
          ),
          throwsA(
            isA<NestError>().having(
              (e) => e.category,
              'category',
              'pending_command',
            ),
          ),
        );
        final command = f.calls.lastWhere((v) => v['op'] == operation);
        final mismatched = {...command, 'expectedRevision': 999};
        await expectLater(
          f.service.execute('alice', {
            'op': 'spec.commandReceipt',
            'command': mismatched,
          }),
          throwsA(
            isA<backend.ServiceException>().having(
              (e) => e.code,
              'code',
              'operation_conflict',
            ),
          ),
        );
        await expectLater(
          f.service.execute('bob', {
            'op': 'spec.commandReceipt',
            'command': command,
          }),
          throwsA(isA<backend.ServiceException>()),
        );
        final before = f.calls.where((v) => v['op'] == operation).length;
        final beforeReceipts = f.calls
            .where((v) => v['op'] == 'spec.commandReceipt')
            .length;
        await expectLater(
          f.client.confirmRetainedBuilderCommand(
            appId: 'wrong-app',
            operation: operation,
            expectedRevision: draft.mutation,
            request: operation == 'spec.generate' ? 'Offline edit' : null,
            startFromScratch: operation == 'spec.generate' ? false : null,
            candidateHash: operation == 'spec.saveDraft'
                ? readback.candidateHash
                : null,
          ),
          throwsA(
            isA<NestError>().having(
              (e) => e.category,
              'category',
              'pending_command',
            ),
          ),
        );
        expect(
          f.calls.where((v) => v['op'] == 'spec.commandReceipt').length,
          beforeReceipts,
        );
        expect(
          await f.client.confirmRetainedBuilderCommand(
            appId: draft.draftId,
            operation: operation,
            expectedRevision: draft.mutation,
            request: operation == 'spec.generate' ? 'Offline edit' : null,
            startFromScratch: operation == 'spec.generate' ? false : null,
            candidateHash: operation == 'spec.saveDraft'
                ? readback.candidateHash
                : null,
          ),
          RetainedCommandStatus.confirmed,
        );
        expect(f.calls.where((v) => v['op'] == operation).length, before);
        expect(provider.calls, 0);
        // Receipt confirmation alone does not finish the recovery snapshot.
        await f.client.builder.getForRecovery(readback.draftId);
        final changed = await f.client.builder.patch(
          readback.draftId,
          readback.mutation,
          jsonEncode({
            'type': 'RenameLabel',
            'targetId': 'title',
            'label': 'Second',
          }),
        );
        expect(changed.mutation, readback.mutation + 1);
      },
    );
  }

  test('missing receipt keeps uncertain command locked', () async {
    final f = Fixture();
    addTearDown(f.client.close);
    final (_, draft) = await f.draft();
    f.loseBeforeOp = 'spec.saveDraft';
    await expectLater(
      f.client.builder.patch(
        draft.draftId,
        draft.mutation,
        jsonEncode({
          'type': 'RenameLabel',
          'targetId': 'title',
          'label': 'One',
        }),
      ),
      throwsA(isA<BackendNetworkException>()),
    );
    final expected = spec.AppSpec.parse(draft.candidateJson).patch({
      'type': 'RenameLabel',
      'targetId': 'title',
      'label': 'One',
    }, () => 'unused');
    expect(
      await f.client.confirmRetainedBuilderCommand(
        appId: draft.draftId,
        operation: 'spec.saveDraft',
        expectedRevision: draft.mutation,
        candidateHash: expected.hash,
      ),
      RetainedCommandStatus.pending,
    );
    await expectLater(
      f.client.builder.patch(
        draft.draftId,
        draft.mutation,
        jsonEncode({
          'type': 'RenameLabel',
          'targetId': 'title',
          'label': 'Two',
        }),
      ),
      throwsA(
        isA<NestError>().having(
          (e) => e.category,
          'category',
          'pending_command',
        ),
      ),
    );
  });

  test(
    'receipt lookup rejects malformed confirmation and wrong operation',
    () async {
      final seen = <String>[];
      final auth = ClientAuth()..setSession({'id': 'alice'});
      final client = Client(
        'https://offline.invalid',
        auth: auth,
        transport: (input) async {
          seen.add(input['op'] as String);
          if (input['op'] == 'spec.commandReceipt') return {'confirmed': 'yes'};
          throw BackendNetworkException('uncertain', uncertain: true);
        },
      );
      addTearDown(client.close);
      await expectLater(
        client.request({
          'op': 'spec.generate',
          'appId': 'app',
          'operationId': 'someid',
          'expectedRevision': 0,
          'request': 'original',
          'startFromScratch': false,
        }),
        throwsA(isA<BackendNetworkException>()),
      );
      await expectLater(
        client.confirmRetainedBuilderCommand(
          appId: 'app',
          operation: 'spec.saveDraft',
          expectedRevision: 0,
          candidateHash: 'irrelevant',
        ),
        throwsA(
          isA<NestError>().having(
            (e) => e.category,
            'category',
            'pending_command',
          ),
        ),
      );
      expect(seen, ['spec.generate']);
      await expectLater(
        client.confirmRetainedBuilderCommand(
          appId: 'app',
          operation: 'spec.generate',
          expectedRevision: 0,
          request: 'original',
          startFromScratch: false,
        ),
        throwsA(
          isA<NestError>().having(
            (e) => e.category,
            'category',
            'invalid_response',
          ),
        ),
      );
      await expectLater(
        client.request({
          'op': 'spec.saveDraft',
          'appId': 'app',
          'operationId': 'different',
        }),
        throwsA(
          isA<NestError>().having(
            (e) => e.category,
            'category',
            'pending_command',
          ),
        ),
      );
    },
  );

  test('receipt lookup fails after builder access is revoked', () async {
    final f = Fixture();
    addTearDown(f.client.close);
    final (app, _) = await f.published();
    final workspace = (await f.client.apps.manifest(app)).workspaceId;
    final bob = f.forActor('bob');
    addTearDown(bob.close);
    final token = await f.client.apps.invite(app, 'builder', 'bob');
    await bob.apps.acceptInvitation(token);
    final draft = await bob.builder.begin(workspace, 'reading', app);
    final patch = {
      'type': 'RenameLabel',
      'targetId': 'title',
      'label': 'Private',
    };
    final expected = spec.AppSpec.parse(draft.candidateJson)
        .patch(patch, () => 'unused');
    f.loseNextOp = 'spec.saveDraft';
    await expectLater(
      bob.builder.patch(draft.draftId, draft.mutation, jsonEncode(patch)),
      throwsA(isA<BackendNetworkException>()),
    );
    await f.client.apps.members(app);
    await f.client.apps.setGrant(app, 'bob', null);
    await expectLater(
      bob.confirmRetainedBuilderCommand(
        appId: draft.draftId,
        operation: 'spec.saveDraft',
        expectedRevision: draft.mutation,
        candidateHash: expected.hash,
      ),
      throwsA(isA<NestError>()),
    );
  });

  test('session change fences a delayed receipt result', () async {
    final auth = ClientAuth()..setSession({'id': 'alice'});
    final reply = Completer<Map<String, dynamic>>();
    final started = Completer<void>();
    final client = Client(
      'https://offline.invalid',
      auth: auth,
      transport: (input) async {
        if (input['op'] == 'spec.commandReceipt') {
          started.complete();
          return reply.future;
        }
        throw BackendNetworkException('uncertain', uncertain: true);
      },
    );
    addTearDown(client.close);
    await expectLater(
      client.request({
        'op': 'spec.generate',
        'appId': 'app',
        'operationId': 'someid',
        'expectedRevision': 0,
        'request': 'original',
        'startFromScratch': false,
      }),
      throwsA(isA<BackendNetworkException>()),
    );
    final confirmation = client.confirmRetainedBuilderCommand(
      appId: 'app',
      operation: 'spec.generate',
      expectedRevision: 0,
      request: 'original',
      startFromScratch: false,
    );
    final assertion = expectLater(
      confirmation,
      throwsA(isA<BackendUnauthorized>()),
    );
    await started.future;
    auth.setSession({'id': 'bob'});
    reply.complete({'confirmed': true});
    await assertion;
  });

  test(
    'real service: original draft patch publication and record transport',
    () async {
      final f = Fixture();
      addTearDown(f.client.close);
      final (workspace, draft) = await f.draft();
      expect(draft.appId, isA<String>());
      expect(draft.candidateReady, isTrue);
      final changed = await f.client.builder.patch(
        draft.draftId,
        draft.mutation,
        jsonEncode({
          'type': 'RenameLabel',
          'targetId': 'title',
          'label': 'Book title',
        }),
      );
      expect(changed.mutation, draft.mutation + 1);
      final version = await f.client.builder.publish(
        PublishRequest(
          draftId: changed.draftId,
          candidateHash: changed.candidateHash,
          expectedCurrentVersionId: null,
          enabledRuleIds: [],
          activateExistingRecordIds: [],
          reviewHash: spec.hashJson({
            'candidateHash': changed.candidateHash,
            'enabledRuleIds': <String>[],
            'activateExistingRecordIds': <String>[],
          }),
          idempotencyKey: 'publish-exact',
        ),
      );
      final manifest = await f.client.apps.manifest(changed.appId);
      expect(manifest.versionId, version);
      expect(manifest.workspaceId, workspace);
      final outcome = await f.add(changed.appId, version);
      expect(outcome.message, 'Saved');
      expect(outcome.revision, 1);
      final record = await f.client.runtime.get(
        changed.appId,
        outcome.recordId,
      );
      expect(record.data['title'], 'A book');
      final page = await f.client.runtime.query(changed.appId, 'books', '{}');
      expect(page.total, 1);
      expect(page.records.single.id, outcome.recordId);
      final summary = await f.client.runtime.summary(
        changed.appId,
        'books',
        '{}',
        'status',
      );
      expect(summary.groups['Reading'], 1);
      final duplicate = await f.add(changed.appId, version);
      expect(duplicate.recordId, outcome.recordId);
      expect(f.store.rows['spec_records']!.length, 1);
      final patch = await f.client.runtime.execute(
        ActionRequest(
          appId: changed.appId,
          actionId: 'editBook',
          targetRecordId: record.id,
          expectedDefinitionVersionId: version,
          expectedRecordRevision: record.revision,
          input: {
            'data': {'notes': 'Offline edit'},
          },
          idempotencyKey: 'patch-once',
        ),
      );
      expect(patch.revision, 2);
      expect(
        (await f.client.runtime.get(changed.appId, record.id)).data['notes'],
        'Offline edit',
      );
      await expectLater(
        f.client.runtime.execute(
          ActionRequest(
            appId: changed.appId,
            actionId: 'editBook',
            targetRecordId: record.id,
            expectedDefinitionVersionId: version,
            expectedRecordRevision: record.revision,
            input: {
              'data': {'notes': 'Stale edit'},
            },
            idempotencyKey: 'stale-patch',
          ),
        ),
        throwsA(
          isA<NestError>().having(
            (e) => e.category,
            'code',
            'revision_conflict',
          ),
        ),
      );
      expect(f.calls.every((v) => !v.containsKey('actor')), isTrue);
    },
  );
  test('real service launcher accepts draft metadata and does not erase full manifests', () async {
    final f = Fixture();
    addTearDown(f.client.close);
    final (workspace, draft) = await f.draft();
    final listed = await f.client.apps.list(workspace);
    expect(listed.single.appId, draft.appId);
    expect(
      (await f.client.builder.get(draft.draftId)).candidateHash,
      draft.candidateHash,
    );
    final version = await f.client.builder.publish(
      PublishRequest(
        draftId: draft.draftId,
        candidateHash: draft.candidateHash,
        enabledRuleIds: [],
        activateExistingRecordIds: [],
        reviewHash: spec.hashJson({
          'candidateHash': draft.candidateHash,
          'enabledRuleIds': <String>[],
          'activateExistingRecordIds': <String>[],
        }),
        idempotencyKey: 'publish',
      ),
    );
    await f.client.apps.list(workspace);
    final before = f.calls.length;
    await f.client.runtime.query(draft.appId, 'books', '{}');
    expect(f.calls.length, before + 1);
    expect(f.calls.last['versionId'], version);
  });
  test(
    'real service multiple semantic patch allocations stay distinct',
    () async {
      final f = Fixture();
      addTearDown(f.client.close);
      final (_, draft) = await f.draft();
      final changed = await f.client.builder.patch(
        draft.draftId,
        draft.mutation,
        jsonEncode({
          'type': 'AddPage',
          'page': {'title': 'New page', 'layout': 'stacked', 'viewIds': []},
          'newViews': [
            {
              'type': 'list',
              'label': 'Books',
              'collectionId': 'books',
              'titleFieldId': 'title',
              'actionIds': [],
            },
            {
              'type': 'summary',
              'label': 'Overview',
              'collectionId': 'books',
              'groupByFieldId': 'status',
              'actionIds': [],
            },
          ],
        }),
      );
      final parsed = spec.AppSpec.parse(changed.candidateJson),
          page = parsed.navigation!.pages.last;
      expect(page.viewIds.length, 2);
      expect({page.id, ...page.viewIds}.length, 3);
    },
  );
  test(
    'real service lost committed record reply retries the exact operation once',
    () async {
      final f = Fixture();
      addTearDown(f.client.close);
      final (app, version) = await f.published();
      f.loseNextMutation = true;
      await expectLater(
        f.add(app, version, key: 'lost-reply'),
        throwsA(
          isA<BackendNetworkException>().having(
            (e) => e.uncertain,
            'uncertain',
            true,
          ),
        ),
      );
      final before = f.calls.last;
      final outcome = await f.add(app, version, key: 'lost-reply');
      expect(f.calls.last, before);
      expect(f.store.rows['spec_records']!.length, 1);
      expect(outcome.revision, 1);
    },
  );
  test(
    'real service sharing and revocation preserve current authorization',
    () async {
      final f = Fixture();
      addTearDown(f.client.close);
      final (app, version) = await f.published();
      final token = await f.client.apps.invite(app, 'viewer', 'bob'),
          bob = f.forActor('bob');
      addTearDown(bob.close);
      expect(await bob.apps.acceptInvitation(token), app);
      expect((await bob.apps.manifest(app)).role, 'viewer');
      await expectLater(
        bob.runtime.execute(
          ActionRequest(
            appId: app,
            actionId: 'addBook',
            expectedDefinitionVersionId: version,
            input: {'title': 'Unauthorized', 'status': 'Reading'},
            idempotencyKey: 'denied',
          ),
        ),
        throwsA(isA<NestError>().having((e) => e.status, 'status', 403)),
      );
      await f.client.apps.members(app);
      await f.client.apps.setGrant(app, 'bob', null);
      await expectLater(
        bob.apps.manifest(app),
        throwsA(isA<NestError>().having((e) => e.status, 'status', 404)),
      );
    },
  );
  test('real service media: chunk queued processing ready attachment and private reads', () async {
    final f = Fixture();
    addTearDown(f.client.close);
    final (app, version) = await f.published('photoJournal');
    final pixels = image.Image(width: 16, height: 8);
    image.fill(pixels, color: image.ColorRgb8(30, 100, 220));
    final bytes = Uint8List.fromList(image.encodePng(pixels));
    final definition = spec.AppSpec.parse(
      jsonEncode(f.clientManifest(app)['spec']),
    );
    final add = definition.actions.firstWhere(
      (a) => a.capability == 'records.create.v1',
    );
    final ticket = await f.client.media.beginUpload(
      MediaUploadRequest(
        appId: app,
        actionId: add.id,
        fieldId: 'photo',
        expectedDefinitionVersionId: version,
        byteLength: bytes.length,
        contentType: 'image/png',
        idempotencyKey: 'image-fixed',
      ),
    );
    final before = f.calls.length;
    expect(ticket.assetId, isEmpty);
    expect(f.calls.length, before);
    await f.client.media.uploadBytes(ticket, bytes);
    expect(ticket.assetId, isNotEmpty);
    await expectLater(
      f.client.media.completeUpload(app, ticket.assetId),
      throwsA(isA<BackendMediaProcessing>()),
    );
    await f.service.processMedia(ticket.assetId);
    final ready = await f.client.media.checkUpload(app, ticket.assetId);
    expect(ready.width, 16);
    expect(ready.height, 8);
    final record = await f.add(
      app,
      version,
      key: 'image-record',
      data: {'title': 'Synthetic photo', 'photo': ready.assetId},
    );
    expect(
      (await f.client.runtime.get(app, record.recordId)).data['photo'],
      ready.assetId,
    );
    final downloaded = await f.client.media.readImage(
      app,
      ready.assetId,
      'display',
    );
    expect(image.decodeImage(downloaded.buffer.asUint8List())!.width, 16);
    final outsider = f.forActor('mallory');
    addTearDown(outsider.close);
    await expectLater(
      outsider.media.readImage(app, ready.assetId, 'display'),
      throwsA(isA<NestError>().having((e) => e.status, 'status', 404)),
    );
  });
  test(
    'real service provider-off keeps valid draft and actual activity works',
    () async {
      final f = Fixture();
      addTearDown(f.client.close);
      final (_, draft) = await f.draft();
      await expectLater(
        f.client.builder.generate(
          draft.draftId,
          draft.mutation,
          'A useful app',
        ),
        throwsA(
          isA<NestError>().having(
            (e) => e.category,
            'code',
            'provider_unavailable',
          ),
        ),
      );
      expect(
        (await f.client.builder.get(draft.draftId)).candidateHash,
        draft.candidateHash,
      );
      expect(await f.client.apps.activity(draft.appId), isNotEmpty);
      expect(await f.client.builder.runs(draft.appId), isEmpty);
    },
  );
  test(
    'real service nonempty reminder state run history inbox and mark-read',
    () async {
      final f = Fixture();
      addTearDown(f.client.close);
      final (_, draft) = await f.draft('planner');
      const rules = ['taskReminder'];
      final version = await f.client.builder.publish(
        PublishRequest(
          draftId: draft.draftId,
          candidateHash: draft.candidateHash,
          enabledRuleIds: rules,
          activateExistingRecordIds: [],
          reviewHash: spec.hashJson({
            'candidateHash': draft.candidateHash,
            'enabledRuleIds': rules,
            'activateExistingRecordIds': <String>[],
          }),
          idempotencyKey: 'approve-reminder',
        ),
      );
      final task = await f.client.runtime.execute(
        ActionRequest(
          appId: draft.appId,
          actionId: 'addTask',
          expectedDefinitionVersionId: version,
          input: {
            'data': {
              'title': 'Synthetic due reminder',
              'status': 'Open',
              'reminderAt': DateTime.utc(2030).toIso8601String(),
            },
          },
          idempotencyKey: 'new-task',
        ),
      );
      await backend.WorkerEngine(f.service).reminders();
      final states = await f.client.runtime.reminderState(
        draft.appId,
        task.recordId,
      );
      expect(states.single.state, 'delivered');
      final runs = await f.client.builder.runs(draft.appId);
      expect(runs.single.status, 'succeeded');
      expect(runs.single.createdAt, DateTime.utc(2030));
      final inbox = await f.client.runtime.inbox();
      expect(inbox.single.recordId, task.recordId);
      expect(inbox.single.isRead, false);
      await f.client.runtime.readNotification(inbox.single.id);
      expect((await f.client.runtime.inbox()).single.isRead, true);
    },
  );
  test('real service queued and failed generation string diagnostics decode without Cloud', () async {
    final provider = OfflineRejectedProvider(), f = Fixture(provider: provider);
    addTearDown(f.client.close);
    final (_, draft) = await f.draft();
    final queued = await f.client.builder.generate(
      draft.draftId,
      draft.mutation,
      'Synthetic bounded request',
      startFromScratch: true,
    );
    expect(queued.stage, 'queued');
    expect(queued.candidateReady, isFalse);
    expect(queued.diagnostics, isEmpty);
    expect(queued.latestRequest, 'Synthetic bounded request');
    expect(queued.jobId, isNotNull);
    expect(provider.calls, 0);
    await backend.WorkerEngine(f.service).generate(queued.jobId!);
    final failed = await f.client.builder.get(draft.draftId);
    expect(failed.stage, 'failed');
    expect(
      failed.diagnostics.single,
      contains('Synthetic offline provider rejection'),
    );
    expect(failed.candidateReady, false);
    expect(provider.calls, 1);
    expect(failed.candidateHash, draft.candidateHash);
  });
  test(
    'failed edit retains its validated preview when outcome is indeterminate',
    () async {
      final provider = OfflineIndeterminateProvider(),
          f = Fixture(provider: provider);
      addTearDown(f.client.close);
      final (_, draft) = await f.draft();
      expect(draft.candidateReady, isTrue);
      final queued = await f.client.builder.generate(
        draft.draftId,
        draft.mutation,
        'Synthetic edit request',
        startFromScratch: false,
      );
      expect(queued.jobId, isNotNull);
      expect(queued.candidateReady, isTrue);
      expect(queued.candidateHash, draft.candidateHash);
      await backend.WorkerEngine(f.service).generate(queued.jobId!);
      final failed = await f.client.builder.get(draft.draftId);
      expect(failed.stage, 'failed');
      expect(failed.failureCategory, 'indeterminate');
      expect(failed.candidateReady, isTrue);
      expect(failed.candidateHash, draft.candidateHash);
      expect(failed.candidateJson, draft.candidateJson);
      expect(provider.calls, 1);
    },
  );

  test(
    'FIFO coalesces identical reads and cancels queued prior-session work',
    () async {
      final first = Completer<Map<String, dynamic>>(), calls = <String>[];
      final auth = ClientAuth()..setSession({'id': 'alice'});
      final client = Client(
        'https://offline.invalid',
        auth: auth,
        transport: (input) async {
          calls.add(input['op'] as String);
          return first.future;
        },
      );
      addTearDown(client.close);
      final one = client.request({'op': 'spec.capabilities'}),
          same = client.request({'op': 'spec.capabilities'});
      expect(identical(one, same), true);
      final queued = client.request({'op': 'spec.templates'});
      final oneCheck = expectLater(one, throwsA(isA<BackendUnauthorized>()));
      final queueCheck = expectLater(
        queued,
        throwsA(isA<BackendUnauthorized>()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(calls, ['spec.capabilities']);
      auth.setSession({'id': 'bob'});
      first.complete({'generation': false});
      await oneCheck;
      await queueCheck;
      expect(calls, ['spec.capabilities']);
    },
  );
  test(
    'late failed prior-session mutation cannot poison the new session',
    () async {
      final gate = Completer<Map<String, dynamic>>();
      var first = true;
      final auth = ClientAuth()..setSession({'id': 'alice'});
      final client = Client(
        'https://offline.invalid',
        auth: auth,
        transport: (input) async {
          if (first) {
            first = false;
            return gate.future;
          }
          return {'ok': true};
        },
      );
      addTearDown(client.close);
      final old = expectLater(
        client.request({'op': 'synthetic.write', 'operationId': 'old'}),
        throwsA(isA<BackendUnauthorized>()),
      );
      auth.setSession({'id': 'bob'});
      gate.completeError(
        BackendNetworkException('Synthetic late failure', uncertain: true),
      );
      await old;
      expect(
        await client.request({'op': 'synthetic.write', 'operationId': 'new'}),
        {'ok': true},
      );
    },
  );
  test(
    'budget freezes every route at exact function and account limits',
    () async {
      final budget = RequestBudget(
        maxFunctions: 2,
        maxAccounts: 1,
        maxMutations: 1,
      );
      final client = Client(
        'https://offline.invalid',
        budget: budget,
        transport: (input) async => {'ok': true},
      );
      addTearDown(client.close);
      await client.request({'op': 'spec.capabilities'});
      await client.request({'op': 'spec.templates'});
      await expectLater(
        client.request({'op': 'spec.capabilities'}),
        throwsA(
          isA<NestError>().having(
            (e) => e.category,
            'category',
            'request_budget',
          ),
        ),
      );
      expect(budget.functions, 2);
      expect(budget.stopped, true);
      expect(budget.account, throwsA(isA<NestError>()));
      expect(budget.accounts, 0);
      final auth = RequestBudget(maxAccounts: 1);
      auth.account();
      expect(auth.account, throwsA(isA<NestError>()));
      expect(auth.stopped, true);
    },
  );
  test(
    'quota or uncertain mutation stops a smoke budget without retries',
    () async {
      final budget = RequestBudget();
      var calls = 0;
      final client = Client(
        'https://offline.invalid',
        budget: budget,
        transport: (input) async {
          calls++;
          throw NestError(
            category: 'quota_exceeded',
            message: 'Synthetic quota',
            status: 429,
          );
        },
      );
      addTearDown(client.close);
      await expectLater(
        client.request({'op': 'spec.capabilities'}),
        throwsA(isA<NestError>()),
      );
      await expectLater(
        client.request({'op': 'spec.templates'}),
        throwsA(isA<NestError>()),
      );
      expect(calls, 1);
      expect(budget.stopped, true);
      final uncertain = RequestBudget();
      final other = Client(
        'https://offline.invalid',
        budget: uncertain,
        transport: (input) async => throw BackendNetworkException(
          'Synthetic lost reply',
          uncertain: true,
        ),
      );
      addTearDown(other.close);
      await expectLater(
        other.request({'op': 'synthetic.write', 'operationId': 'once'}),
        throwsA(isA<BackendNetworkException>()),
      );
      await expectLater(
        other.request({'op': 'synthetic.write', 'operationId': 'once'}),
        throwsA(isA<NestError>()),
      );
      expect(uncertain.functions, 1);
      expect(uncertain.stopped, true);
    },
  );
  test('unreadable successful mutation is uncertain and preserves exact retry payload', () async {
    var count = 0;
    final calls = <Map<String, dynamic>>[];
    final client = Client(
      'https://offline.invalid',
      transport: (input) async {
        calls.add(input);
        count++;
        return count == 1
            ? {}
            : {
                'outcome': {
                  'recordId': 'record',
                  'revision': 1,
                  'message': 'Saved',
                },
              };
      },
    );
    addTearDown(client.close);
    final request = ActionRequest(
      appId: 'app',
      actionId: 'add',
      expectedDefinitionVersionId: 'version',
      input: {'title': 'Retained'},
      idempotencyKey: 'same',
    );
    await expectLater(
      client.runtime.execute(request),
      throwsA(
        isA<BackendNetworkException>().having(
          (e) => e.uncertain,
          'uncertain',
          true,
        ),
      ),
    );
    expect((await client.runtime.execute(request)).recordId, 'record');
    expect(calls[0], calls[1]);
  });
  test('manual stream does not dispatch Cloud or poll while idle', () async {
    var requests = 0;
    final client = Client(
      'https://offline.invalid',
      transport: (input) async {
        requests++;
        return {};
      },
    );
    addTearDown(client.close);
    final subscription = client.runtime.events('app').listen((_) {});
    addTearDown(subscription.cancel);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(requests, 0);
  });
  test(
    'session restore coalesces and nullable models can explicitly clear IDs',
    () async {
      var restores = 0;
      final auth = ClientAuth(
        restore: () async {
          restores++;
          return {'id': 'alice', 'email': 'synthetic@example.test'};
        },
      );
      await Future.wait([
        auth.restore(),
        auth.restore(),
        auth.validateAuthentication(),
      ]);
      expect(restores, 1);
      expect(auth.actorId, 'alice');
      final value = AppManifest(
        appId: 'app',
        workspaceId: 'ws',
        name: 'Name',
        versionId: 'version',
        role: 'owner',
        archived: false,
        pinned: false,
        recordCount: 0,
        availablePlaces: 0,
      );
      expect(value.copyWith(versionId: null).versionId, isNull);
      expect(value.copyWith().versionId, 'version');
      auth.dispose();
    },
  );
}

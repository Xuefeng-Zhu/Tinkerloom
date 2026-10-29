import 'dart:convert';
import 'dart:io';
import 'package:appnest_spec/appnest_spec.dart' as spec;
import 'package:test/test.dart';
import '../tool/import/engine.dart';
import '../tool/import/format.dart';
import '../tool/import/replay.dart';

Json copy(Json value) => jsonDecode(jsonEncode(value)) as Json;
List<int> bytes(Object? value) => utf8.encode(jsonEncode(value));
late Json baseSource, baseMapping;
(List<int>, List<int>) inputs({
  void Function(Json)? source,
  void Function(Json)? mapping,
}) {
  final s = copy(baseSource);
  source?.call(s);
  final sb = bytes(s), m = copy(baseMapping)..['sourceSha256'] = digest(sb);
  mapping?.call(m);
  return (sb, bytes(m));
}

ImportPlan plan({void Function(Json)? source, void Function(Json)? mapping}) {
  final (s, m) = inputs(source: source, mapping: mapping);
  return planImport(s, m);
}

Matcher problem(String code) =>
    isA<ImportProblem>().having((e) => e.code, 'code', code);
Json table(Json s, String name, int index) => s['tables'][name][index] as Json;
void replaceDefinition(Json source, int index, void Function(Json) edit) {
  final row = table(source, 'versions', index),
      definition = jsonDecode(row['specJson']) as Json;
  edit(definition);
  final value = spec.AppSpec.parse(jsonEncode(definition));
  row['specJson'] = value.canonical;
  row['candidateHash'] = value.hash;
}

void count(Json source, String name) =>
    source['counts'][name] = (source['tables'][name] as List).length;
void main() {
  setUpAll(() {
    baseSource =
        jsonDecode(
              File(
                'test/fixtures/import/source.synthetic.json',
              ).readAsStringSync(),
            )
            as Json;
    baseMapping =
        jsonDecode(
              File(
                'test/fixtures/import/mapping.synthetic.json',
              ).readAsStringSync(),
            )
            as Json;
  });
  test(
    'three policy export creates complete deterministic core, capacity and projections',
    () {
      final p = plan();
      expect(p.validForSimulation, isTrue);
      expect(p.rows.length, 36);
      expect(p.rows.where((r) => r.table == 'spec_records').length, 3);
      expect(p.rows.where((r) => r.table == 'spec_versions').length, 4);
      expect(
        p.rows.where((r) => r.table == 'spec_pools').single.data['allocated'],
        1,
      );
      expect(
        p.rows.where((r) => r.table == 'spec_claims').single.data['actorId'],
        'qa-member',
      );
      expect(
        p.rows
            .where((r) => r.table == 'grants' && r.data['revoked'] == true)
            .length,
        1,
      );
      final chore = p.rows.singleWhere(
        (r) => r.table == 'spec_records' && r.data['collectionId'] == 'chores',
      );
      expect(jsonDecode(chore.data['dataJson'])['assignee'], 'qa-member');
      expect(
        p.rows
            .singleWhere(
              (r) => r.table == 'spec_values' && r.data['fieldId'] == 'dueAt',
            )
            .data['timestampValue'],
        '2026-10-28T12:00:00.123456Z',
      );
      expect(
        p.rows
            .singleWhere(
              (r) =>
                  r.table == 'spec_values' && r.data['fieldId'] == 'importNote',
            )
            .data['present'],
        false,
      );
      expect(plan().planSha256, p.planSha256);
      expect(p.report()['cutoverReady'], false);
      expect(
        p.rows.any(
          (r) => {
            'receipts',
            'automations',
            'worker_dispatch',
            'outbox',
            'media_assets',
          }.contains(r.table),
        ),
        false,
      );
      expect(p.quarantine.length, 3);
      expect(
        p.rows
            .where((r) => r.key.startsWith('activate/'))
            .every(
              (activation) => p.rows
                  .where((r) => r.data['appId'] == activation.id)
                  .every((r) => p.rows.indexOf(r) < p.rows.indexOf(activation)),
            ),
        true,
      );
    },
  );
  test(
    'source int64 IDs remain quoted and destination natural IDs match service',
    () {
      final p = plan();
      expect(
        p.rows.singleWhere((r) => r.table == 'workspaces').id,
        'qa-workspace',
      );
      expect(
        p.rows
            .singleWhere(
              (r) =>
                  r.table == 'memberships' && r.data['actorId'] == 'qa-member',
            )
            .id,
        identity('m', ['qa-workspace', 'qa-member']),
      );
      final version = p.rows.firstWhere((r) => r.table == 'spec_versions');
      expect(
        version.id,
        identity('v', [version.data['appId'], '${version.data['number']}']),
      );
      final record = p.rows.firstWhere((r) => r.table == 'spec_records');
      final field = p.rows.firstWhere(
        (r) => r.table == 'spec_values' && r.data['recordId'] == record.id,
      );
      expect(field.id, identity('f', [record.id, field.data['fieldId']]));
    },
  );
  test(
    'identity worksheet covers historical assignee without synthesizing grants',
    () {
      final (s, _) = inputs();
      final worksheet = identityWorksheet(s);
      expect(worksheet['accounts'], [
        {'sourceActorId': 'legacy|alice', 'targetAccountId': null},
        {'sourceActorId': 'legacy|bob', 'targetAccountId': null},
      ]);
      expect(
        () => planImport(s, bytes(worksheet)),
        throwsA(problem('invalid_text')),
      );
    },
  );
  test('missing account, workspace and merged identities fail closed', () {
    expect(
      () => plan(mapping: (m) => m['accounts'].removeLast()),
      throwsA(problem('unresolved_identity')),
    );
    expect(
      () => plan(mapping: (m) => m['workspaces'] = []),
      throwsA(problem('unresolved_workspace')),
    );
    expect(
      () => plan(
        mapping: (m) => m['accounts'][1]['targetAccountId'] = 'qa-owner',
      ),
      throwsA(problem('identity_merge_forbidden')),
    );
    expect(
      () => plan(
        mapping: (m) => m['accounts'].add({
          'sourceActorId': 'unused',
          'targetAccountId': 'unused',
        }),
      ),
      isNotNull,
    );
    expect(
      plan(
        mapping: (m) => m['accounts'].add({
          'sourceActorId': 'unused',
          'targetAccountId': 'unused',
        }),
      ).validForSimulation,
      false,
    );
  });
  test('mapping target rejects credentials and malformed endpoints', () {
    for (final url in [
      'http://localhost/v1',
      'https://name:secret@example.test/v1',
      'https://example.test/v1?key=secret',
      'https://example.test/v1#token',
      'https://example.test/not-api',
    ]) {
      expect(
        () => plan(mapping: (m) => m['target']['endpoint'] = url),
        throwsA(problem('invalid_target_endpoint')),
      );
    }
    expect(
      () => plan(mapping: (m) => m['target']['apiKey'] = 'not-a-real-key'),
      throwsA(problem('unknown_field')),
    );
  });
  test('raw source, counts and map are bound exactly including whitespace', () {
    final (s, m) = inputs();
    expect(
      () => planImport([...s, 32], m),
      throwsA(problem('source_binding_mismatch')),
    );
    expect(
      () => plan(source: (s) => s['counts']['records'] = 99),
      throwsA(problem('source_count_mismatch')),
    );
    expect(
      () => plan(source: (s) => s['consistentSnapshot'] = false),
      throwsA(problem('unsupported_export_contract')),
    );
  });
  test(
    'duplicate keys unknown tables secrets and numeric source IDs rejected',
    () {
      expect(
        () => decodeDocument(utf8.encode('{"x":1,"\\u0078":2}'), 'x'),
        throwsA(problem('duplicate_json_key')),
      );
      expect(
        () => decodeDocument(utf8.encode('{"a":{"x":1,"x":2}}'), 'x'),
        throwsA(problem('duplicate_json_key')),
      );
      expect(
        () => plan(source: (s) => s['tables']['authSessions'] = []),
        throwsA(problem('unknown_field')),
      );
      expect(
        () => plan(source: (s) => table(s, 'records', 0)['id'] = 1000),
        throwsA(problem('invalid_text')),
      );
      expect(
        () => plan(
          source: (s) => table(s, 'workspaces', 0)['ownerPassword'] = 'secret',
        ),
        throwsA(problem('unknown_field')),
      );
      expect(
        () => plan(
          source: (s) => table(s, 'apps', 0)['id'] = '9223372036854775808',
        ),
        throwsA(problem('invalid_source_id')),
      );
    },
  );
  test('strict parser enforces UTF8 finite numbers depth and byte limits', () {
    expect(() => decodeDocument([0xff], 'x'), throwsA(problem('invalid_utf8')));
    expect(
      () => decodeDocument(utf8.encode('{"x":1e999}'), 'x'),
      throwsA(problem('nonfinite_number')),
    );
    expect(
      () => decodeDocument(utf8.encode('{"x":${'[' * 66}0${']' * 66}}'), 'x'),
      throwsA(problem('json_depth_exceeded')),
    );
    expect(
      () => decodeDocument([123, 125], 'x', maxBytes: 1),
      throwsA(problem('file_size_limit')),
    );
  });
  test('foreign version record grant pool and claim parents rejected', () {
    expect(
      () => plan(
        source: (s) => table(s, 'records', 0)['writtenUnderVersionId'] = '101',
      ),
      throwsA(problem('cross_parent_reference')),
    );
    expect(
      () => plan(source: (s) => table(s, 'grants', 0)['workspaceId'] = '1'),
      throwsA(problem('cross_parent_reference')),
    );
    expect(
      () => plan(source: (s) => table(s, 'pools', 0)['recordId'] = '1000'),
      throwsA(problem('cross_parent_reference')),
    );
    expect(
      () => plan(source: (s) => table(s, 'claims', 0)['appId'] = '20'),
      throwsA(problem('cross_parent_reference')),
    );
    expect(
      () => plan(source: (s) => table(s, 'apps', 0)['activeVersionId'] = '101'),
      throwsA(problem('invalid_active_version')),
    );
  });
  test(
    'owner membership and active grants require explicit workspace membership',
    () {
      expect(
        () => plan(
          source: (s) {
            s['tables']['memberships'].removeAt(0);
            count(s, 'memberships');
          },
        ),
        throwsA(problem('owner_membership_missing')),
      );
      expect(
        () => plan(
          source: (s) {
            s['tables']['memberships'].removeAt(1);
            count(s, 'memberships');
          },
        ),
        throwsA(problem('grant_membership_missing')),
      );
      expect(
        () => plan(
          source: (s) => table(s, 'grants', 0)['actorId'] = 'legacy|alice',
        ),
        throwsA(problem('owner_grant_forbidden')),
      );
    },
  );
  test(
    'AppSpec hash unsupported capability and incompatible version history reject',
    () {
      expect(
        () => plan(
          source: (s) => table(s, 'versions', 0)['candidateHash'] = '0' * 64,
        ),
        throwsA(problem('definition_hash_mismatch')),
      );
      expect(
        () => plan(
          source: (s) {
            final row = table(s, 'versions', 0),
                j = jsonDecode(row['specJson']);
            j['requires'].add('execute.arbitraryCode');
            row['specJson'] = jsonEncode(j);
            row['candidateHash'] = hash(j);
          },
        ),
        throwsA(problem('invalid_appspec_or_record')),
      );
      expect(
        () => plan(
          source: (s) => replaceDefinition(
            s,
            3,
            (j) => j['collections'][0]['fields'].removeWhere(
              (f) => f['id'] == 'author',
            ),
          ),
        ),
        throwsA(problem('incompatible_version_history')),
      );
      expect(
        () => plan(source: (s) => table(s, 'versions', 3)['number'] = 3),
        throwsA(problem('version_sequence_gap')),
      );
    },
  );
  test(
    'record required fields unknown fields unsafe ints and timestamp rollover rejected',
    () {
      for (final edit in <void Function(Json)>[
        (r) => r['data'].remove('title'),
        (r) => r['data']['unknown'] = 'x',
        (r) => r['data']['rating'] = 9007199254740992,
      ]) {
        expect(
          () => plan(source: (s) => edit(table(s, 'records', 0))),
          throwsA(problem('invalid_appspec_or_record')),
        );
      }
      expect(
        () => plan(
          source: (s) =>
              table(s, 'records', 1)['data']['dueAt'] = '2026-02-30T10:00:00Z',
        ),
        throwsA(problem('invalid_appspec_or_record')),
      );
      expect(
        () => plan(
          source: (s) => table(s, 'records', 0)['data'] = {
            '__className': 'Map',
            'data': {'title': 'wrapped'},
          },
        ),
        throwsA(problem('invalid_appspec_or_record')),
      );
    },
  );
  test(
    'capacity exact allocation and unique claims are preserved including revoked actors',
    () {
      expect(
        () => plan(source: (s) => table(s, 'pools', 0)['allocated'] = 2),
        throwsA(problem('claim_allocation_mismatch')),
      );
      expect(
        () => plan(source: (s) => table(s, 'pools', 0)['capacity'] = 0),
        throwsA(problem('invalid_integer')),
      );
      expect(
        () => plan(
          source: (s) {
            s['tables']['pools'] = [];
            s['tables']['claims'] = [];
            count(s, 'pools');
            count(s, 'claims');
          },
        ),
        throwsA(problem('capacity_pool_missing')),
      );
      expect(
        () => plan(
          source: (s) {
            final c = copy(table(s, 'claims', 0))..['id'] = '2';
            s['tables']['claims'].add(c);
            count(s, 'claims');
          },
        ),
        throwsA(problem('duplicate_natural_key')),
      );
      final p = plan(source: (s) => table(s, 'grants', 1)['revoked'] = true);
      expect(
        p.rows.singleWhere((r) => r.table == 'spec_pools').data['allocated'],
        1,
      );
    },
  );
  test(
    'confirmed legacy receipt is quarantined and unknown outcome blocks replay',
    () {
      final p = plan();
      expect(
        p.quarantine.singleWhere((r) => r['kind'] == 'legacy_receipt')['state'],
        'confirmed',
      );
      expect(p.rows.any((r) => r.table == 'receipts'), false);
      final unknown = plan(
        source: (s) {
          final r = table(s, 'receipts', 0);
          r['state'] = 'unknown';
          r['recordId'] = null;
          r['revision'] = null;
        },
      );
      expect(unknown.validForSimulation, false);
      expect(
        () => Simulation(unknown),
        throwsA(problem('required_issues_block_replay')),
      );
      expect(
        () => plan(source: (s) => table(s, 'receipts', 0)['revision'] = 99),
        throwsA(problem('receipt_revision_ahead')),
      );
    },
  );
  test('pending commands and active generation cannot be auto-executed', () {
    final p = plan(
      source: (s) {
        s['tables']['pendingCommands'] = [
          {
            'id': '1',
            'appId': '10',
            'actorId': 'legacy|alice',
            'requestHash': hash('pending'),
            'state': 'unknown',
          },
        ];
        count(s, 'pendingCommands');
      },
    );
    expect(p.validForSimulation, false);
    expect(p.rows.any((r) => r.table == 'worker_dispatch'), false);
    final job = plan(
      source: (s) {
        s['tables']['jobs'] = [
          {
            'id': '1',
            'appId': '10',
            'draftId': '1',
            'actorId': 'legacy|alice',
            'status': 'generating',
            'mutation': 7,
            'contentSha256': hash('job'),
          },
        ];
        table(s, 'drafts', 0)['activeJobId'] = '1';
        count(s, 'jobs');
      },
    );
    expect(job.validForSimulation, false);
  });
  test('effects remain absent even when source approval enabled', () {
    final p = plan();
    expect(table(baseSource, 'automations', 0)['enabled'], true);
    expect(
      p.rows.any(
        (r) => {
          'automations',
          'reminder_runs',
          'notifications',
          'outbox',
          'worker_dispatch',
        }.contains(r.table),
      ),
      false,
    );
    expect(
      p.quarantine.any(
        (q) => q['kind'] == 'automation_disabled_at_destination',
      ),
      true,
    );
  });
  test(
    'candidate mutation starts an explicit new revision and consumed candidates bind exact hash',
    () {
      final p = plan();
      final draft = p.rows.singleWhere((r) => r.table == 'spec_drafts');
      expect(draft.data['revision'], 1);
      expect(draft.annotations['sourceMutation'], 7);
      final consumed = plan(
        source: (s) => table(s, 'drafts', 0)['publishedVersionId'] = '103',
      );
      expect(
        consumed.rows
            .singleWhere((r) => r.table == 'spec_drafts')
            .data['publishedVersionId'],
        isNotNull,
      );
      expect(
        () => plan(
          source: (s) => table(s, 'drafts', 0)['publishedVersionId'] = '100',
        ),
        throwsA(problem('consumed_candidate_mismatch')),
      );
    },
  );
  test(
    'historical author drafts explicitly block rather than silently discard',
    () {
      final p = plan(
        source: (s) {
          final old = copy(table(s, 'drafts', 0))..['id'] = '2';
          old['updatedAt'] = '2026-10-27T12:00:00.000Z';
          s['tables']['drafts'].add(old);
          count(s, 'drafts');
        },
      );
      expect(p.validForSimulation, false);
      expect(p.quarantine.any((q) => q['kind'] == 'historical_draft'), true);
      expect(p.rows.where((r) => r.table == 'spec_drafts').length, 1);
    },
  );
  test(
    'typed member query values are mapped and canonical version hashes recomputed',
    () {
      final p = plan(
        source: (s) => replaceDefinition(s, 1, (j) {
          j['requires'].add('views.configured.v1');
          j['views'][0]['query'] = {
            'filters': [
              {'fieldId': 'assignee', 'operator': 'eq', 'value': 'legacy|bob'},
            ],
          };
        }),
      );
      final version = p.rows.singleWhere(
        (r) =>
            r.table == 'spec_versions' &&
            (jsonDecode(r.data['specJson'])['policyPresetRequest'] ==
                'groupWorkflow.v1'),
      );
      final rewritten = spec.AppSpec.parse(version.data['specJson']);
      expect(rewritten.views.first.query!['filters'][0]['value'], 'qa-member');
      expect(version.data['hash'], rewritten.hash);
      expect(version.annotations['sourceSpecSha256'], isNot(rewritten.hash));
    },
  );
  test(
    'private media and historical references are validated but never fabricated as ready rows',
    () {
      Json mediaSource(Json s) {
        final asset = 'img_${'A' * 43}';
        for (final index in [0, 3]) {
          replaceDefinition(s, index, (j) {
            j['requires'].addAll([
              'fields.image.v1',
              'views.banner.v1',
              'views.configured.v1',
              'navigation.v1',
            ]);
            j['collections'][0]['fields'].add({
              'id': 'photo',
              'label': 'Photo',
              'type': 'image',
              'required': false,
            });
            j['views'].add({
              'id': 'cover',
              'type': 'banner',
              'label': 'Cover',
              'options': {
                'title': 'Synthetic cover',
                'imageAssetId': asset,
                'imageAlt': 'Synthetic image',
              },
            });
            j['navigation'] = {
              'entryPageId': 'home',
              'pages': [
                {
                  'id': 'home',
                  'title': 'Home',
                  'viewIds': [for (final view in j['views']) view['id']],
                },
              ],
              'tabs': [
                {'pageId': 'home', 'label': 'Home', 'icon': 'book'},
              ],
            };
          });
        }
        final draft = table(s, 'drafts', 0), version = table(s, 'versions', 3);
        draft['candidateJson'] = version['specJson'];
        draft['candidateHash'] = version['candidateHash'];
        table(s, 'records', 0)['data']['photo'] = asset;
        const time = '2026-10-28T12:00:00.000Z';
        s['tables']['media'] = [
          {
            'id': '1',
            'assetId': asset,
            'appId': '10',
            'workspaceId': '9007199254740993',
            'uploaderId': 'legacy|alice',
            'status': 'ready',
            'contentType': 'image/jpeg',
            'byteLength': 123,
            'storedBytes': 200,
            'width': 10,
            'height': 10,
            'originalRemoved': true,
            'createdAt': time,
            'updatedAt': time,
          },
        ];
        s['tables']['mediaReferences'] = [
          {
            'id': '1',
            'appId': '10',
            'assetRowId': '1',
            'draftId': null,
            'versionId': '100',
            'recordId': null,
          },
          {
            'id': '2',
            'appId': '10',
            'assetRowId': '1',
            'draftId': null,
            'versionId': '103',
            'recordId': null,
          },
          {
            'id': '3',
            'appId': '10',
            'assetRowId': '1',
            'draftId': '1',
            'versionId': null,
            'recordId': null,
          },
          {
            'id': '4',
            'appId': '10',
            'assetRowId': '1',
            'draftId': null,
            'versionId': null,
            'recordId': '1000',
          },
        ];
        count(s, 'media');
        count(s, 'mediaReferences');
        return s;
      }

      final p = plan(source: mediaSource);
      expect(p.validForSimulation, false);
      expect(
        p.issues.any((i) => i.code == 'media_binary_transfer_required'),
        true,
      );
      expect(p.rows.any((r) => r.table.startsWith('media')), false);
      expect(
        p.quarantine.where((q) => q['kind'] == 'media_reference').length,
        4,
      );
      expect(
        () => plan(
          source: (s) {
            mediaSource(s);
            table(s, 'media', 0)['appId'] = '20';
          },
        ),
        throwsA(problem('cross_parent_media_reference')),
      );
      expect(
        () => plan(
          source: (s) {
            mediaSource(s);
            s['tables']['mediaReferences'].removeLast();
            count(s, 'mediaReferences');
          },
        ),
        throwsA(problem('media_reference_set_mismatch')),
      );
      expect(
        () => plan(
          source: (s) {
            mediaSource(s);
            table(s, 'mediaReferences', 0)['draftId'] = '1';
          },
        ),
        throwsA(problem('media_reference_owner_cardinality')),
      );
      expect(
        () => plan(
          source: (s) {
            mediaSource(s);
            table(s, 'media', 0)['uploadDescription'] = 'credential';
          },
        ),
        throwsA(problem('unknown_field')),
      );
    },
  );
  test(
    'actual legacy generation and issuing media states remain explicit quarantine',
    () {
      for (final state in [
        'queued',
        'generating',
        'validating',
        'preview ready',
        'stale',
        'failed',
      ]) {
        final p = plan(
          source: (s) {
            s['tables']['jobs'] = [
              {
                'id': '1',
                'appId': '10',
                'draftId': '1',
                'actorId': 'legacy|alice',
                'status': state,
                'mutation': 7,
                'contentSha256': hash('synthetic job'),
              },
            ];
            count(s, 'jobs');
          },
        );
        expect(
          p.quarantine.singleWhere(
            (q) => q['kind'] == 'generation_job',
          )['state'],
          state,
        );
        expect(
          p.validForSimulation,
          !{'queued', 'generating', 'validating'}.contains(state),
        );
      }
      final media = plan(
        source: (s) {
          const t = '2026-10-28T12:00:00.000Z';
          s['tables']['media'] = [
            {
              'id': '1',
              'assetId': 'img_${'A' * 43}',
              'appId': '10',
              'workspaceId': '9007199254740993',
              'uploaderId': 'legacy|alice',
              'status': 'issuing',
              'contentType': 'image/png',
              'byteLength': 10,
              'storedBytes': 0,
              'width': 0,
              'height': 0,
              'originalRemoved': false,
              'createdAt': t,
              'updatedAt': t,
            },
          ];
          count(s, 'media');
        },
      );
      expect(media.validForSimulation, false);
      expect(
        media.quarantine.singleWhere(
          (q) => q['kind'] == 'media_metadata',
        )['state'],
        'issuing',
      );
    },
  );
  test('unknown archived history state is fingerprinted but never echoed', () {
    const marker = 'private_untrusted_marker';
    final p = plan(source: (s) => table(s, 'history', 0)['state'] = marker);
    expect(p.validForSimulation, false);
    expect(jsonEncode(p.report()).contains(marker), false);
    expect(
      p.quarantine.singleWhere((q) => q['kind'] == 'audit')['state'],
      'unknown',
    );
  });
  test(
    'source and expanded operation budgets fail closed before unbounded planning',
    () {
      expect(
        () => plan(
          source: (s) {
            s['tables']['history'] = List.generate(
              5001,
              (i) => {
                'id': '${i + 1}',
                'appId': '10',
                'kind': 'audit',
                'state': 'terminal',
                'contentSha256': hash('history'),
              },
            );
            count(s, 'history');
          },
        ),
        throwsA(problem('source_row_budget_exceeded')),
      );
      expect(
        () => plan(
          source: (s) {
            final version = table(s, 'versions', 0),
                j = jsonDecode(version['specJson']) as Json;
            for (var i = 0; i < 30; i++) {
              j['collections'][0]['fields'].add({
                'id': 'extra$i',
                'label': 'Extra $i',
                'type': 'text',
                'required': false,
              });
            }
            final v = spec.AppSpec.parse(jsonEncode(j));
            version['specJson'] = v.canonical;
            version['candidateHash'] = v.hash;
            // Keep one version, no private candidate, and many valid projection rows.
            s['tables']['versions'] = [version];
            s['tables']['apps'] = [
              table(s, 'apps', 0)..['activeVersionId'] = '100',
            ];
            s['tables']['grants'] = [];
            s['tables']['drafts'] = [];
            s['tables']['pools'] = [];
            s['tables']['claims'] = [];
            s['tables']['automations'] = [];
            final record = table(s, 'records', 0);
            s['tables']['records'] = List.generate(
              1400,
              (i) => copy(record)..['id'] = '${1000 + i}',
            );
            for (final name in [
              'versions',
              'apps',
              'grants',
              'drafts',
              'pools',
              'claims',
              'automations',
              'records',
            ]) {
              count(s, name);
            }
          },
        ),
        throwsA(problem('planned_operation_budget_exceeded')),
      );
    },
  );
  test(
    'all twelve supported canonical original fixtures produce validated structure plans',
    () {
      final directory = Directory('packages/appnest_spec/fixtures');
      final fixtures = directory
          .listSync()
          .whereType<File>()
          .where(
            (f) =>
                f.path.endsWith('.json') &&
                !f.path.endsWith('unsupported.json'),
          )
          .toList();
      expect(fixtures.length, 12);
      for (final fixture in fixtures) {
        final definition = spec.AppSpec.parse(fixture.readAsStringSync());
        final p = plan(
          source: (s) {
            for (final name in tables) {
              if (!{
                'workspaces',
                'memberships',
                'apps',
                'versions',
              }.contains(name))
                s['tables'][name] = [];
            }
            s['tables']['memberships'] = [table(s, 'memberships', 0)];
            final app = table(s, 'apps', 0)..['activeVersionId'] = '100';
            s['tables']['apps'] = [app];
            final version = table(s, 'versions', 0)
              ..['specJson'] = definition.canonical
              ..['candidateHash'] = definition.hash;
            s['tables']['versions'] = [version];
            for (final name in tables) {
              count(s, name);
            }
          },
          mapping: (m) => m['accounts'].removeLast(),
        );
        expect(p.validForSimulation, true, reason: fixture.path);
        expect(
          p.rows.singleWhere((r) => r.table == 'spec_versions').data['hash'],
          definition.hash,
        );
      }
    },
  );
  test(
    'existing workspace simulation requires an exact owner assertion and never overwrites name',
    () {
      final p = plan(
        mapping: (m) => m['workspaces'][0]['disposition'] = 'existing',
      );
      expect(p.validForSimulation, true);
      expect(
        () => Simulation(p)..advance(),
        throwsA(problem('simulated_existing_workspace_mismatch')),
      );
      final existing = {
        'workspaces/qa-workspace': <String, dynamic>{
          'ownerId': 'qa-owner',
          'name': 'Existing destination name',
        },
      };
      final simulation = Simulation(
        p,
        destination: SimulatedRows(existing: existing),
      );
      simulation.advance(maxOperations: 10000);
      expect(simulation.complete, true);
      expect(
        simulation.destination.read('workspaces', 'qa-workspace')!['name'],
        'Existing destination name',
      );
      expect(
        () => Simulation(
          p,
          destination: SimulatedRows(
            existing: {
              'workspaces/qa-workspace': {'ownerId': 'other'},
            },
          ),
        )..advance(),
        throwsA(problem('simulated_existing_workspace_mismatch')),
      );
    },
  );
  test(
    'metadata precision is rejected explicitly rather than silently rounded',
    () {
      expect(
        () => plan(
          source: (s) => table(s, 'records', 0)['createdAt'] =
              '2026-10-28T12:00:00.123456Z',
        ),
        throwsA(problem('metadata_timestamp_requires_utc_milliseconds')),
      );
      expect(
        () => plan(
          source: (s) =>
              table(s, 'records', 0)['createdAt'] = '2026-02-30T12:00:00.000Z',
        ),
        throwsA(problem('invalid_timestamp')),
      );
    },
  );
  test(
    'full simulation, exact retries and interrupted resume converge to same snapshot',
    () {
      final p = plan(), whole = Simulation(plan());
      whole.advance(maxOperations: 10000);
      expect(whole.complete, true);
      expect(whole.destination.count, 33);
      final partial = Simulation(p);
      expect(partial.advance(maxOperations: 7), 7);
      final resumed = Simulation(p, resume: copy(partial.ledger));
      expect(resumed.confirmed, 7);
      resumed.advance(maxOperations: 10000);
      expect(resumed.destination.checksum, whole.destination.checksum);
      for (final op in p.rows) {
        resumed.destination.apply(op);
      }
      expect(resumed.destination.checksum, whole.destination.checksum);
      expect(Simulation(p, resume: resumed.ledger).complete, true);
    },
  );
  test(
    'resume rejects different source mapping target plan and corrupt progress',
    () {
      final p = plan(),
          sim = Simulation(plan())..advance(maxOperations: 4),
          ledger = sim.ledger;
      final sourceChanged = plan(
        source: (s) => table(s, 'apps', 0)['name'] = 'changed',
      );
      expect(
        () => Simulation(sourceChanged, resume: ledger),
        throwsA(problem('resume_binding_mismatch')),
      );
      final actorChanged = plan(
        mapping: (m) => m['accounts'][1]['targetAccountId'] = 'another-account',
      );
      expect(
        () => Simulation(actorChanged, resume: ledger),
        throwsA(problem('resume_binding_mismatch')),
      );
      final foreign = plan(
        mapping: (m) => m['target']['projectId'] = 'foreign-project',
      );
      expect(
        () => Simulation(foreign, resume: ledger),
        throwsA(problem('resume_binding_mismatch')),
      );
      final tampered = copy(ledger);
      tampered['entries'][0]['payloadSha256'] = '0' * 64;
      expect(
        () => Simulation(p, resume: tampered),
        throwsA(problem('ledger_checksum_mismatch')),
      );
      tampered['ledgerSha256'] = hash({...tampered}..remove('ledgerSha256'));
      expect(
        () => Simulation(p, resume: tampered),
        throwsA(problem('invalid_ledger_progress')),
      );
    },
  );
  test(
    'unknown simulated step stays unknown across restart and cannot be advanced',
    () {
      final p = plan(), sim = Simulation(plan())..advance(maxOperations: 5);
      sim.markNextUnknown();
      final resumed = Simulation(p, resume: sim.ledger);
      expect(resumed.confirmed, 5);
      expect(resumed.uncertain, true);
      expect(
        () => resumed.advance(),
        throwsA(problem('unknown_progress_requires_reconciliation')),
      );
      expect(resumed.ledger['entries'].last['state'], 'unknown');
    },
  );
  test(
    'simulated collisions never overwrite foreign rows or changed operation payloads',
    () {
      final p = plan(), first = p.rows.first;
      final foreign = SimulatedRows(
        existing: {
          '${first.table}/${first.id}': {'ownerId': 'foreign'},
        },
      );
      expect(
        () => foreign.apply(first),
        throwsA(problem('simulated_destination_collision')),
      );
      final store = SimulatedRows()..apply(first);
      final changed = PlannedRow(first.key, first.mode, first.table, first.id, {
        ...first.data,
        'name': 'changed',
      }, first.dependencies);
      expect(
        () => store.apply(changed),
        throwsA(problem('simulated_operation_conflict')),
      );
    },
  );
  test(
    'report and ledger contain fingerprints not source record values or receipt keys',
    () {
      final p = plan(), sim = Simulation(plan())..advance(maxOperations: 10000);
      final output = jsonEncode([p.report(), sim.ledger]);
      for (final forbidden in [
        'Synthetic book',
        'Synthetic chore',
        'old private command key',
        'candidateJson',
        'specJson',
        'dataJson',
      ]) {
        expect(output.contains(forbidden), false, reason: forbidden);
      }
    },
  );
  test(
    'CLI rejects admin keys/apply and output overwrite, produces bounded simulation report',
    () async {
      Future<ProcessResult> run(List<String> args) => Process.run(
        Platform.resolvedExecutable,
        ['--suppress-analytics', 'run', 'tool/import/main.dart', ...args],
      );
      for (final flag in [
        '--api-key',
        '--admin-key',
        '--apply',
        '--endpoint',
      ]) {
        final r = await run([flag, 'forbidden']);
        expect(r.exitCode, 64);
        expect(r.stdout, '');
        expect(r.stderr.toString().contains('forbidden'), false);
      }
      final temp = Directory.systemTemp.createTempSync(
        'tinkerloom-import-cli-',
      );
      addTearDown(() => temp.deleteSync(recursive: true));
      final args = [
        '--source',
        'test/fixtures/import/source.synthetic.json',
        '--mapping',
        'test/fixtures/import/mapping.synthetic.json',
        '--simulate',
        '7',
        '--ledger-out',
        '${temp.path}/ledger.json',
        '--report',
        '${temp.path}/report.json',
      ];
      final first = await run(args);
      expect(first.exitCode, 0, reason: '${first.stderr}');
      final output = jsonDecode(first.stdout as String);
      expect(output['liveWrites'], 0);
      expect(output['simulation']['confirmed'], 7);
      final before = File('${temp.path}/ledger.json').readAsBytesSync();
      final second = await run(args);
      expect(second.exitCode, 74);
      expect(File('${temp.path}/ledger.json').readAsBytesSync(), before);
      final worksheet = await run([
        '--source',
        'test/fixtures/import/source.synthetic.json',
        '--worksheet',
        '${temp.path}/map.json',
      ]);
      expect(worksheet.exitCode, 0);
      expect(jsonDecode(worksheet.stdout as String)['unresolvedAccounts'], 2);
    },
  );
}

// Deterministic SYNTHETIC export only. Never reads a server/database or secrets.
import 'dart:convert';
import 'dart:io' show File;
import 'package:appnest_spec/appnest_spec.dart' as spec;
import 'engine.dart';
import 'format.dart';

void main() {
  const time = '2026-10-28T12:00:00.000Z';
  final source = <String, dynamic>{
    'format': 'appnest.offline-export.v1',
    'sourceInstanceId': 'synthetic-legacy',
    'snapshotId': 'synthetic-2026-10-28',
    'exportedAt': time,
    'consistentSnapshot': true,
    'dataEncoding': 'serverpod-unwrapped-json.v1',
    'sourceArchive': {
      'sha256': digest(utf8.encode('synthetic archive only')),
      'byteLength': 22,
    },
    'counts': <String, dynamic>{},
    'tables': <String, dynamic>{for (final t in tables) t: <Json>[]},
  };
  final t = source['tables'] as Json;
  t['workspaces'] = [
    {
      'id': '9007199254740993',
      'name': 'Synthetic QA',
      'ownerId': 'legacy|alice',
      'personal': true,
      'createdAt': time,
    },
  ];
  t['memberships'] = [
    {
      'id': '1',
      'workspaceId': '9007199254740993',
      'actorId': 'legacy|alice',
      'role': 'owner',
    },
    {
      'id': '2',
      'workspaceId': '9007199254740993',
      'actorId': 'legacy|bob',
      'role': 'member',
    },
  ];
  var versionId = 100;
  final versions = <Json>[];
  for (final entry in {
    '10': 'reading',
    '20': 'chores',
    '30': 'volunteer',
  }.entries) {
    final app = spec.starterTemplates()[entry.value]!;
    final v = '${versionId++}';
    (t['apps'] as List).add({
      'id': entry.key,
      'workspaceId': '9007199254740993',
      'ownerId': 'legacy|alice',
      'name': app.name,
      'activeVersionId': v,
      'archived': false,
      'controlRevision': 9,
      'createdAt': time,
    });
    versions.add({
      'id': v,
      'appId': entry.key,
      'workspaceId': '9007199254740993',
      'number': 1,
      'specJson': app.canonical,
      'candidateHash': app.hash,
      'publisherId': 'legacy|alice',
      'createdAt': time,
    });
  }
  final evolved =
      jsonDecode(spec.starterTemplates()['reading']!.canonical) as Json;
  (evolved['collections'][0]['fields'] as List).add({
    'id': 'importNote',
    'label': 'Import note',
    'type': 'text',
    'required': false,
  });
  final second = spec.AppSpec.parse(jsonEncode(evolved));
  versions.add({
    'id': '103',
    'appId': '10',
    'workspaceId': '9007199254740993',
    'number': 2,
    'specJson': second.canonical,
    'candidateHash': second.hash,
    'publisherId': 'legacy|alice',
    'createdAt': time,
  });
  t['apps'][0]['activeVersionId'] = '103';
  t['versions'] = versions;
  t['grants'] = [
    {
      'id': '1',
      'appId': '20',
      'workspaceId': '9007199254740993',
      'actorId': 'legacy|bob',
      'role': 'member',
      'revoked': true,
    },
    {
      'id': '2',
      'appId': '30',
      'workspaceId': '9007199254740993',
      'actorId': 'legacy|bob',
      'role': 'member',
      'revoked': false,
    },
  ];
  t['shortcuts'] = [
    {'id': '1', 'appId': '10', 'actorId': 'legacy|alice'},
  ];
  t['drafts'] = [
    {
      'id': '1',
      'appId': '10',
      'workspaceId': '9007199254740993',
      'actorId': 'legacy|alice',
      'baseVersionId': '103',
      'candidateJson': second.canonical,
      'candidateHash': second.hash,
      'mutation': 7,
      'activeJobId': null,
      'publishedVersionId': null,
      'updatedAt': time,
    },
  ];
  t['records'] = [
    {
      'id': '1000',
      'appId': '10',
      'workspaceId': '9007199254740993',
      'collectionId': 'books',
      'data': {'title': 'Synthetic book', 'status': 'Reading', 'rating': 4},
      'creatorId': 'legacy|alice',
      'revision': 3,
      'writtenUnderVersionId': '100',
      'createdAt': time,
      'updatedAt': time,
      'deleted': false,
    },
    {
      'id': '2000',
      'appId': '20',
      'workspaceId': '9007199254740993',
      'collectionId': 'chores',
      'data': {
        'title': 'Synthetic chore',
        'status': 'Doing',
        'assignee': 'legacy|bob',
        'dueAt': '2026-10-28T12:00:00.123456Z',
      },
      'creatorId': 'legacy|alice',
      'revision': 2,
      'writtenUnderVersionId': '101',
      'createdAt': time,
      'updatedAt': time,
      'deleted': false,
    },
    {
      'id': '3000',
      'appId': '30',
      'workspaceId': '9007199254740993',
      'collectionId': 'shifts',
      'data': {
        'title': 'Synthetic shift',
        'startsAt': '2026-11-01T10:00:00.000Z',
      },
      'creatorId': 'legacy|alice',
      'revision': 1,
      'writtenUnderVersionId': '102',
      'createdAt': time,
      'updatedAt': time,
      'deleted': false,
    },
  ];
  t['pools'] = [
    {
      'id': '1',
      'appId': '30',
      'workspaceId': '9007199254740993',
      'recordId': '3000',
      'behaviorId': 'places',
      'capacity': 3,
      'allocated': 1,
    },
  ];
  t['claims'] = [
    {
      'id': '1',
      'appId': '30',
      'workspaceId': '9007199254740993',
      'poolId': '1',
      'actorId': 'legacy|bob',
      'active': true,
      'createdAt': time,
      'updatedAt': time,
    },
  ];
  t['receipts'] = [
    {
      'id': '1',
      'appId': '10',
      'actorId': 'legacy|alice',
      'idempotencyKeySha256': hash('old private command key'),
      'requestHash': hash('old request'),
      'outcomeSha256': hash({
        'recordId': 1000,
        'revision': 3,
        'message': 'Saved',
      }),
      'recordId': '1000',
      'revision': 3,
      'state': 'confirmed',
    },
  ];
  t['automations'] = [
    {
      'id': '1',
      'appId': '20',
      'workspaceId': '9007199254740993',
      'ruleId': 'dueReminder',
      'enabled': true,
      'executionActorId': 'legacy|alice',
      'ruleSha256': hash(
        spec.starterTemplates()['chores']!.automationRequests.single.toJson(),
      ),
    },
  ];
  t['history'] = [
    {
      'id': '1',
      'appId': '10',
      'kind': 'audit',
      'state': 'terminal',
      'contentSha256': hash('synthetic audit'),
    },
  ];
  source['counts'] = {for (final key in tables) key: (t[key] as List).length};
  const encoder = JsonEncoder.withIndent('  ');
  final sourceBytes = utf8.encode('${encoder.convert(source)}\n');
  final mapping = {
    'format': 'tinkerloom.identity-map.v1',
    'sourceInstanceId': source['sourceInstanceId'],
    'sourceSha256': digest(sourceBytes),
    'target': {
      'endpoint': 'https://appwrite.invalid/v1',
      'projectId': 'synthetic-project',
      'databaseId': 'tinkerloom',
      'operatorAccountId': 'qa-owner',
    },
    'accounts': [
      {'sourceActorId': 'legacy|alice', 'targetAccountId': 'qa-owner'},
      {'sourceActorId': 'legacy|bob', 'targetAccountId': 'qa-member'},
    ],
    'workspaces': [
      {
        'sourceWorkspaceId': '9007199254740993',
        'targetWorkspaceId': 'qa-workspace',
        'disposition': 'create',
      },
    ],
  };
  File(
    'test/fixtures/import/source.synthetic.json',
  ).writeAsBytesSync(sourceBytes);
  File(
    'test/fixtures/import/mapping.synthetic.json',
  ).writeAsStringSync('${encoder.convert(mapping)}\n');
}

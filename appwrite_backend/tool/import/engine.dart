// Read-only import planner. This library deliberately has no dart:io, backend
// service, RowStore, HTTP, authentication or credential imports.
import 'dart:convert';
import 'dart:collection';
import 'package:appnest_spec/appnest_spec.dart' as spec;
import 'format.dart';
export 'format.dart' show ImportProblem;

typedef Issue = ({String code, String path, bool required});
const tables = <String>[
  'workspaces',
  'memberships',
  'apps',
  'grants',
  'shortcuts',
  'versions',
  'drafts',
  'records',
  'pools',
  'claims',
  'receipts',
  'pendingCommands',
  'media',
  'mediaReferences',
  'automations',
  'jobs',
  'history',
];
const _fields = <String, String>{
  'workspaces': 'id name ownerId personal createdAt',
  'memberships': 'id workspaceId actorId role',
  'apps':
      'id workspaceId ownerId name activeVersionId archived controlRevision createdAt',
  'grants': 'id appId workspaceId actorId role revoked',
  'shortcuts': 'id appId actorId',
  'versions':
      'id appId workspaceId number specJson candidateHash publisherId createdAt',
  'drafts':
      'id appId workspaceId actorId baseVersionId candidateJson candidateHash mutation activeJobId publishedVersionId updatedAt',
  'records':
      'id appId workspaceId collectionId data creatorId revision writtenUnderVersionId createdAt updatedAt deleted',
  'pools': 'id appId workspaceId recordId behaviorId capacity allocated',
  'claims': 'id appId workspaceId poolId actorId active createdAt updatedAt',
  // Receipt keys/outcomes are explicitly fingerprinted, not new-platform keys.
  'receipts':
      'id appId actorId idempotencyKeySha256 requestHash outcomeSha256 recordId revision state',
  'pendingCommands': 'id appId actorId requestHash state',
  // No uploadDescription, original upload credentials or file URLs are legal.
  'media':
      'id assetId appId workspaceId uploaderId status contentType byteLength storedBytes width height originalRemoved createdAt updatedAt',
  'mediaReferences': 'id appId assetRowId draftId versionId recordId',
  'automations':
      'id appId workspaceId ruleId enabled executionActorId ruleSha256',
  'jobs': 'id appId draftId actorId status mutation contentSha256',
  // Read-only archive fingerprints for audit, inbox, runs and outbox history.
  'history': 'id appId kind state contentSha256',
};

class PlannedRow {
  final String key, mode, table, id;
  final Json data;
  final List<String> dependencies;
  final Json annotations;
  PlannedRow(
    this.key,
    this.mode,
    this.table,
    this.id,
    this.data,
    this.dependencies, [
    this.annotations = const {},
  ]);
  String get payloadSha256 => hash(data);
  Json get descriptor => {
    'key': key,
    'mode': mode,
    'table': table,
    'id': id,
    'payloadSha256': payloadSha256,
    'dependencies': dependencies,
    if (annotations.isNotEmpty) 'annotations': annotations,
  };
}

class ImportPlan {
  final String sourceSha256, mappingSha256, targetSha256;
  final Json target;
  final List<PlannedRow> rows;
  final List<Issue> issues;
  final Json sourceCounts;
  final Json destinationIdentities;
  final List<Json> quarantine;
  ImportPlan(
    this.sourceSha256,
    this.mappingSha256,
    this.targetSha256,
    this.target,
    this.rows,
    this.issues,
    this.sourceCounts,
    this.quarantine,
    this.destinationIdentities,
  );
  bool get validForSimulation => !issues.any((i) => i.required);
  String get planSha256 => hash({
    'format': 'tinkerloom.offline-plan.v1',
    'sourceSha256': sourceSha256,
    'mappingSha256': mappingSha256,
    'targetSha256': targetSha256,
    'operations': rows.map((r) => r.descriptor).toList(),
    'quarantine': quarantine,
    'destinationIdentities': destinationIdentities,
  });
  Json report() => {
    'format': 'tinkerloom.offline-plan.v1',
    'mode': 'offline_dry_run',
    'cutoverReady': false,
    'validForSimulation': validForSimulation,
    'sourceSha256': sourceSha256,
    'mappingSha256': mappingSha256,
    'targetSha256': targetSha256,
    'planSha256': planSha256,
    'sourceCounts': sourceCounts,
    'destinationIdentities': destinationIdentities,
    'plannedCounts': {
      for (final t in rows.map((r) => r.table).toSet().toList()..sort())
        t: rows.where((r) => r.table == t).map((r) => r.id).toSet().length,
    },
    'plannedOperationCounts': {
      for (final t in rows.map((r) => r.table).toSet().toList()..sort())
        t: rows.where((r) => r.table == t).length,
    },
    'issues': [
      for (final i in issues)
        {'code': i.code, 'path': i.path, 'required': i.required},
    ],
    'operations': rows.map((r) => r.descriptor).toList(),
    'quarantine': quarantine,
    'remainingGates': [
      'authorized_consistent_source_export',
      'source_writer_worker_quiescence_and_pending_command_inventory',
      'remote_target_identity_and_access',
      'existing_target_collision_and_quota_inventory',
      'source_createdAt_launcher_order_strategy',
      'approved_write_runner_and_backup_restore',
      'legacy_receipt_and_pending_command_reconciliation',
      'media_binary_transfer_resanitization_and_references',
      'effect_and_job_quarantine_no_enrollment',
      'actual_counts_checksums_restart_and_rollback_proof',
      'bounded_engine_preservation_separate_from_appspec_import',
    ],
  };
}

ImportPlan planImport(List<int> sourceBytes, List<int> mappingBytes) =>
    _Planner(sourceBytes, mappingBytes).run();

class _Planner {
  final List<int> sourceBytes, mappingBytes;
  late Json source, mapping, target;
  final data = <String, List<Json>>{};
  final byId = <String, Map<String, Json>>{};
  final actors = <String, String>{}, workspaces = <String, String>{};
  final workspaceModes = <String, String>{};
  final ids = <String, Map<String, String>>{};
  final definitions = <String, spec.AppSpec>{};
  final transformed = <String, spec.AppSpec>{};
  final rows = <PlannedRow>[];
  final operationKeys = <String>{};
  final issues = <Issue>[];
  final quarantine = <Json>[];
  final usedAccounts = <String>{};
  final usedWorkspaces = <String>{};
  late String scope;
  _Planner(this.sourceBytes, this.mappingBytes);

  void issue(String code, String path, {bool required = true}) =>
      issues.add((code: code, path: path, required: required));
  T guard<T>(String path, T Function() body) {
    try {
      return body();
    } on spec.SpecException {
      bad('invalid_appspec_or_record', path);
    }
  }

  Json reference(String table, Object? id, String path) {
    final key = oldId(id, path);
    return byId[table]?[key] ?? (bad('missing_reference', path));
  }

  String mappedActor(Object? raw, String path) {
    final actor = text(raw, path, max: 100);
    usedAccounts.add(actor);
    final mapped = actors[actor];
    if (mapped == null) bad('unresolved_identity', path);
    return mapped;
  }

  String ws(Object? raw, String path) {
    final id = oldId(raw, path);
    reference('workspaces', id, path);
    usedWorkspaces.add(id);
    return workspaces[id] ?? (bad('unresolved_workspace', path));
  }

  String dest(String table, Object? id, String path) {
    final value = reference(table, id, path);
    return ids[table]![value['id']]!;
  }

  void parent(Json row, String path) {
    final app = reference('apps', row['appId'], '$path.appId');
    if (row.containsKey('workspaceId') &&
        row['workspaceId'] != app['workspaceId']) {
      bad('cross_parent_reference', path);
    }
  }

  void sameApp(Json row, Json owner, String path) {
    if (row['appId'] != owner['appId'] ||
        (row.containsKey('workspaceId') &&
            owner.containsKey('workspaceId') &&
            row['workspaceId'] != owner['workspaceId'])) {
      bad('cross_parent_reference', path);
    }
  }

  void unique(String table, List<String> fields) {
    final seen = <String>{};
    for (final row in data[table]!) {
      if (!seen.add(hash([for (final k in fields) row[k]]))) {
        bad('duplicate_natural_key', table);
      }
    }
  }

  void add(
    String mode,
    String table,
    String id,
    Json payload, {
    List<String> deps = const [],
    String? key,
    Json annotations = const {},
  }) {
    final op = key ?? '$table/$id';
    if (rows.length >= 50000) bad('planned_operation_budget_exceeded', 'plan');
    if (!operationKeys.add(op)) bad('duplicate_destination_operation', table);
    rows.add(PlannedRow(op, mode, table, id, payload, deps, annotations));
  }

  String rowKey(String table, String id) => '$table/$id';
  Json common(Json row) => {
    'appId': dest('apps', row['appId'], 'appId'),
    'workspaceId': ws(
      reference('apps', row['appId'], 'appId')['workspaceId'],
      'workspaceId',
    ),
  };
  void archive(String kind, Json row, {String? state}) {
    quarantine.add({
      'kind': kind,
      'sourceId': row['id'],
      'sourceRowSha256': hash(row),
      if (row['appId'] != null) 'sourceAppId': row['appId'],
      if (state != null) 'state': state,
      'disposition': 'preserve_source_archive_do_not_execute',
    });
  }

  ImportPlan run() {
    source = decodeDocument(sourceBytes, 'source');
    mapping = decodeDocument(mappingBytes, 'mapping', maxBytes: 4194304);
    _envelopes();
    _identities();
    _core();
    _versionsAndDrafts();
    _records();
    _capacity();
    _ancillary();
    // Superfluous identity entries may hide an accidental mapping file mix-up.
    if (!usedAccounts.containsAll(actors.keys))
      issue('unused_account_mapping', 'mapping.accounts');
    if (!usedWorkspaces.containsAll(workspaces.keys))
      issue('unused_workspace_mapping', 'mapping.workspaces');
    _order();
    return ImportPlan(
      digest(sourceBytes),
      digest(mappingBytes),
      hash(target),
      target,
      rows,
      issues,
      Map<String, dynamic>.from(source['counts']),
      quarantine,
      {
        for (final table in [
          'workspaces',
          'memberships',
          'apps',
          'grants',
          'shortcuts',
          'versions',
          'drafts',
          'records',
          'pools',
          'claims',
        ])
          table: ids[table],
      },
    );
  }

  void _envelopes() {
    shape(
      source,
      {
        'format',
        'sourceInstanceId',
        'snapshotId',
        'exportedAt',
        'consistentSnapshot',
        'dataEncoding',
        'sourceArchive',
        'counts',
        'tables',
      },
      {},
      'source',
    );
    if (source['format'] != 'appnest.offline-export.v1' ||
        source['dataEncoding'] != 'serverpod-unwrapped-json.v1' ||
        source['consistentSnapshot'] != true)
      bad('unsupported_export_contract', 'source');
    text(source['sourceInstanceId'], 'source.sourceInstanceId');
    text(source['snapshotId'], 'source.snapshotId');
    timestamp(source['exportedAt'], 'source.exportedAt');
    final archive = obj(source['sourceArchive'], 'source.sourceArchive');
    shape(archive, {'sha256', 'byteLength'}, {}, 'source.sourceArchive');
    sha(archive['sha256'], 'source.sourceArchive.sha256');
    integer(
      archive['byteLength'],
      'source.sourceArchive.byteLength',
      min: 1,
      max: 9007199254740991,
    );
    final input = obj(source['tables'], 'source.tables');
    final counts = obj(source['counts'], 'source.counts');
    shape(input, tables.toSet(), {}, 'source.tables');
    shape(counts, tables.toSet(), {}, 'source.counts');
    var totalRows = 0;
    for (final table in tables) {
      final values = objects(input[table], 'tables.$table');
      if (integer(counts[table], 'counts.$table', max: 100000) !=
          values.length) {
        bad('source_count_mismatch', 'counts.$table');
      }
      totalRows += values.length;
      if (totalRows > 5000) bad('source_row_budget_exceeded', 'source.tables');
      final index = <String, Json>{};
      for (var n = 0; n < values.length; n++) {
        final row = values[n], path = 'tables.$table[$n]';
        shape(row, _fields[table]!.split(' ').toSet(), {}, path);
        final id = oldId(row['id'], '$path.id');
        if (index.containsKey(id)) bad('duplicate_source_id', path);
        index[id] = row;
      }
      values.sort(
        (a, b) => BigInt.parse(a['id']).compareTo(BigInt.parse(b['id'])),
      );
      data[table] = values;
      byId[table] = index;
    }
    shape(
      mapping,
      {
        'format',
        'sourceInstanceId',
        'sourceSha256',
        'target',
        'accounts',
        'workspaces',
      },
      {},
      'mapping',
    );
    if (mapping['format'] != 'tinkerloom.identity-map.v1' ||
        mapping['sourceInstanceId'] != source['sourceInstanceId'] ||
        sha(mapping['sourceSha256'], 'mapping.sourceSha256') !=
            digest(sourceBytes)) {
      bad('source_binding_mismatch', 'mapping');
    }
    target = obj(mapping['target'], 'mapping.target');
    shape(
      target,
      {'endpoint', 'projectId', 'databaseId', 'operatorAccountId'},
      {},
      'mapping.target',
    );
    final endpoint = text(target['endpoint'], 'target.endpoint', max: 2048);
    final uri = Uri.tryParse(endpoint);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        !uri.path.endsWith('/v1') ||
        endpoint != uri.toString()) {
      bad('invalid_target_endpoint', 'mapping.target.endpoint');
    }
    for (final key in ['projectId', 'databaseId', 'operatorAccountId']) {
      targetId(target[key], 'mapping.target.$key');
    }
    scope = hash({
      'sourceInstanceId': source['sourceInstanceId'],
      'target': target,
    });
  }

  void _identities() {
    final targetActors = <String>{}, targetSpaces = <String>{};
    for (final row in objects(mapping['accounts'], 'mapping.accounts')) {
      shape(row, {'sourceActorId', 'targetAccountId'}, {}, 'mapping.accounts');
      final actor = text(
        row['sourceActorId'],
        'mapping.accounts.sourceActorId',
        max: 100,
      );
      final to = targetId(
        row['targetAccountId'],
        'mapping.accounts.targetAccountId',
      );
      if (actors.containsKey(actor) || !targetActors.add(to))
        bad('identity_merge_forbidden', 'mapping.accounts');
      actors[actor] = to;
    }
    for (final row in objects(mapping['workspaces'], 'mapping.workspaces')) {
      shape(
        row,
        {'sourceWorkspaceId', 'targetWorkspaceId', 'disposition'},
        {},
        'mapping.workspaces',
      );
      final from = oldId(
        row['sourceWorkspaceId'],
        'mapping.workspaces.sourceWorkspaceId',
      );
      final to = targetId(
        row['targetWorkspaceId'],
        'mapping.workspaces.targetWorkspaceId',
      );
      if (!{'create', 'existing'}.contains(row['disposition']) ||
          workspaces.containsKey(from) ||
          !targetSpaces.add(to))
        bad('workspace_merge_forbidden', 'mapping.workspaces');
      workspaces[from] = to;
      workspaceModes[from] = row['disposition'];
    }
    for (final table in tables) {
      ids[table] = {
        for (final row in data[table]!)
          row['id'] as String: identity('i', [
            scope,
            table,
            row['id'] as String,
          ]),
      };
    }
    for (final row in data['workspaces']!) {
      ids['workspaces']![row['id']] = ws(row['id'], 'workspaces.id');
    }
    for (final row in data['versions']!) {
      ids['versions']![row['id']] = identity('v', [
        dest('apps', row['appId'], 'versions.appId'),
        '${integer(row['number'], 'versions.number', min: 1)}',
      ]);
    }
    for (final row in data['drafts']!) {
      ids['drafts']![row['id']] = identity('s', [
        dest('apps', row['appId'], 'drafts.appId'),
        mappedActor(row['actorId'], 'drafts.actorId'),
      ]);
    }
    for (final row in data['pools']!) {
      ids['pools']![row['id']] = identity('p', [
        dest('records', row['recordId'], 'pools.recordId'),
        text(row['behaviorId'], 'pools.behaviorId'),
      ]);
    }
    for (final row in data['memberships']!) {
      ids['memberships']![row['id']] = identity('m', [
        ws(row['workspaceId'], 'memberships.workspaceId'),
        mappedActor(row['actorId'], 'memberships.actorId'),
      ]);
    }
    for (final row in data['grants']!) {
      ids['grants']![row['id']] = identity('g', [
        dest('apps', row['appId'], 'grants.appId'),
        mappedActor(row['actorId'], 'grants.actorId'),
      ]);
    }
    for (final row in data['shortcuts']!) {
      ids['shortcuts']![row['id']] = identity('k', [
        dest('apps', row['appId'], 'shortcuts.appId'),
        mappedActor(row['actorId'], 'shortcuts.actorId'),
      ]);
    }
    for (final row in data['claims']!) {
      ids['claims']![row['id']] = identity('c', [
        dest('pools', row['poolId'], 'claims.poolId'),
        mappedActor(row['actorId'], 'claims.actorId'),
      ]);
    }
  }

  void _core() {
    unique('memberships', ['workspaceId', 'actorId']);
    unique('grants', ['appId', 'actorId']);
    unique('shortcuts', ['appId', 'actorId']);
    for (final row in data['workspaces']!) {
      final id = ws(row['id'], 'workspaces.id'),
          owner = mappedActor(row['ownerId'], 'workspaces.ownerId');
      text(row['name'], 'workspaces.name');
      boolean(row['personal'], 'workspaces.personal');
      timestamp(row['createdAt'], 'workspaces.createdAt');
      if (!data['memberships']!.any(
        (m) =>
            m['workspaceId'] == row['id'] &&
            m['actorId'] == row['ownerId'] &&
            m['role'] == 'owner',
      ))
        bad('owner_membership_missing', 'workspaces');
      add(
        workspaceModes[row['id']] == 'create' ? 'create' : 'assert_existing',
        'workspaces',
        id,
        {
          'ownerId': owner,
          if (workspaceModes[row['id']] == 'create') 'name': row['name'],
        },
        annotations: {
          'sourceCreatedAt': row['createdAt'],
          'sourcePersonal': row['personal'],
        },
      );
    }
    for (final row in data['memberships']!) {
      final workspace = reference(
        'workspaces',
        row['workspaceId'],
        'memberships.workspaceId',
      );
      final owner = row['actorId'] == workspace['ownerId'];
      if (row['role'] != (owner ? 'owner' : 'member'))
        bad('invalid_workspace_role', 'memberships.role');
      final w = ws(row['workspaceId'], 'memberships.workspaceId'),
          actor = mappedActor(row['actorId'], 'memberships.actorId');
      add(
        'create',
        'memberships',
        identity('m', [w, actor]),
        {
          'workspaceId': w,
          'actorId': actor,
          'role': row['role'],
          'active': true,
          'revision': 1,
        },
        deps: [rowKey('workspaces', w)],
      );
    }
    for (final workspace in data['workspaces']!) {
      if (data['apps']!
              .where((a) => a['workspaceId'] == workspace['id'])
              .length >
          100)
        bad('apps_per_workspace_limit', 'apps');
    }
    for (final row in data['apps']!) {
      final w = ws(row['workspaceId'], 'apps.workspaceId'),
          actor = mappedActor(row['ownerId'], 'apps.ownerId');
      if (!data['memberships']!.any(
        (m) =>
            m['workspaceId'] == row['workspaceId'] &&
            m['actorId'] == row['ownerId'],
      )) {
        bad('app_owner_membership_missing', 'apps');
      }
      text(row['name'], 'apps.name');
      boolean(row['archived'], 'apps.archived');
      integer(row['controlRevision'], 'apps.controlRevision');
      timestamp(row['createdAt'], 'apps.createdAt');
      final id = dest('apps', row['id'], 'apps.id');
      add(
        'create',
        'apps',
        id,
        {
          'workspaceId': w,
          'ownerId': actor,
          'name': row['name'],
          'guard': identity('h', [scope, 'app', row['id']]),
          'draftRevision': 0,
          'publishedRevision': 0,
          'headRevision': 0,
          'archived': row['archived'],
          'engine': 'appspec.v1',
          'specVersionId': null,
          'specVersionNumber': 0,
          'controlRevision': row['controlRevision'],
        },
        deps: [
          rowKey('memberships', identity('m', [w, actor])),
        ],
        annotations: {'sourceCreatedAt': row['createdAt']},
      );
    }
    for (final row in data['grants']!) {
      parent(row, 'grants');
      if (!{'builder', 'member', 'viewer'}.contains(row['role']))
        bad('invalid_app_role', 'grants.role');
      final app = reference('apps', row['appId'], 'grants.appId');
      if (row['actorId'] == app['ownerId'])
        bad('owner_grant_forbidden', 'grants.actorId');
      final revoked = boolean(row['revoked'], 'grants.revoked');
      if (!revoked &&
          !data['memberships']!.any(
            (m) =>
                m['workspaceId'] == row['workspaceId'] &&
                m['actorId'] == row['actorId'],
          )) {
        bad('grant_membership_missing', 'grants');
      }
      final c = common(row),
          actor = mappedActor(row['actorId'], 'grants.actorId');
      add(
        'create',
        'grants',
        identity('g', [c['appId'], actor]),
        {
          ...c,
          'actorId': actor,
          'role': row['role'],
          'revoked': revoked,
          'revision': 1,
        },
        deps: [rowKey('apps', c['appId'])],
      );
    }
    for (final row in data['shortcuts']!) {
      final app = reference('apps', row['appId'], 'shortcuts.appId');
      final actor = mappedActor(row['actorId'], 'shortcuts.actorId'),
          a = dest('apps', row['appId'], 'shortcuts.appId');
      add(
        'create',
        'shortcuts',
        identity('k', [a, actor]),
        {
          'workspaceId': ws(app['workspaceId'], 'shortcuts.workspaceId'),
          'appId': a,
          'actorId': actor,
          'pinned': true,
          'revision': 1,
          'updatedAt': source['exportedAt'],
        },
        deps: [rowKey('apps', a)],
      );
    }
  }

  spec.AppSpec definition(String value, String checksum, String path) {
    if (utf8.encode(value).length > spec.Limits.definitionBytes)
      bad('definition_size_limit', path);
    // Validate the embedded JSON without silently accepting duplicate keys.
    final parsed = guard(
      path,
      () =>
          spec.AppSpec.parse(jsonEncode(obj(StrictJson(value).parse(), path))),
    );
    if (parsed.hash != checksum) bad('definition_hash_mismatch', path);
    return parsed;
  }

  spec.AppSpec transform(spec.AppSpec value, String appId, String path) {
    final json = jsonDecode(value.canonical) as Json;
    for (final view in json['views'] as List) {
      final collectionId = view['collectionId'];
      if (collectionId != null) {
        final collection = value.collection(collectionId);
        for (final filter in view['query']?['filters'] as List? ?? []) {
          final field = collection.field(filter['fieldId']);
          if (field.type != spec.FieldType.member || filter['value'] == null)
            continue;
          filter['value'] = filter['value'] is List
              ? [
                  for (final actor in filter['value'])
                    mappedActor(actor, '$path.memberFilter'),
                ]
              : mappedActor(filter['value'], '$path.memberFilter');
        }
      }
      final asset = view['options']?['imageAssetId'];
      if (asset != null) _mediaReference(appId, asset, '$path.banner');
    }
    // Media-bearing definitions retain old IDs only in the quarantine report.
    // They cannot enter a replayable plan until a separate binary mapping exists.
    return guard(path, () => spec.AppSpec.parse(jsonEncode(json)));
  }

  void _versionsAndDrafts() {
    unique('versions', ['appId', 'number']);
    for (final row in data['versions']!) {
      parent(row, 'versions');
      final parsed = definition(
        text(
          row['specJson'],
          'versions.specJson',
          max: spec.Limits.definitionBytes,
        ),
        sha(row['candidateHash'], 'versions.candidateHash'),
        'versions.specJson',
      );
      definitions[row['id']] = parsed;
      transformed[row['id']] = transform(
        parsed,
        row['appId'],
        'versions.specJson',
      );
      final rewritten = transformed[row['id']]!, c = common(row);
      final actor = mappedActor(row['publisherId'], 'versions.publisherId');
      timestamp(row['createdAt'], 'versions.createdAt');
      final id = dest('versions', row['id'], 'versions.id');
      add(
        'create',
        'spec_versions',
        id,
        {
          ...c,
          'number': row['number'],
          'specJson': rewritten.canonical,
          'hash': rewritten.hash,
          'publisherId': actor,
          'createdAt': row['createdAt'],
        },
        deps: [rowKey('apps', c['appId'])],
        annotations: {'sourceSpecSha256': parsed.hash},
      );
    }
    for (final app in data['apps']!) {
      final versions =
          data['versions']!.where((v) => v['appId'] == app['id']).toList()
            ..sort(
              (a, b) => (a['number'] as int).compareTo(b['number'] as int),
            );
      for (var i = 0; i < versions.length; i++) {
        if (versions[i]['number'] != i + 1)
          bad('version_sequence_gap', 'versions');
        if (i > 0 &&
            definitions[versions[i - 1]['id']]!
                .compatibilityErrors(definitions[versions[i]['id']]!)
                .isNotEmpty) {
          bad('incompatible_version_history', 'versions');
        }
      }
      if (app['activeVersionId'] == null) {
        if (versions.isNotEmpty)
          bad('active_version_missing', 'apps.activeVersionId');
      } else {
        final active = reference(
          'versions',
          app['activeVersionId'],
          'apps.activeVersionId',
        );
        if (active['appId'] != app['id'] ||
            versions.isEmpty ||
            versions.last['id'] != active['id']) {
          bad('invalid_active_version', 'apps.activeVersionId');
        }
        final a = dest('apps', app['id'], 'apps.id'),
            v = dest('versions', active['id'], 'apps.activeVersionId');
        add(
          'patch',
          'apps',
          a,
          {'specVersionId': v, 'specVersionNumber': active['number']},
          key: 'activate/$a',
          deps: [rowKey('spec_versions', v)],
        );
      }
    }
    final selected = <String, Json>{};
    for (final row in data['drafts']!) {
      parent(row, 'drafts');
      final app = reference('apps', row['appId'], 'drafts.appId');
      final actor = mappedActor(row['actorId'], 'drafts.actorId');
      timestamp(row['updatedAt'], 'drafts.updatedAt');
      integer(row['mutation'], 'drafts.mutation');
      final candidate = definition(
        text(
          row['candidateJson'],
          'drafts.candidateJson',
          max: spec.Limits.definitionBytes,
        ),
        sha(row['candidateHash'], 'drafts.candidateHash'),
        'drafts.candidateJson',
      );
      transform(candidate, row['appId'], 'drafts.candidateJson');
      for (final field in ['baseVersionId', 'publishedVersionId']) {
        if (row[field] != null)
          sameApp(
            row,
            reference('versions', row[field], 'drafts.$field'),
            'drafts.$field',
          );
      }
      if (row['publishedVersionId'] != null &&
          definitions[row['publishedVersionId']]!.hash != candidate.hash)
        bad('consumed_candidate_mismatch', 'drafts');
      if (row['activeJobId'] != null) {
        final job = reference('jobs', row['activeJobId'], 'drafts.activeJobId');
        if (job['draftId'] != row['id'] || job['actorId'] != row['actorId'])
          bad('cross_parent_reference', 'drafts.activeJobId');
        issue(
          'active_generation_requires_reconciliation',
          'drafts.activeJobId',
        );
      }
      final key = identity('s', [
        dest('apps', row['appId'], 'drafts.appId'),
        actor,
      ]);
      final old = selected[key];
      if (old != null) {
        final newer =
            (row['updatedAt'] as String).compareTo(old['updatedAt']) > 0 ||
            (row['updatedAt'] == old['updatedAt'] &&
                BigInt.parse(row['id']) > BigInt.parse(old['id']));
        archive('historical_draft', newer ? old : row);
        issue('multiple_author_drafts_require_archive', 'drafts');
        if (!newer) continue;
      }
      selected[key] = row;
      // Revoked authors' candidates remain private; no grant is synthesized.
      if (row['actorId'] != app['ownerId'] &&
          !data['grants']!.any(
            (g) =>
                g['appId'] == app['id'] &&
                g['actorId'] == row['actorId'] &&
                g['role'] == 'builder' &&
                g['revoked'] == false,
          )) {
        issue('inaccessible_private_draft_retained', 'drafts', required: false);
      }
    }
    for (final entry in selected.entries) {
      final row = entry.value, c = common(row);
      final value = transform(
        definition(row['candidateJson'], row['candidateHash'], 'drafts'),
        row['appId'],
        'drafts',
      );
      add(
        'create',
        'spec_drafts',
        entry.key,
        {
          ...c, 'actorId': mappedActor(row['actorId'], 'drafts.actorId'),
          // Serverpod mutation and Appwrite candidate revision have different
          // meanings. Begin a new explicit revision domain; retain the source in annotations.
          'revision': 1,
          'baseVersionId': row['baseVersionId'] == null
              ? null
              : dest('versions', row['baseVersionId'], 'drafts.baseVersionId'),
          'candidateHash': value.hash, 'specJson': value.canonical,
          'publishedVersionId': row['publishedVersionId'] == null
              ? null
              : dest(
                  'versions',
                  row['publishedVersionId'],
                  'drafts.publishedVersionId',
                ),
          'updatedAt': row['updatedAt'],
        },
        deps: [
          rowKey('apps', c['appId']),
          if (row['baseVersionId'] != null)
            rowKey(
              'spec_versions',
              dest('versions', row['baseVersionId'], 'drafts.baseVersionId'),
            ),
        ],
        annotations: {
          'sourceMutation': row['mutation'],
          'sourceDraftId': row['id'],
        },
      );
    }
  }

  void _mediaReference(String appId, Object? value, String path) {
    final asset = data['media']!
        .where((a) => a['assetId'] == value)
        .firstOrNull;
    if (asset == null) bad('missing_media_reference', path);
    if (asset['appId'] != appId) bad('cross_parent_media_reference', path);
    if (asset['status'] != 'ready') bad('media_reference_not_ready', path);
    issue('media_binary_transfer_required', path);
  }

  void _records() {
    for (final row in data['records']!) {
      parent(row, 'records');
      final written = reference(
        'versions',
        row['writtenUnderVersionId'],
        'records.writtenUnderVersionId',
      );
      sameApp(row, written, 'records.writtenUnderVersionId');
      final original = definitions[written['id']]!;
      final collection = guard(
        'records.collectionId',
        () => original.collection(
          text(row['collectionId'], 'records.collectionId'),
        ),
      );
      final input = obj(row['data'], 'records.data');
      final normalized = guard(
        'records.data',
        () => collection.normalizeRecord(input),
      );
      // An export must not silently drop a SQL wrapper or normalize malformed values.
      if (spec.canonicalJson(normalized) != spec.canonicalJson(input))
        bad('record_not_canonical', 'records.data');
      final mapped = <String, dynamic>{...normalized};
      for (final field in collection.fields) {
        if (mapped[field.id] == null) continue;
        if (field.type == spec.FieldType.member)
          mapped[field.id] = mappedActor(
            mapped[field.id],
            'records.data.member',
          );
        if (field.type == spec.FieldType.image)
          _mediaReference(row['appId'], mapped[field.id], 'records.data.image');
      }
      final deleted = boolean(row['deleted'], 'records.deleted');
      final app = reference('apps', row['appId'], 'records.appId');
      if (app['activeVersionId'] == null)
        bad('record_without_published_version', 'records');
      final active = transformed[app['activeVersionId']]!;
      if (!deleted)
        guard(
          'records.currentCompatibility',
          () => active.collection(collection.id).normalizeRecord(mapped),
        );
      timestamp(row['createdAt'], 'records.createdAt');
      timestamp(row['updatedAt'], 'records.updatedAt');
      if ((row['updatedAt'] as String).compareTo(row['createdAt']) < 0)
        bad('metadata_time_order', 'records');
      final c = common(row), id = dest('records', row['id'], 'records.id');
      add(
        'create',
        'spec_records',
        id,
        {
          ...c,
          'collectionId': collection.id,
          'dataJson': jsonEncode(mapped),
          'creatorId': mappedActor(row['creatorId'], 'records.creatorId'),
          'revision': integer(row['revision'], 'records.revision', min: 1),
          'writtenUnderVersionId': dest(
            'versions',
            written['id'],
            'records.writtenUnderVersionId',
          ),
          'deleted': deleted,
          'createdAt': row['createdAt'],
          'updatedAt': row['updatedAt'],
        },
        deps: [
          rowKey(
            'spec_versions',
            dest('versions', written['id'], 'records.writtenUnderVersionId'),
          ),
        ],
      );
      // The runtime projects the current compatible shape, including explicit absent fields.
      final projection = deleted
          ? collection
          : active.collection(collection.id);
      for (final field in projection.fields) {
        final value = mapped[field.id];
        add(
          'create',
          'spec_values',
          identity('f', [id, field.id]),
          {
            ...c,
            'recordId': id,
            'collectionId': collection.id,
            'fieldId': field.id,
            'present': value != null,
            'textValue':
                value is String && field.type != spec.FieldType.timestamp
                ? value
                : null,
            'numberValue': value is num ? value : null,
            'boolValue': value is bool ? value : null,
            'timestampValue': field.type == spec.FieldType.timestamp
                ? value
                : null,
          },
          deps: [rowKey('spec_records', id)],
        );
      }
    }
  }

  void _capacity() {
    unique('pools', ['recordId', 'behaviorId']);
    unique('claims', ['poolId', 'actorId']);
    for (final row in data['pools']!) {
      parent(row, 'pools');
      final record = reference('records', row['recordId'], 'pools.recordId');
      sameApp(row, record, 'pools.recordId');
      final col = definitions[record['writtenUnderVersionId']]!.collection(
        record['collectionId'],
      );
      final behavior = guard(
        'pools.behaviorId',
        () => col.behavior(row['behaviorId']),
      );
      if (behavior.type != 'capacity.v1')
        bad('invalid_capacity_behavior', 'pools.behaviorId');
      final capacity = integer(row['capacity'], 'pools.capacity', max: 10000);
      final allocated = integer(
        row['allocated'],
        'pools.allocated',
        max: capacity,
      );
      final claims = data['claims']!
          .where((c) => c['poolId'] == row['id'])
          .toList();
      if (claims.where((c) => c['active'] == true).length != allocated)
        bad('claim_allocation_mismatch', 'pools');
      final c = common(row), id = dest('pools', row['id'], 'pools.id');
      add(
        'create',
        'spec_pools',
        id,
        {
          ...c,
          'recordId': dest('records', record['id'], 'pools.recordId'),
          'collectionId': col.id,
          'behaviorId': behavior.id,
          'capacity': capacity,
          'allocated': allocated,
        },
        deps: [
          rowKey(
            'spec_records',
            dest('records', record['id'], 'pools.recordId'),
          ),
        ],
      );
    }
    for (final record in data['records']!) {
      final col = definitions[record['writtenUnderVersionId']]!.collection(
        record['collectionId'],
      );
      for (final behavior in col.behaviors.where(
        (b) => b.type == 'capacity.v1',
      )) {
        if (!data['pools']!.any(
          (p) =>
              p['recordId'] == record['id'] && p['behaviorId'] == behavior.id,
        )) {
          bad('capacity_pool_missing', 'records');
        }
      }
    }
    for (final row in data['claims']!) {
      parent(row, 'claims');
      final pool = reference('pools', row['poolId'], 'claims.poolId');
      sameApp(row, pool, 'claims.poolId');
      final c = common(row),
          actor = mappedActor(row['actorId'], 'claims.actorId'),
          p = dest('pools', pool['id'], 'claims.poolId');
      timestamp(row['createdAt'], 'claims.createdAt');
      timestamp(row['updatedAt'], 'claims.updatedAt');
      add(
        'create',
        'spec_claims',
        identity('c', [p, actor]),
        {
          ...c,
          'poolId': p,
          'actorId': actor,
          'active': boolean(row['active'], 'claims.active'),
          'createdAt': row['createdAt'],
          'updatedAt': row['updatedAt'],
        },
        deps: [rowKey('spec_pools', p)],
      );
    }
  }

  void _ancillary() {
    unique('media', ['assetId']);
    final declaredRefs = <String>{}, expectedRefs = <String>{};
    for (final row in data['media']!) {
      parent(row, 'media');
      mappedActor(row['uploaderId'], 'media.uploaderId');
      if (!RegExp(
        r'^img_[A-Za-z0-9_-]{43}$',
      ).hasMatch(text(row['assetId'], 'media.assetId')))
        bad('invalid_legacy_asset_id', 'media.assetId');
      if (!{
        'issuing',
        'pending',
        'processing',
        'ready',
        'failed',
        'deleting',
        'deleted',
      }.contains(row['status']))
        bad('unsupported_media_state', 'media.status');
      if (!{
        'image/jpeg',
        'image/png',
        'image/webp',
      }.contains(row['contentType']))
        bad('unsupported_media_content_type', 'media.contentType');
      integer(
        row['byteLength'],
        'media.byteLength',
        min: 1,
        max: 5 * 1024 * 1024,
      );
      integer(row['storedBytes'], 'media.storedBytes', max: 250 * 1024 * 1024);
      integer(row['width'], 'media.width', max: 8192);
      integer(row['height'], 'media.height', max: 8192);
      boolean(row['originalRemoved'], 'media.originalRemoved');
      timestamp(row['createdAt'], 'media.createdAt');
      timestamp(row['updatedAt'], 'media.updatedAt');
      archive('media_metadata', row, state: row['status']);
      issue('media_binary_and_quota_reservation_plan_required', 'media');
    }
    for (final app in data['apps']!) {
      final assets = data['media']!
          .where((a) => a['appId'] == app['id'])
          .toList();
      if (assets.length > 500 ||
          assets.fold<int>(0, (n, a) => n + (a['storedBytes'] as int)) >
              250 * 1024 * 1024)
        bad('legacy_media_quota_exceeded', 'media');
    }
    void expect(String kind, Json owner, spec.AppSpec definition) {
      for (final view in definition.views) {
        final asset = view.options['imageAssetId'];
        if (asset == null) continue;
        final media = data['media']!.firstWhere((a) => a['assetId'] == asset);
        expectedRefs.add(hash([media['id'], kind, owner['id']]));
      }
    }

    for (final row in data['versions']!) {
      expect('version', row, definitions[row['id']]!);
    }
    for (final row in data['drafts']!) {
      expect(
        'draft',
        row,
        definition(row['candidateJson'], row['candidateHash'], 'drafts'),
      );
    }
    for (final row in data['records']!) {
      final col = definitions[row['writtenUnderVersionId']]!.collection(
        row['collectionId'],
      );
      for (final field in col.fields.where(
        (f) => f.type == spec.FieldType.image,
      )) {
        final value = row['data'][field.id];
        if (value == null) continue;
        final media = data['media']!.firstWhere((a) => a['assetId'] == value);
        expectedRefs.add(hash([media['id'], 'record', row['id']]));
      }
    }
    for (final row in data['mediaReferences']!) {
      parent(row, 'mediaReferences');
      final asset = reference(
        'media',
        row['assetRowId'],
        'mediaReferences.assetRowId',
      );
      sameApp(row, asset, 'mediaReferences.assetRowId');
      final owners = [
        'draftId',
        'versionId',
        'recordId',
      ].where((k) => row[k] != null).toList();
      if (owners.length != 1)
        bad('media_reference_owner_cardinality', 'mediaReferences');
      final key = owners.single, kind = key.substring(0, key.length - 2);
      final owner = reference('${kind}s', row[key], 'mediaReferences.$key');
      sameApp(row, owner, 'mediaReferences.$key');
      final signature = hash([asset['id'], kind, owner['id']]);
      if (!declaredRefs.add(signature))
        bad('duplicate_media_reference', 'mediaReferences');
      archive('media_reference', row);
    }
    if (!declaredRefs.containsAll(expectedRefs) ||
        !expectedRefs.containsAll(declaredRefs))
      bad('media_reference_set_mismatch', 'mediaReferences');
    unique('receipts', ['appId', 'actorId', 'idempotencyKeySha256']);
    for (final row in data['receipts']!) {
      reference('apps', row['appId'], 'receipts.appId');
      mappedActor(row['actorId'], 'receipts.actorId');
      for (final key in [
        'idempotencyKeySha256',
        'requestHash',
        'outcomeSha256',
      ]) {
        sha(row[key], 'receipts.$key');
      }
      if (!{'confirmed', 'unknown'}.contains(row['state']))
        bad('unsupported_receipt_state', 'receipts.state');
      if (row['state'] == 'confirmed') {
        final record = reference(
          'records',
          row['recordId'],
          'receipts.recordId',
        );
        sameApp(row, record, 'receipts.recordId');
        final revision = integer(row['revision'], 'receipts.revision', min: 1);
        if (revision > (record['revision'] as int))
          bad('receipt_revision_ahead', 'receipts.revision');
      } else {
        if (row['recordId'] != null || row['revision'] != null)
          bad('unknown_receipt_cannot_assert_outcome', 'receipts');
        issue('unknown_receipt_requires_reconciliation', 'receipts');
      }
      archive('legacy_receipt', row, state: row['state']);
      issue(
        'legacy_receipt_preserved_not_reinterpreted',
        'receipts',
        required: false,
      );
    }
    for (final row in data['pendingCommands']!) {
      reference('apps', row['appId'], 'pendingCommands.appId');
      mappedActor(row['actorId'], 'pendingCommands.actorId');
      sha(row['requestHash'], 'pendingCommands.requestHash');
      if (!{'pending', 'unknown'}.contains(row['state']))
        bad('unsupported_pending_command_state', 'pendingCommands');
      archive('outstanding_command', row, state: row['state']);
      issue('outstanding_command_requires_reconciliation', 'pendingCommands');
    }
    unique('automations', ['appId', 'ruleId']);
    for (final row in data['automations']!) {
      parent(row, 'automations');
      mappedActor(row['executionActorId'], 'automations.executionActorId');
      sha(row['ruleSha256'], 'automations.ruleSha256');
      boolean(row['enabled'], 'automations.enabled');
      final app = reference('apps', row['appId'], 'automations.appId');
      if (app['activeVersionId'] == null ||
          !definitions[app['activeVersionId']]!.automationRequests.any(
            (r) => r.id == row['ruleId'],
          )) {
        bad('automation_rule_missing', 'automations.ruleId');
      }
      archive(
        'automation_disabled_at_destination',
        row,
        state: row['enabled'] ? 'source_enabled' : 'source_disabled',
      );
      issue(
        'automation_approvals_not_transferred',
        'automations',
        required: false,
      );
    }
    for (final row in data['jobs']!) {
      reference('apps', row['appId'], 'jobs.appId');
      final draft = reference('drafts', row['draftId'], 'jobs.draftId');
      sameApp(row, draft, 'jobs.draftId');
      mappedActor(row['actorId'], 'jobs.actorId');
      if (row['actorId'] != draft['actorId'])
        bad('private_job_author_mismatch', 'jobs.actorId');
      integer(row['mutation'], 'jobs.mutation');
      sha(row['contentSha256'], 'jobs.contentSha256');
      if (!{
        'queued',
        'generating',
        'validating',
        'preview ready',
        'stale',
        'failed',
      }.contains(row['status']))
        bad('unsupported_job_state', 'jobs.status');
      archive('generation_job', row, state: row['status']);
      if ({'queued', 'generating', 'validating'}.contains(row['status']))
        issue('active_generation_requires_reconciliation', 'jobs');
    }
    for (final row in data['history']!) {
      reference('apps', row['appId'], 'history.appId');
      if (!{
        'audit',
        'notification',
        'automationRun',
        'outbox',
        'invitationRedacted',
      }.contains(row['kind']))
        bad('unsupported_archive_kind', 'history.kind');
      text(row['state'], 'history.state');
      sha(row['contentSha256'], 'history.contentSha256');
      const states = {
        'terminal',
        'read',
        'delivered',
        'revoked',
        'expired',
        'pending',
        'unknown',
        'queued',
        'generating',
        'validating',
        'preview ready',
        'stale',
        'failed',
        'suppressed',
        'succeeded',
        'unread',
        'unplanned',
      };
      archive(
        row['kind'],
        row,
        state: states.contains(row['state']) ? row['state'] : 'unknown',
      );
      if (!{
        'terminal',
        'read',
        'delivered',
        'revoked',
        'expired',
      }.contains(row['state'])) {
        issue('nonterminal_history_requires_reconciliation', 'history');
      }
    }
  }

  void _order() {
    // Visibility switches last, after every dependent row for that app. A real
    // runner must still use a maintenance fence and authorized atomic batches.
    for (final activation in rows.where((r) => r.key.startsWith('activate/'))) {
      activation.dependencies.addAll(
        rows
            .where(
              (r) =>
                  r != activation &&
                  (r.data['appId'] == activation.id ||
                      (r.table == 'apps' && r.id == activation.id)),
            )
            .map((r) => r.key),
      );
    }
    final remaining = <String, int>{}, dependents = <String, List<String>>{};
    final index = {for (final row in rows) row.key: row},
        allKeys = rows.map((r) => r.key).toSet();
    for (final row in rows) {
      final deps = row.dependencies.toSet();
      if (!allKeys.containsAll(deps))
        bad('invalid_operation_dependencies', 'plan');
      remaining[row.key] = deps.length;
      for (final dep in deps) {
        (dependents[dep] ??= []).add(row.key);
      }
    }
    final ready = SplayTreeSet<String>()
      ..addAll(remaining.keys.where((k) => remaining[k] == 0));
    final sorted = <PlannedRow>[];
    while (ready.isNotEmpty) {
      final key = ready.first;
      ready.remove(key);
      sorted.add(index[key]!);
      for (final child in dependents[key] ?? <String>[]) {
        remaining[child] = remaining[child]! - 1;
        if (remaining[child] == 0) ready.add(child);
      }
    }
    if (sorted.length != rows.length)
      bad('invalid_operation_dependencies', 'plan');
    rows
      ..clear()
      ..addAll(sorted);
    // Destination IDs are checked even for hash-derived natural identities.
    for (final row in rows) {
      targetId(row.id, 'plan.destinationId');
    }
  }
}

/// An explicit local mapping worksheet. Null destinations are intentionally
/// invalid until the operator supplies real account/workspace identities.
Json identityWorksheet(List<int> sourceBytes) {
  final document = decodeDocument(sourceBytes, 'source');
  final placeholder = {
    'format': 'tinkerloom.identity-map.v1',
    'sourceInstanceId': document['sourceInstanceId'],
    'sourceSha256': digest(sourceBytes),
    'target': {
      'endpoint': 'https://appwrite.invalid/v1',
      'projectId': 'worksheet',
      'databaseId': 'tinkerloom',
      'operatorAccountId': 'worksheet',
    },
    'accounts': [],
    'workspaces': [],
  };
  final parser = _Planner(sourceBytes, utf8.encode(jsonEncode(placeholder)))
    ..source = document;
  parser.mapping = placeholder;
  parser._envelopes();
  final accounts = <String>{};
  const fields = {
    'workspaces': ['ownerId'],
    'memberships': ['actorId'],
    'apps': ['ownerId'],
    'grants': ['actorId'],
    'shortcuts': ['actorId'],
    'versions': ['publisherId'],
    'drafts': ['actorId'],
    'records': ['creatorId'],
    'claims': ['actorId'],
    'receipts': ['actorId'],
    'pendingCommands': ['actorId'],
    'media': ['uploaderId'],
    'automations': ['executionActorId'],
    'jobs': ['actorId'],
  };
  for (final entry in fields.entries) {
    for (final row in parser.data[entry.key]!) {
      for (final field in entry.value) {
        accounts.add(text(row[field], '${entry.key}.$field', max: 100));
      }
    }
  }
  final defs = <String, spec.AppSpec>{};
  void filters(spec.AppSpec definition) {
    for (final view in definition.views) {
      if (view.contentOnly) continue;
      final collection = definition.collection(view.collectionId);
      for (final filter in view.query?['filters'] as List? ?? []) {
        if (collection.field(filter['fieldId']).type != spec.FieldType.member ||
            filter['value'] == null)
          continue;
        final values = filter['value'] is List
            ? filter['value'] as List
            : [filter['value']];
        for (final actor in values) {
          accounts.add(text(actor, 'definition.memberFilter', max: 100));
        }
      }
    }
  }

  for (final row in parser.data['versions']!) {
    final definition = parser.definition(
      text(
        row['specJson'],
        'versions.specJson',
        max: spec.Limits.definitionBytes,
      ),
      sha(row['candidateHash'], 'versions.candidateHash'),
      'versions.specJson',
    );
    defs[row['id']] = definition;
    filters(definition);
  }
  for (final row in parser.data['drafts']!) {
    filters(
      parser.definition(
        text(
          row['candidateJson'],
          'drafts.candidateJson',
          max: spec.Limits.definitionBytes,
        ),
        sha(row['candidateHash'], 'drafts.candidateHash'),
        'drafts.candidateJson',
      ),
    );
  }
  for (final row in parser.data['records']!) {
    final definition =
        defs[row['writtenUnderVersionId']] ??
        (bad('missing_reference', 'records.writtenUnderVersionId'));
    final collection = parser.guard(
      'records.collectionId',
      () => definition.collection(row['collectionId']),
    );
    final record = parser.guard(
      'records.data',
      () => collection.normalizeRecord(obj(row['data'], 'records.data')),
    );
    for (final field in collection.fields.where(
      (f) => f.type == spec.FieldType.member,
    )) {
      if (record[field.id] != null)
        accounts.add(text(record[field.id], 'records.member', max: 100));
    }
  }
  return {
    'format': 'tinkerloom.identity-map.v1',
    'sourceInstanceId': document['sourceInstanceId'],
    'sourceSha256': digest(sourceBytes),
    'target': {
      'endpoint': null,
      'projectId': null,
      'databaseId': null,
      'operatorAccountId': null,
    },
    'accounts': [
      for (final actor in accounts.toList()..sort())
        {'sourceActorId': actor, 'targetAccountId': null},
    ],
    'workspaces': [
      for (final workspace in parser.data['workspaces']!)
        {
          'sourceWorkspaceId': workspace['id'],
          'targetWorkspaceId': null,
          'disposition': null,
        },
    ],
  };
}

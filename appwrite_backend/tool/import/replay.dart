// Deterministic IN-MEMORY simulator only; no production RowStore adapter.
import 'engine.dart';
import 'format.dart';

class SimulatedRows {
  final Map<String, Json> _rows = {};
  final Map<String, String> _applied = {};
  SimulatedRows({Map<String, Json> existing = const {}}) {
    for (final e in existing.entries) {
      _rows[e.key] = {...e.value};
    }
  }
  int get count => _rows.length;
  String get checksum => hash(_rows);
  Json? read(String table, String id) => _rows['$table/$id'];
  void apply(PlannedRow operation) {
    final payload = operation.payloadSha256;
    if (_applied.containsKey(operation.key)) {
      if (_applied[operation.key] != payload)
        bad('simulated_operation_conflict', operation.key);
      return;
    }
    if (!operation.dependencies.every(_applied.containsKey))
      bad('simulated_dependency_missing', operation.key);
    final key = '${operation.table}/${operation.id}', existing = _rows[key];
    switch (operation.mode) {
      case 'create':
        if (existing != null && hash(existing) != payload)
          bad('simulated_destination_collision', operation.key);
        _rows[key] = {...operation.data};
      case 'assert_existing':
        if (existing == null ||
            operation.data.entries.any(
              (e) => hash(existing[e.key]) != hash(e.value),
            )) {
          bad('simulated_existing_workspace_mismatch', operation.key);
        }
      case 'patch':
        if (existing == null)
          bad('simulated_patch_target_missing', operation.key);
        _rows[key] = {...existing, ...operation.data};
      default:
        bad('unsupported_simulated_mode', operation.key);
    }
    _applied[operation.key] = payload;
  }
}

class Simulation {
  final ImportPlan plan;
  final SimulatedRows destination;
  final List<Json> _entries = [];
  Simulation(this.plan, {SimulatedRows? destination, Json? resume})
    : destination = destination ?? SimulatedRows() {
    if (!plan.validForSimulation) bad('required_issues_block_replay', 'plan');
    if (resume != null) _resume(resume);
  }
  int get confirmed =>
      _entries.where((e) => e['state'] == 'simulated_confirmed').length;
  bool get complete => confirmed == plan.rows.length;
  bool get uncertain => _entries.any((e) => e['state'] == 'unknown');
  Json get ledger {
    final payload = <String, dynamic>{
      'format': 'tinkerloom.offline-ledger.v1',
      'mode': 'simulation_only',
      'sourceSha256': plan.sourceSha256,
      'mappingSha256': plan.mappingSha256,
      'targetSha256': plan.targetSha256,
      'planSha256': plan.planSha256,
      'entries': [
        for (final entry in _entries) {...entry},
      ],
      'simulatedRowCount': destination.count,
      'simulatedRowSha256': destination.checksum,
    };
    return {...payload, 'ledgerSha256': hash(payload)};
  }

  void _resume(Json value) {
    shape(
      value,
      {
        'format',
        'mode',
        'sourceSha256',
        'mappingSha256',
        'targetSha256',
        'planSha256',
        'entries',
        'simulatedRowCount',
        'simulatedRowSha256',
        'ledgerSha256',
      },
      {},
      'ledger',
    );
    if (value['format'] != 'tinkerloom.offline-ledger.v1' ||
        value['mode'] != 'simulation_only') {
      bad('unsupported_ledger', 'ledger');
    }
    for (final e in {
      'sourceSha256': plan.sourceSha256,
      'mappingSha256': plan.mappingSha256,
      'targetSha256': plan.targetSha256,
      'planSha256': plan.planSha256,
    }.entries) {
      if (value[e.key] != e.value)
        bad('resume_binding_mismatch', 'ledger.${e.key}');
    }
    final unsigned = {...value}..remove('ledgerSha256');
    if (sha(value['ledgerSha256'], 'ledger.ledgerSha256') != hash(unsigned))
      bad('ledger_checksum_mismatch', 'ledger');
    final entries = objects(value['entries'], 'ledger.entries');
    if (entries.length > plan.rows.length)
      bad('ledger_progress_out_of_range', 'ledger.entries');
    var unknown = false;
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i], expected = plan.rows[i];
      shape(
        e,
        {'sequence', 'operationKey', 'payloadSha256', 'state'},
        {},
        'ledger.entries',
      );
      if (e['sequence'] != i ||
          e['operationKey'] != expected.key ||
          e['payloadSha256'] != expected.payloadSha256 ||
          unknown ||
          !{'simulated_confirmed', 'unknown'}.contains(e['state']))
        bad('invalid_ledger_progress', 'ledger.entries');
      if (e['state'] == 'unknown') {
        unknown = true;
      } else {
        destination.apply(expected);
      }
      _entries.add({...e});
    }
    if (value['simulatedRowCount'] != destination.count ||
        value['simulatedRowSha256'] != destination.checksum)
      bad('simulated_snapshot_mismatch', 'ledger');
  }

  int advance({int maxOperations = 100}) {
    integer(maxOperations, 'simulation.maxOperations', min: 1, max: 10000);
    if (uncertain) bad('unknown_progress_requires_reconciliation', 'ledger');
    var advanced = 0;
    while (confirmed < plan.rows.length && advanced < maxOperations) {
      final operation = plan.rows[confirmed];
      destination.apply(operation);
      _entries.add({
        'sequence': confirmed,
        'operationKey': operation.key,
        'payloadSha256': operation.payloadSha256,
        'state': 'simulated_confirmed',
      });
      advanced++;
    }
    return advanced;
  }

  /// Failure injection for tests/operators demonstrating an ambiguous local step.
  /// There is intentionally no API that converts unknown into confirmed.
  void markNextUnknown() {
    if (uncertain || complete) bad('invalid_unknown_injection', 'ledger');
    final operation = plan.rows[confirmed];
    _entries.add({
      'sequence': confirmed,
      'operationKey': operation.key,
      'payloadSha256': operation.payloadSha256,
      'state': 'unknown',
    });
  }
}

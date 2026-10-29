// Test-only stdio bridge: no HTTP endpoint, credentials, or production override.
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import '../lib/service.dart';
import 'memory_store.dart';

class WorkspaceGuardRaceStore extends MemoryStore {
  bool armed = false;
  Completer<void>? paused;
  Completer<void>? resume;

  void arm() {
    armed = true;
    paused = Completer<void>();
    resume = Completer<void>();
  }

  @override
  Future<Row> update(
    String table,
    String id,
    Row data, {
    String? transactionId,
  }) async {
    final result = await super.update(
      table,
      id,
      data,
      transactionId: transactionId,
    );
    if (armed && table == 'workspaces' && transactionId != null) {
      armed = false;
      paused!.complete();
      await resume!.future;
    }
    return result;
  }
}

Future<void> main() async {
  var now = DateTime.utc(2030, 1, 2);
  final store = WorkspaceGuardRaceStore();
  final service = PlatformService(
    store,
    clock: () => now,
    remindersEnabled: true,
  );
  final worker = WorkerEngine(service);
  stdout.writeln(jsonEncode({'ready': true, 'layer': 'local_virtual_clock'}));
  await for (final line
      in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    try {
      if (line.length > 131072) throw const FormatException();
      final envelope = jsonDecode(line) as Row;
      now = DateTime.fromMillisecondsSinceEpoch(
        envelope['now'] as int,
        isUtc: true,
      );
      if (envelope['kind'] == 'localWorkerDrain') {
        // Called only by the offline harness, never by the public HTTP adapter.
        final drains = envelope['drains'] as int? ?? 1;
        if (drains < 1 || drains > 3) throw const FormatException();
        final results = <Row>[];
        for (var n = 0; n < drains; n++) {
          results.add(await worker.reminders());
        }
        stdout.writeln(
          jsonEncode({
            'status': 200,
            'data': {'drains': results},
          }),
        );
        continue;
      }
      if (envelope['kind'] != 'publicCore') throw const FormatException();
      if (envelope['raceWorkerPlanning'] == true) store.arm();
      final pending = service.execute(
        envelope['actor'] as String,
        Map<String, dynamic>.from(envelope['input'] as Map),
      );
      if (envelope['raceWorkerPlanning'] == true) {
        await store.paused!.future;
        try {
          await worker.reminders();
        } finally {
          store.resume!.complete();
        }
      }
      final response = await pending;
      stdout.writeln(jsonEncode({'status': 200, 'data': response}));
    } on ServiceException catch (error) {
      stdout.writeln(
        jsonEncode({
          'status': error.status,
          'data': {'error': error.code},
        }),
      );
    } catch (_) {
      stdout.writeln(
        jsonEncode({
          'status': 500,
          'data': {'error': 'offline_bridge_failure'},
        }),
      );
    }
  }
}

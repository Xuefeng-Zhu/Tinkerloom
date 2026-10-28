import 'dart:convert';
import 'dart:io';
import 'package:appnest_spec/appnest_spec.dart' as spec;
import '../lib/service.dart';
import 'memory_store.dart';

/// Real service DTOs over a simulated store. No Cloud or provider calls.
Future<void> main(List<String> args) async {
  final store = MemoryStore();
  final service = PlatformService(
    store,
    clock: () => DateTime.utc(2026, 10, 28, 12),
  );
  Future<Row> call(Row input) => service.execute('alice', input);
  await call({'op': 'createWorkspace', 'id': 'ws', 'name': 'Wire workspace'});
  final shell = await call({
    'op': 'spec.createApp',
    'id': 'app',
    'workspaceId': 'ws',
    'operationId': 'create',
    'name': 'Wire app',
  });
  final definition = spec.starterTemplates()['reading']!.toJson();
  final draft = await call({
    'op': 'spec.saveDraft',
    'appId': 'app',
    'operationId': 'save',
    'expectedRevision': 0,
    'expectedVersionId': null,
    'spec': definition,
  });
  final review = await call({
    'op': 'spec.review',
    'appId': 'app',
    'expectedRevision': 1,
    'enabledRuleIds': <String>[],
    'activateExistingRecordIds': <String>[],
  });
  final published = await call({
    'op': 'spec.publish',
    'appId': 'app',
    'operationId': 'publish',
    'expectedRevision': 1,
    'expectedVersionId': null,
    'candidateHash': (review['review'] as Row)['candidateHash'],
    'reviewHash': (review['review'] as Row)['reviewHash'],
    'enabledRuleIds': <String>[],
    'activateExistingRecordIds': <String>[],
  });
  final result = <String, dynamic>{
    'proof':
        'Real Dart service DTOs with a simulated optimistic store; no Cloud evidence.',
    'capabilities': await call({'op': 'spec.capabilities'}),
    'shell': shell,
    'draft': draft,
    'review': review,
    'published': published,
    'launcher': await call({
      'op': 'spec.launcher',
      'workspaceId': 'ws',
      'limit': 50,
    }),
    'drafts': await call({
      'op': 'spec.listDrafts',
      'workspaceId': 'ws',
      'limit': 50,
    }),
    'versions': await call({
      'op': 'spec.listVersions',
      'appId': 'app',
      'limit': 25,
    }),
  };
  final versionId = ((published['app'] as Row)['version'] as Row)['id'];
  result['version'] = await call({
    'op': 'spec.getVersion',
    'appId': 'app',
    'versionId': versionId,
  });
  final wire = const JsonEncoder.withIndent('  ').convert(result) + '\n';
  if (args.length == 2 && args.first == '--check') {
    if (jsonEncode(jsonDecode(File(args.last).readAsStringSync())) !=
        jsonEncode(result)) {
      stderr.writeln('Client wire fixture differs from the current service.');
      exitCode = 1;
    } else {
      stdout.writeln('Client wire fixture matches the current Dart service.');
    }
  } else if (args.length == 2 && args.first == '--write') {
    File(args.last)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(wire);
  } else {
    stdout.write(wire);
  }
}

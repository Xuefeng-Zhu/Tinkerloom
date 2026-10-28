import 'dart:convert';
import 'dart:io';
import 'package:appnest_server/src/modules/builder/nemotron_scenarios.dart';
import 'package:appnest_server/src/modules/builder/provider.dart';
import 'package:crypto/crypto.dart';
import 'package:appnest_server/src/modules/builder/nemotron_routes.dart';

void main(List<String> args) {
  final cases = jsonDecode(File('output/nemotron-tuning-2026-10-08/plan.json').readAsStringSync()) as Map<String,dynamic>;
  final selected = (cases['screeningCases'] ?? cases['cases']) as List?;
  final scenarios = nemotronScenarios().where((s) => s.operation == 'create' && (selected == null || selected.contains(s.id)));
  final receipts = <String,dynamic>{};
  for (final model in ['nvidia/nemotron-3-super-120b-a12b', 'z-ai/glm-5.3']) {
    final provider = ChatCompletionProvider(Uri.parse(nvidiaEvaluationBase),model,'synthetic-unused-key',nvidiaModelEvaluation:true);
    receipts[model] = {
      for(final s in scenarios) s.id: sha256.convert(utf8.encode(jsonEncode(provider.adaptRequestForTransport(buildAiRequest(model,s.prompt,s.baseline,editing:false),generation:true)))).toString(),
    };
  }
  File(args.single).writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(receipts)}\n');
}

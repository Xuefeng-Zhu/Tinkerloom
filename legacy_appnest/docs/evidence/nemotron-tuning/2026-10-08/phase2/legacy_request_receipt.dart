import 'dart:convert';
import 'dart:io';

import 'package:appnest_server/src/modules/builder/nemotron_scenarios.dart';
import 'package:appnest_server/src/modules/builder/provider.dart';
import 'package:appnest_server/src/modules/builder/nemotron_routes.dart';
import 'package:crypto/crypto.dart';

void main(List<String> args) {
  final receipts = <String, String>{};
  final scenarios = [...nemotronScenarios(), ...nemotronSequences()];
  for (final profile in [
    NvidiaNemotronProfile.baseline,
    NvidiaNemotronProfile.boundedReasoning,
    NvidiaNemotronProfile.contractReasoning,
  ]) {
    for (final model in [
      'nvidia/nemotron-3-super-120b-a12b',
      'nvidia/nemotron-3-ultra-550b-a55b',
      'z-ai/glm-5.3',
    ]) {
      final provider = ChatCompletionProvider(
        Uri.parse(nvidiaEvaluationBase),
        model,
        'synthetic-unused-key',
        nvidiaModelEvaluation: true,
        nemotronProfile: profile,
      );
      for (final scenario in scenarios) {
        for (final repair in [false, true]) {
          final guidance = scenario.operation == 'guidance';
          final authored = guidance
              ? buildGuidanceRequest(model, scenario.prompt)
              : buildAiRequest(
                  model,
                  scenario.prompt,
                  scenario.baseline,
                  editing: {'edit', 'sequence'}.contains(scenario.operation),
                  diagnostics: repair
                      ? const ['Synthetic validation diagnostic']
                      : const [],
                  rejectedOutput: repair
                      ? '{"unsupported":"synthetic rejected response"}'
                      : null,
                );
          final request = provider.adaptRequestForTransport(
            authored,
            generation: !guidance,
          );
          receipts['${profile.id}/$model/${scenario.id}/${repair ? 'repair' : 'initial'}'] =
              sha256.convert(utf8.encode(jsonEncode(request))).toString();
        }
      }
    }
  }
  File(args.single).writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(receipts)}\n',
  );
  stdout.writeln('${receipts.length} offline legacy request hashes saved.');
}

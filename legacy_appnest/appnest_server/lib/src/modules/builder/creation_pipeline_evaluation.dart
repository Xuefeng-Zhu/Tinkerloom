import 'dart:convert';

import 'package:appnest_spec/appnest_spec.dart';
import 'package:crypto/crypto.dart';

import 'creation_patch.dart';
import 'creation_plan.dart';
import 'nemotron_prompt.dart';
import 'provider.dart';
import 'scoped_creation_contract.dart';

/// Explicit synthetic evaluation only. No configured application uses this.
enum CreationPipeline { baseline, scoped, plan, repair, cascade }

CreationPipeline parseCreationPipeline(
  String value,
) => CreationPipeline.values.firstWhere(
  (pipeline) => pipeline.name == value,
  orElse: () => throw const FormatException(
    'Choose --creation-pipeline=baseline, scoped, plan, repair, or cascade.',
  ),
);

const pipelineFallbackModel = 'z-ai/glm-5.3';
const pipelineTargetModel = 'nvidia/nemotron-3-super-120b-a12b';

Map<String, dynamic> creationPipelineMetadata(CreationPipeline pipeline) => {
  'version': 'appnest-creation-pipeline-v1',
  'pipeline': pipeline.name,
  'syntheticEvaluationOnly': true,
  'strictScorerUnchanged': true,
  'maxTotalCallsPerOperation': 3,
  if (pipeline == CreationPipeline.repair)
    'invalidPatchRetry':
        'full generation when the prior response is not an AppSpec',
  if (pipeline == CreationPipeline.cascade) ...{
    'fallbackModel': pipelineFallbackModel,
    'routing': 'Nemotron first; remaining bounded attempts use GLM',
  },
};

String _digest(String value) => sha256.convert(utf8.encode(value)).toString();

/// The provider authors a new response grammar only for new creation trials.
/// Existing edit/guidance payloads and the ordinary provider remain unchanged.
class ExperimentalCreationProvider extends ChatCompletionProvider {
  final CreationPipeline pipeline;
  Map<String, dynamic>? _evidence;
  Map<String, dynamic>? _repairBase;
  bool _patchRequest = false;

  ExperimentalCreationProvider(
    super.base,
    super.model,
    super.key, {
    required this.pipeline,
    super.clientFactory,
  }) : super(
         nvidiaModelEvaluation: true,
         nemotronProfile: NvidiaNemotronProfile.efficientCreation,
       ) {
    if (pipeline == CreationPipeline.baseline ||
        pipeline == CreationPipeline.cascade ||
        model != pipelineTargetModel) {
      throw ArgumentError(
        'Select a single Super creation pipeline experiment.',
      );
    }
  }

  @override
  Map<String, dynamic> adaptRequestForTransport(
    Map<String, dynamic> body, {
    required bool generation,
  }) {
    if (!generation || !isNemotronCreationRequest(body['messages'] as List)) {
      return super.adaptRequestForTransport(body, generation: generation);
    }
    final original = super.adaptRequestForTransport(body, generation: true);
    _repairBase = null;
    _patchRequest = false;
    final authored = switch (pipeline) {
      CreationPipeline.scoped => buildScopedCreationRequest(body),
      CreationPipeline.plan => buildCreationPlanRequest(body),
      CreationPipeline.repair => buildCreationPatchRequest(body),
      _ => throw StateError('Unsupported experiment'),
    };
    if (pipeline == CreationPipeline.repair) {
      _patchRequest = isCreationPatchRequest(authored);
      if (_patchRequest) _repairBase = creationPatchBase(body);
    }
    final adapted = super.adaptRequestForTransport(authored, generation: true);
    if (pipeline == CreationPipeline.plan || _patchRequest) {
      final system = (adapted['messages'] as List).first as Map;
      system['content'] = (system['content'] as String).replaceAll(
        ' $nemotronCreationChecklist',
        '',
      );
    }
    final encoded = jsonEncode(adapted);
    _evidence = {
      ...creationPipelineMetadata(pipeline),
      'servedByModel': model,
      'requestSha256': _digest(encoded),
      'requestBytes': utf8.encode(encoded).length,
      'controlRequestBytes': utf8.encode(jsonEncode(original)).length,
      'responseProtocol': pipeline == CreationPipeline.plan
          ? 'creationPlanVersion:1'
          : _patchRequest
          ? 'boundedCreationChanges'
          : 'AppSpec',
      if (_repairBase != null) 'repairBase': _repairBase,
    };
    return adapted;
  }

  @override
  Future<AiResult> generate(
    String request,
    AppSpec current, {
    required bool editing,
    List<String> diagnostics = const [],
    String? rejectedOutput,
  }) async {
    _evidence = null;
    AiResult raw;
    try {
      raw = await super.generate(
        request,
        current,
        editing: editing,
        diagnostics: diagnostics,
        rejectedOutput: rejectedOutput,
      );
    } on AiResponseException catch (error) {
      throw AiResponseException(
        error.kind,
        error.message,
        statusCode: error.statusCode,
        providerErrorType: error.providerErrorType,
        retryAfter: error.retryAfter,
        retryable: error.retryable,
        usage: error.usage,
        syntheticResponse: error.syntheticResponse,
        pipelineEvidence: _evidence,
      );
    }
    if (_evidence == null) return raw;
    final evidence = <String, dynamic>{
      ..._evidence!,
      'rawResponseSha256': _digest(raw.text),
    };
    try {
      final derived = deriveCreationPipelineResponse(raw.text, evidence);
      evidence['derivedResponseSha256'] = _digest(derived);
      return AiResult(
        derived,
        raw.provider,
        raw.model,
        raw.usage,
        rawText: raw.text,
        pipelineEvidence: evidence,
      );
    } on SpecException catch (error) {
      throw AiResponseException(
        'pipeline_validation',
        error.message,
        usage: raw.usage,
        syntheticResponse: raw.text,
        pipelineEvidence: evidence,
      );
    } on AiResponseException catch (error) {
      throw AiResponseException(
        'pipeline_validation',
        error.message,
        usage: raw.usage,
        syntheticResponse: raw.text,
        pipelineEvidence: evidence,
      );
    } on FormatException catch (error) {
      throw AiResponseException(
        'pipeline_validation',
        error.message,
        usage: raw.usage,
        syntheticResponse: raw.text,
        pipelineEvidence: evidence,
      );
    }
  }
}

/// Replay derives the candidate from the saved raw response, never trusting a
/// saved candidate. The unchanged strict scorer runs on this result afterward.
String deriveCreationPipelineResponse(
  String raw,
  Map<String, dynamic> evidence,
) {
  final recordedHash = evidence['rawResponseSha256'];
  if (recordedHash != null && recordedHash != _digest(raw)) {
    throw const SpecException('Pipeline raw response hash mismatch');
  }
  final protocol = evidence['responseProtocol'];
  final result = switch (protocol) {
    'creationPlanVersion:1' => jsonEncode(
      compileCreationPlan(parseAiOutput(raw)),
    ),
    'boundedCreationChanges' => _derivePatch(raw, evidence),
    _ => raw,
  };
  final derivedHash = evidence['derivedResponseSha256'];
  if (derivedHash != null && derivedHash != _digest(result)) {
    throw const SpecException('Pipeline derived response hash mismatch');
  }
  return result;
}

String _derivePatch(String raw, Map<String, dynamic> evidence) {
  final output = parseAiOutput(raw);
  if (output.containsKey('unsupported')) {
    keys(output, {'unsupported'}, 'creation repair response');
    str(output['unsupported'], 'unsupported reason', max: 500);
    return raw;
  }
  return jsonEncode(
    applyCreationPatch(
      Map<String, dynamic>.from(evidence['repairBase'] as Map),
      output,
    ),
  );
}

/// One call per runner attempt: GLM fallback spends the remaining original
/// attempt budget and follows the runner's same pacing and stop guards.
class CreationCascade {
  final ChatCompletionProvider primary, fallback;
  CreationCascade(this.primary, this.fallback);

  Future<AiResult> generate(
    String request,
    AppSpec current, {
    required bool editing,
    List<String> diagnostics = const [],
    String? rejectedOutput,
    bool fallbackPreviouslyUsed = false,
  }) async {
    final provider = diagnostics.isEmpty ? primary : fallback;
    final previous = fallbackPreviouslyUsed ? rejectedOutput : null;
    final body = provider.adaptRequestForTransport(
      buildAiRequest(
        provider.model,
        request,
        current,
        editing: editing,
        diagnostics: diagnostics,
        rejectedOutput: previous,
      ),
      generation: true,
    );
    final encoded = jsonEncode(body);
    final evidence = {
      ...creationPipelineMetadata(CreationPipeline.cascade),
      'servedByModel': provider.model,
      'responseProtocol': 'AppSpec',
      'requestSha256': _digest(encoded),
      'requestBytes': utf8.encode(encoded).length,
    };
    // The first fallback starts independently from the original request. A
    // later GLM repair may use only the preceding response and diagnostics.
    try {
      final result = await provider.generate(
        request,
        current,
        editing: editing,
        diagnostics: diagnostics,
        rejectedOutput: previous,
      );
      return AiResult(
        result.text,
        result.provider,
        result.model,
        result.usage,
        rawText: result.text,
        pipelineEvidence: {
          ...evidence,
          'rawResponseSha256': _digest(result.text),
          'derivedResponseSha256': _digest(result.text),
        },
      );
    } on AiResponseException catch (error) {
      throw AiResponseException(
        error.kind,
        error.message,
        statusCode: error.statusCode,
        providerErrorType: error.providerErrorType,
        retryAfter: error.retryAfter,
        retryable: error.retryable,
        usage: error.usage,
        syntheticResponse: error.syntheticResponse,
        pipelineEvidence: evidence,
      );
    }
  }
}

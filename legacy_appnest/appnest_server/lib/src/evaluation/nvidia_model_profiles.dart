import 'dart:convert';

/// Default/application NVIDIA selection remains the previously evaluated set.
const nvidiaNemotronModels = <String>[
  'nvidia/nemotron-3.5-lightning-30b-a3b',
  'nvidia/nemotron-3-super-120b-a12b',
  'nvidia/nemotron-3-ultra-550b-a55b',
  'nvidia/nemotron-3-nano-omni-30b-a3b-reasoning',
];

/// Additional exact IDs require explicit benchmark selection via --models.
const nvidiaComparisonModels = <String>[
  'moonshotai/kimi-k3',
  'z-ai/glm-5.3',
  'deepseek-ai/deepseek-v4.1-flash',
  'z-ai/glm-5.3-flash',
  'google/gemma-4-31b-it',
  'poolside/laguna-xs-2.1',
];

const nvidiaEvaluationModels = <String>[
  ...nvidiaNemotronModels,
  ...nvidiaComparisonModels,
];

/// Explicit benchmark experiments never change the configured app's default.
enum NvidiaNemotronProfile {
  baseline('baseline'),
  boundedReasoning('bounded-reasoning'),
  contractReasoning('contract-reasoning'),
  contractOnly('contract-only'),
  efficientCreation('efficient-creation'),
  publisherCreation('publisher-creation');

  final String id;
  const NvidiaNemotronProfile(this.id);
}

NvidiaNemotronProfile parseNvidiaNemotronProfile(String value) =>
    NvidiaNemotronProfile.values.firstWhere(
      (profile) => profile.id == value,
      orElse: () => throw const FormatException(
        'Choose --nemotron-profile=baseline, bounded-reasoning, '
        'contract-reasoning, contract-only, efficient-creation, or publisher-creation.',
      ),
    );

const _boundedReasoningModels = {
  'nvidia/nemotron-3-super-120b-a12b',
  'nvidia/nemotron-3-ultra-550b-a55b',
};
const _boundedReasoningControls = {'z-ai/glm-5.3', 'z-ai/glm-5.3-flash'};

/// Validate before catalog access or credential construction. GLM controls keep
/// their existing profiles; at least one actual experimental model is required.
void validateNvidiaNemotronProfileSelection(
  List<String> models,
  String provider,
  NvidiaNemotronProfile profile,
) {
  if (profile == NvidiaNemotronProfile.baseline) return;
  if (provider != 'nvidia' ||
      !models.any(_boundedReasoningModels.contains) ||
      models.any(
        (model) =>
            !_boundedReasoningModels.contains(model) &&
            !_boundedReasoningControls.contains(model),
      )) {
    throw const FormatException(
      'Reasoning experiments require NVIDIA Super and/or Ultra; only GLM 5.3 '
      'and GLM 5.3 Flash may accompany them as unchanged controls.',
    );
  }
}

/// Fixed, reviewed transport parameters and their primary-source provenance.
/// This registry does not establish free availability or credential access:
/// those are checked separately immediately before completion dispatch.
class NvidiaEvaluationProfile {
  final String model, family, catalogPath, name, reasoning;
  final String? promptContract;
  final String topP;
  final Map<String, dynamic> requestOverrides;
  final Map<String, dynamic>? creationRequestOverrides;
  final List<String> documentationUrls;
  final Map<String, String> parameterSources;
  final List<String> limitations;

  const NvidiaEvaluationProfile({
    required this.model,
    required this.family,
    required this.catalogPath,
    required this.name,
    required this.reasoning,
    required this.requestOverrides,
    required this.documentationUrls,
    required this.parameterSources,
    this.promptContract,
    this.creationRequestOverrides,
    this.topP = 'model default; omitted',
    this.limitations = const [],
  });

  String get catalogUrl => 'https://build.nvidia.com/$catalogPath';

  /// Creation selects its complete reviewed override map. Never merge it with
  /// thinking-off defaults, which would conflict with creation reasoning.
  Map<String, dynamic> transportOverrides({bool creation = false}) =>
      jsonDecode(
        jsonEncode(
          creation && creationRequestOverrides != null
              ? creationRequestOverrides
              : requestOverrides,
        ),
      ) as Map<String, dynamic>;

  Map<String, dynamic> toJson() => {
    'profile': name,
    'family': family,
    'catalogUrl': catalogUrl,
    'reasoning': reasoning,
    if (promptContract != null) 'promptContract': promptContract,
    'requestOverrides': transportOverrides(),
    if (creationRequestOverrides != null) ...{
      'creationRequestOverrides': transportOverrides(creation: true),
      'operationOverrides': {
        'create': transportOverrides(creation: true),
        'unsupported': transportOverrides(creation: true),
        'edit': transportOverrides(),
        'sequence': transportOverrides(),
        'guidance': transportOverrides(),
      },
    },
    'responseContract': 'complete JSON schema supplied as instructions',
    'generationDeadlineSeconds': 90,
    'guidanceDeadlineSeconds': 20,
    'generationMaxTokens': {
      'initial': 8000,
      'recognizedCreationTruncation': 12000,
    },
    'guidanceMaxTokens': 2048,
    'topP': topP,
    'documentationUrls': documentationUrls.toList(),
    'parameterSources': Map<String, String>.from(parameterSources),
    'limitations': limitations.toList(),
  };
}

NvidiaEvaluationProfile nvidiaEvaluationProfile(
  String model, {
  NvidiaNemotronProfile nemotronProfile = NvidiaNemotronProfile.baseline,
}) {
  if (nemotronProfile != NvidiaNemotronProfile.baseline) {
    if (_boundedReasoningModels.contains(model)) {
      final superModel = model == 'nvidia/nemotron-3-super-120b-a12b';
      final effort = superModel ? 'low' : 'medium';
      final contract =
          nemotronProfile == NvidiaNemotronProfile.contractReasoning;
      final documentation =
          'https://docs.api.nvidia.com/nim/reference/'
          '${superModel ? 'nvidia-nemotron-3-super-120b-a12b' : 'nvidia-nemotron-3-ultra-550b-a55b'}-infer';
      if (nemotronProfile == NvidiaNemotronProfile.publisherCreation) {
        final modelcard = 'https://build.nvidia.com/$model/modelcard';
        return NvidiaEvaluationProfile(
          model: model,
          family: 'Nemotron',
          catalogPath: model,
          name:
              'nvidia-nemotron-instruction-schema-publisher-creation-$effort-checklist-v1',
          reasoning:
              'creation: $effort effort; no explicit reasoning budget; '
              'edit/guidance: thinking disabled',
          promptContract: 'nemotron-creation-checklist-v1',
          requestOverrides: const {
            'stream': false,
            'chat_template_kwargs': {'enable_thinking': false},
          },
          creationRequestOverrides: {
            'stream': false,
            'reasoning_effort': effort,
            'temperature': 1.0,
            'top_p': 0.95,
          },
          topP:
              'creation/unsupported: 0.95; '
              'edit/sequence/guidance: model default; omitted',
          documentationUrls: [
            modelcard,
            documentation,
            if (!superModel) 'https://huggingface.co/nvidia/NVIDIA-Nemotron-3-Ultra-550B-A55B-BF16/blob/main/generation_config.json',
          ],
          parameterSources: {
            'stream': documentation,
            'chat_template_kwargs.enable_thinking': modelcard,
            'reasoning_effort': documentation,
            'temperature': modelcard,
            'top_p': modelcard,
          },
          limitations: const [
            'Opt-in experiment; the configured application retains thinking-off.',
            'Creation/unsupported applies publisher temperature 1.0 and top_p '
                '0.95 with the unchanged creation checklist. Edits/sequences '
                'retain baseline temperature 0; guidance retains baseline '
                'omitted temperature; top_p is omitted for all three. '
                'GLM controls remain unchanged.',
            'No explicit reasoning budget is sent. Endpoint defaults still '
                'apply within unchanged 8000/12000 total completion tokens, '
                '90-second generation and 20-second guidance bounds. These '
                'limits do not establish maximal model capability.',
          ],
        );
      }
      if (nemotronProfile == NvidiaNemotronProfile.contractOnly ||
          nemotronProfile == NvidiaNemotronProfile.efficientCreation) {
        final efficient =
            nemotronProfile == NvidiaNemotronProfile.efficientCreation;
        final modelcard = 'https://build.nvidia.com/$model/modelcard';
        const thinkingOff = {
          'stream': false,
          'chat_template_kwargs': {'enable_thinking': false},
        };
        return NvidiaEvaluationProfile(
          model: model,
          family: 'Nemotron',
          catalogPath: model,
          name: efficient
              ? 'nvidia-nemotron-instruction-schema-creation-$effort-checklist-v1'
              : 'nvidia-nemotron-instruction-schema-thinking-off-creation-checklist-v1',
          reasoning: efficient
              ? 'creation: $effort effort; no explicit reasoning budget; '
                    'edit/guidance: thinking disabled'
              : 'thinking disabled for every operation',
          promptContract: 'nemotron-creation-checklist-v1',
          requestOverrides: thinkingOff,
          creationRequestOverrides: efficient
              ? {'stream': false, 'reasoning_effort': effort}
              : thinkingOff,
          documentationUrls: [modelcard, documentation],
          parameterSources: {
            'stream': documentation,
            'chat_template_kwargs.enable_thinking': modelcard,
            if (efficient) 'reasoning_effort': documentation,
          },
          limitations: [
            'Opt-in experiment; the configured application retains thinking-off.',
            'The existing creation checklist is unchanged. Edit/guidance '
                'requests and unchanged GLM controls retain baseline payloads.',
            'The creation request path includes unsupported ideas; '
                'sequence/edit requests preserve baseline transport.',
            if (efficient)
              'Low/medium effort encourages shorter reasoning without a new '
                  'hard per-request reasoning budget. Endpoint defaults still '
                  'apply within unchanged total-token and deadline bounds.',
          ],
        );
      }
      return NvidiaEvaluationProfile(
        model: model,
        family: 'Nemotron',
        catalogPath: model,
        name: contract
            ? 'nvidia-nemotron-instruction-schema-$effort-budget1024-creation-checklist-v1'
            : 'nvidia-nemotron-instruction-schema-$effort-budget1024-v1',
        reasoning: '$effort effort; internal reasoning budget 1024 tokens',
        promptContract: contract ? 'nemotron-creation-checklist-v1' : null,
        requestOverrides: {
          'stream': false,
          'reasoning_effort': effort,
          'reasoning_budget': 1024,
        },
        documentationUrls: [documentation],
        parameterSources: {
          'stream': documentation,
          'reasoning_effort': documentation,
          'reasoning_budget': documentation,
        },
        limitations: [
          'Opt-in experiment; the configured application retains thinking-off.',
          'The 1024-token reasoning budget is an AppNest experimental choice, '
              'not a publisher recommendation. It shares the unchanged total '
              'completion-token and deadline bounds with final JSON output.',
          'Top-level reasoning_effort enables reasoning. No redundant '
              'chat_template_kwargs toggle is sent.',
          if (contract)
            'Creation-only contract emphasis is included; edit and guidance '
                'prompts retain their existing contract.',
        ],
      );
    }
    if (!_boundedReasoningControls.contains(model)) {
      throw ArgumentError(
        'Reasoning experiments support exact NVIDIA Super/Ultra models and GLM controls only.',
      );
    }
  }
  if (nvidiaNemotronModels.contains(model)) {
    return NvidiaEvaluationProfile(
      model: model,
      family: 'Nemotron',
      catalogPath: model,
      name: 'nvidia-instruction-schema-thinking-off-v1',
      reasoning: 'thinking disabled',
      requestOverrides: const {
        'stream': false,
        'chat_template_kwargs': {'enable_thinking': false},
      },
      documentationUrls: ['https://build.nvidia.com/$model/modelcard'],
      parameterSources: {
        'chat_template_kwargs.enable_thinking':
            'https://build.nvidia.com/$model/modelcard',
        'stream': 'https://build.nvidia.com/$model',
      },
    );
  }
  return switch (model) {
    'moonshotai/kimi-k3' => const NvidiaEvaluationProfile(
      model: 'moonshotai/kimi-k3',
      family: 'Kimi',
      catalogPath: 'moonshotai/kimi-k3',
      name: 'nvidia-kimi-k3-instruction-schema-low-v1',
      reasoning: 'always enabled; low effort requested',
      requestOverrides: {
        'stream': false,
        'temperature': 0,
        'reasoning_effort': 'low',
      },
      documentationUrls: [
        'https://docs.api.nvidia.com/nim/reference/moonshotai-kimi-k3',
        'https://docs.api.nvidia.com/nim/reference/moonshotai-kimi-k3-infer',
      ],
      parameterSources: {
        'stream': 'https://docs.api.nvidia.com/nim/reference/moonshotai-kimi-k3-infer',
        'temperature': 'https://docs.api.nvidia.com/nim/reference/moonshotai-kimi-k3-infer',
        'reasoning_effort': 'https://docs.api.nvidia.com/nim/reference/moonshotai-kimi-k3-infer',
      },
      limitations: [
        'Bounded AppNest feasibility profile; thinking cannot be disabled.',
        'Temperature 0 is supported; NVIDIA recommends 1.0. Low effort and '
            'the shared token/deadline limits do not measure maximal capability.',
      ],
    ),
    'z-ai/glm-5.3' => const NvidiaEvaluationProfile(
      model: 'z-ai/glm-5.3',
      family: 'GLM',
      catalogPath: 'z-ai/glm-5-3',
      name: 'nvidia-glm-5.3-instruction-schema-low-v1',
      reasoning: 'enabled; low effort requested; previous thinking cleared',
      requestOverrides: {
        'stream': false,
        'temperature': 0,
        'reasoning_effort': 'low',
        'chat_template_kwargs': {'clear_thinking': true},
      },
      documentationUrls: [
        'https://docs.api.nvidia.com/nim/reference/z-ai-glm-5-3',
        'https://docs.api.nvidia.com/nim/reference/z-ai-glm-5-3-infer',
        'https://recipes.vllm.ai/zai-org/GLM-5.3',
      ],
      parameterSources: {
        'stream':
            'https://docs.api.nvidia.com/nim/reference/z-ai-glm-5-3-infer',
        'temperature':
            'https://docs.api.nvidia.com/nim/reference/z-ai-glm-5-3-infer',
        'reasoning_effort':
            'https://docs.api.nvidia.com/nim/reference/z-ai-glm-5-3',
        'reasoning_effort.location': 'https://recipes.vllm.ai/zai-org/GLM-5.3',
        'chat_template_kwargs.clear_thinking':
            'https://docs.api.nvidia.com/nim/reference/z-ai-glm-5-3',
      },
      limitations: [
        'Bounded AppNest feasibility profile; no unsupported thinking-off '
            'switch is sent.',
        'Temperature 0 is supported; the endpoint default is 0.5. Low effort '
            'and shared token/deadline limits do not measure maximal capability.',
      ],
    ),
    'deepseek-ai/deepseek-v4.1-flash' => const NvidiaEvaluationProfile(
      model: 'deepseek-ai/deepseek-v4.1-flash',
      family: 'DeepSeek',
      catalogPath: 'deepseek-ai/deepseek-v4.1-flash',
      name: 'nvidia-deepseek-v4.1-flash-instruction-schema-default-v1',
      reasoning: 'model default; no documented NVIDIA HTTP override sent',
      requestOverrides: {'stream': false, 'temperature': 0},
      documentationUrls: [
        'https://docs.api.nvidia.com/nim/reference/nvidia-deepseek-v4_1-flash-infer',
        'https://build.nvidia.com/deepseek-ai/deepseek-v4.1-flash/modelcard',
      ],
      parameterSources: {
        'stream': 'https://docs.api.nvidia.com/nim/reference/nvidia-deepseek-v4_1-flash-infer',
        'temperature': 'https://docs.api.nvidia.com/nim/reference/nvidia-deepseek-v4_1-flash-infer',
      },
      limitations: [
        'Bounded AppNest feasibility profile; source-model numeric reasoning '
            'controls are not assumed to be NVIDIA HTTP parameters.',
        'Temperature 0 is supported; NVIDIA recommends 1.0. Shared 8000/12000 '
            'generation tokens and 90-second deadline are below publisher '
            'recommendations and do not measure maximal capability.',
      ],
    ),
    'z-ai/glm-5.3-flash' => const NvidiaEvaluationProfile(
      model: 'z-ai/glm-5.3-flash',
      family: 'GLM',
      catalogPath: 'z-ai/glm-5-3-flash',
      name: 'nvidia-glm-5.3-flash-instruction-schema-low-v1',
      reasoning:
          'always enabled; low effort requested; previous thinking cleared',
      requestOverrides: {
        'stream': false,
        'temperature': 0,
        'reasoning_effort': 'low',
        'chat_template_kwargs': {'clear_thinking': true},
      },
      documentationUrls: [
        'https://docs.api.nvidia.com/nim/reference/z-ai-glm-5-3-flash',
        'https://docs.api.nvidia.com/nim/reference/z-ai-glm-5-3-flash-infer',
        'https://recipes.vllm.ai/zai-org/GLM-5.3-Flash',
      ],
      parameterSources: {
        'stream': 'https://docs.api.nvidia.com/nim/reference/z-ai-glm-5-3-flash-infer',
        'temperature': 'https://docs.api.nvidia.com/nim/reference/z-ai-glm-5-3-flash-infer',
        'reasoning_effort':
            'https://docs.api.nvidia.com/nim/reference/z-ai-glm-5-3-flash',
        'reasoning_effort.location':
            'https://recipes.vllm.ai/zai-org/GLM-5.3-Flash',
        'chat_template_kwargs.clear_thinking':
            'https://docs.api.nvidia.com/nim/reference/z-ai-glm-5-3-flash',
      },
      limitations: [
        'Bounded AppNest feasibility profile; thinking cannot be disabled.',
        'Temperature 0 is supported; the endpoint default is 0.5. Low effort '
            'and shared token/deadline limits do not measure maximal capability.',
      ],
    ),
    'google/gemma-4-31b-it' => const NvidiaEvaluationProfile(
      model: 'google/gemma-4-31b-it',
      family: 'Gemma',
      catalogPath: 'google/gemma-4-31b-it',
      name: 'nvidia-gemma-4-31b-it-instruction-schema-thinking-off-v1',
      reasoning: 'thinking disabled',
      requestOverrides: {
        'stream': false,
        'temperature': 0,
        'chat_template_kwargs': {'enable_thinking': false},
      },
      documentationUrls: [
        'https://docs.api.nvidia.com/nim/reference/google-gemma-4-31b-it-infer',
        'https://build.nvidia.com/google/gemma-4-31b-it/modelcard',
      ],
      parameterSources: {
        'stream': 'https://docs.api.nvidia.com/nim/reference/google-gemma-4-31b-it-infer',
        'temperature': 'https://docs.api.nvidia.com/nim/reference/google-gemma-4-31b-it-infer',
        'chat_template_kwargs.enable_thinking': 'https://docs.api.nvidia.com/nim/reference/google-gemma-4-31b-it-infer',
      },
      limitations: [
        'Bounded AppNest feasibility profile with documented thinking-off '
            'control and shared token/deadline limits; not maximal capability.',
      ],
    ),
    'poolside/laguna-xs-2.1' => const NvidiaEvaluationProfile(
      model: 'poolside/laguna-xs-2.1',
      family: 'Laguna',
      catalogPath: 'poolside/laguna-xs-2.1',
      name: 'nvidia-laguna-xs-2.1-instruction-schema-default-v1',
      reasoning: 'model default; no documented NVIDIA HTTP override sent',
      requestOverrides: {'stream': false, 'temperature': 0},
      documentationUrls: [
        'https://docs.api.nvidia.com/nim/reference/poolside-laguna-xs-2-1-infer',
        'https://docs.api.nvidia.com/nim/reference/poolside-laguna-xs-2-1',
      ],
      parameterSources: {
        'stream': 'https://docs.api.nvidia.com/nim/reference/poolside-laguna-xs-2-1-infer',
        'temperature': 'https://docs.api.nvidia.com/nim/reference/poolside-laguna-xs-2-1-infer',
      },
      limitations: [
        'Bounded AppNest feasibility profile; optional source-model thinking '
            'is not assumed to expose an NVIDIA HTTP parameter.',
        'Temperature 0 is supported; the endpoint default is 1.0. Shared '
            'token/deadline limits and this instruction-only workload differ '
            'from the publisher agentic coding benchmark.',
      ],
    ),
    _ => throw ArgumentError.value(model, 'model', 'Unknown NVIDIA profile'),
  };
}

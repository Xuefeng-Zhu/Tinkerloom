import 'dart:convert';

import 'package:appnest_server/src/modules/builder/provider.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:serverpod/serverpod.dart' show Session;
import 'package:test/test.dart';

const _schemaMarker = 'Complete response schema: ';

class _PasswordSession implements Session {
  @override
  final Map<String, String> passwords;
  _PasswordSession(this.passwords);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Object? _expandInstructionSchema(Object? value, Map root) {
  if (value is List) {
    return value.map((item) => _expandInstructionSchema(item, root)).toList();
  }
  if (value is! Map) return value;
  final scope = value.containsKey(r'$defs') || value.containsKey(r'$id')
      ? value
      : root;
  if (value[r'$ref'] case final String reference) {
    expect(value.keys, [r'$ref']);
    expect(reference, startsWith(r'#/$defs/'));
    return _expandInstructionSchema(
      scope[r'$defs'][reference.substring(8)],
      scope,
    );
  }
  return {
    for (final entry in value.entries)
      if (entry.key != r'$defs')
        entry.key: _expandInstructionSchema(entry.value, scope),
  };
}

void main() {
  final current = starterTemplates()['planner']!;
  ChatCompletionProvider provider(
    String model, {
    http.Client Function()? clientFactory,
    void Function(String)? log,
  }) => ChatCompletionProvider(
    Uri.parse('https://openrouter.ai/api/v1'),
    model,
    'synthetic-key',
    freeNemotronEvaluation: true,
    clientFactory: clientFactory,
    log: log,
  );

  ChatCompletionProvider nvidiaProvider(
    String model, {
    http.Client Function()? clientFactory,
  }) => ChatCompletionProvider(
    Uri.parse('https://integrate.api.nvidia.com/v1'),
    model,
    'synthetic-nvidia-key',
    nvidiaNemotronEvaluation: true,
    clientFactory: clientFactory,
  );

  for (final model in nvidiaNemotronModels) {
    for (final editing in [false, true]) {
      test(
        '$model NVIDIA ${editing ? 'edit' : 'create'} uses instruction schema without reasoning',
        () {
          final source = buildAiRequest(
            model,
            'A daily planner',
            current,
            editing: editing,
          );
          final before = jsonEncode(source);
          final evaluator = nvidiaProvider(model);
          final adapted = evaluator.adaptRequestForTransport(
            source,
            generation: true,
          );
          expect(jsonEncode(source), before);
          expect(adapted['model'], model);
          expect(adapted['max_tokens'], 8000);
          expect(adapted['temperature'], 0);
          expect(adapted['stream'], isFalse);
          expect(adapted['chat_template_kwargs'], {'enable_thinking': false});
          for (final key in [
            'response_format',
            'provider',
            'reasoning',
            'reasoning_effort',
            'models',
            'plugins',
            'tools',
          ]) {
            expect(adapted.containsKey(key), isFalse, reason: key);
          }
          final system = adapted['messages'].first['content'] as String;
          final compacted = jsonDecode(system.split(_schemaMarker).last) as Map;
          final original =
              source['response_format']['json_schema']['schema'] as Map;
          expect(
            _expandInstructionSchema(compacted, compacted),
            _expandInstructionSchema(original, original),
          );
          expect(
            system,
            contains('This request supplies its JSON Schema as instructions.'),
          );
          expect(adapted['messages'].skip(1), source['messages'].skip(1));
          expect(evaluator.generationDeadline, const Duration(seconds: 90));
          expect(
            evaluator.transportProfile,
            'nvidia-instruction-schema-thinking-off-v1',
          );
        },
      );
    }
    test(
      '$model NVIDIA guidance keeps grammar and disables streaming and thinking',
      () async {
        final source = buildGuidanceRequest(model, 'A club app');
        final before = jsonEncode(source);
        final evaluator = nvidiaProvider(
          model,
          clientFactory: () => MockClient((request) async {
            expect(request.followRedirects, isFalse);
            expect(request.headers['Accept'], 'application/json');
            expect(
              request.url.toString(),
              'https://integrate.api.nvidia.com/v1/chat/completions',
            );
            final adapted = jsonDecode(request.body) as Map;
            expect(adapted['stream'], isFalse);
            expect(adapted['chat_template_kwargs'], {'enable_thinking': false});
            expect(adapted['messages'], source['messages']);
            expect(adapted.containsKey('provider'), isFalse);
            expect(adapted.containsKey('response_format'), isFalse);
            return http.Response(
              jsonEncode({
                'choices': [
                  {
                    'finish_reason': 'stop',
                    'message': {
                      'content': '{"needsClarification":false,"questions":[]}',
                    },
                  },
                ],
              }),
              200,
            );
          }),
        );
        final adapted = evaluator.adaptRequestForTransport(
          source,
          generation: false,
        );
        expect(jsonEncode(source), before);
        expect(
          adapted['messages'].first['content'],
          contains('exactly those two keys'),
        );
        expect(await evaluator.suggestQuestions('A club app'), isEmpty);
      },
    );
  }

  test(
    'NVIDIA profile rejects any different API origin, model, or mixed opt-in',
    () {
      for (final base in [
        'http://integrate.api.nvidia.com/v1',
        'https://integrate.api.nvidia.com.evil.test/v1',
        'https://user@integrate.api.nvidia.com/v1',
        'https://integrate.api.nvidia.com:444/v1',
        'https://integrate.api.nvidia.com/v2',
        'https://integrate.api.nvidia.com/v1?route=other',
        'https://integrate.api.nvidia.com/v1#fragment',
      ]) {
        expect(
          () => ChatCompletionProvider(
            Uri.parse(base),
            nvidiaNemotronModels.first,
            'synthetic-key',
            nvidiaNemotronEvaluation: true,
          ),
          throwsArgumentError,
        );
      }
      expect(
        () => nvidiaProvider(freeNemotronModels.first),
        throwsArgumentError,
      );
      expect(
        () => ChatCompletionProvider(
          Uri.parse('https://integrate.api.nvidia.com/v1'),
          nvidiaNemotronModels.first,
          'key',
          freeNemotronEvaluation: true,
          nvidiaNemotronEvaluation: true,
        ),
        throwsArgumentError,
      );
    },
  );

  test('NVIDIA rejects alternate routes and extensions; preserves bounded truncation repair', () {
    final evaluator = nvidiaProvider(nvidiaNemotronModels[2]);
    final source = buildAiRequest(
      evaluator.model,
      'A daily planner',
      current,
      editing: false,
      diagnostics: ['AI output reached the token limit before finishing.'],
    );
    expect(
      evaluator.adaptRequestForTransport(
        source,
        generation: true,
      )['max_tokens'],
      12000,
    );
    for (final key in [
      'models',
      'plugins',
      'tools',
      'provider',
      'route',
      'stream',
      'chat_template_kwargs',
      'reasoning',
    ]) {
      expect(
        () => evaluator.adaptRequestForTransport({
          ...source,
          key: [],
        }, generation: true),
        throwsArgumentError,
      );
    }
    expect(
      () => evaluator.adaptRequestForTransport({
        ...source,
        'response_format': null,
      }, generation: true),
      throwsArgumentError,
    );
  });

  test('configured NVIDIA uses its own key and fails closed without it', () {
    final passwords = <String, String>{
      'AI_BASE_URL': 'https://integrate.api.nvidia.com/v1',
      'AI_MODEL': nvidiaNemotronModels[2],
      'AI_API_KEY': 'synthetic-other-provider-key',
    };
    expect(
      ChatCompletionProvider.configured(_PasswordSession(passwords)),
      isNull,
    );
    passwords['NVIDIA_API_KEY'] = 'synthetic-nvidia-key';
    final configured = ChatCompletionProvider.configured(
      _PasswordSession(passwords),
    )!;
    expect(configured.key, 'synthetic-nvidia-key');
    expect(configured.nvidiaNemotronEvaluation, isTrue);
    passwords.remove('AI_API_KEY');
    expect(
      ChatCompletionProvider.configured(_PasswordSession(passwords)),
      isNotNull,
    );
    for (final base in [
      'http://integrate.api.nvidia.com/v1',
      'https://integrate.api.nvidia.com/other',
    ]) {
      expect(
        ChatCompletionProvider.configured(
          _PasswordSession({...passwords, 'AI_BASE_URL': base}),
        ),
        isNull,
      );
    }
  });

  test(
    'configured other providers retain the existing AI_API_KEY contract',
    () {
      final configured = ChatCompletionProvider.configured(
        _PasswordSession({
          'AI_BASE_URL': 'https://openrouter.ai/api/v1',
          'AI_MODEL': freeNemotronModels[2],
          'AI_API_KEY': 'synthetic-openrouter-key',
          'NVIDIA_API_KEY': 'synthetic-nvidia-key',
        }),
      )!;
      expect(configured.key, 'synthetic-openrouter-key');
      expect(configured.nvidiaNemotronEvaluation, isFalse);
    },
  );

  test(
    'NVIDIA generation disables redirects and retains failed-completion usage',
    () async {
      final evaluator = nvidiaProvider(
        nvidiaNemotronModels.first,
        clientFactory: () => MockClient((request) async {
          expect(request.followRedirects, isFalse);
          expect(request.headers['Accept'], 'application/json');
          final body = jsonDecode(request.body) as Map;
          expect(body['stream'], isFalse);
          expect(body.containsKey('provider'), isFalse);
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'finish_reason': 'length',
                  'message': {'content': 'synthetic unfinished answer'},
                },
              ],
              'usage': {'prompt_tokens': 9, 'completion_tokens': 8},
            }),
            200,
          );
        }),
      );
      await expectLater(
        evaluator.generate('A daily planner', current, editing: false),
        throwsA(
          isA<AiResponseException>()
              .having((e) => e.usage, 'usage', {
                'prompt_tokens': 9,
                'completion_tokens': 8,
              })
              .having(
                (e) => e.syntheticResponse,
                'synthetic response',
                'synthetic unfinished answer',
              ),
        ),
      );
    },
  );

  test('NVIDIA accepted asynchronous work is indeterminate and cannot be blindly retried', () async {
    final evaluator = nvidiaProvider(
      nvidiaNemotronModels.first,
      clientFactory: () => MockClient((_) async => http.Response('', 202)),
    );
    await expectLater(
      evaluator.generate('A daily planner', current, editing: false),
      throwsA(
        isA<AiResponseException>()
            .having((e) => e.kind, 'kind', 'indeterminate')
            .having((e) => e.statusCode, 'status', 202)
            .having((e) => e.retryable, 'retryable', isFalse),
      ),
    );
  });

  for (final model in freeNemotronModels) {
    final structured = model == freeNemotronModels[1];
    final medium = structured || model == freeNemotronModels[2];
    for (final editing in [false, true]) {
      test(
        '$model ${editing ? 'edit' : 'create'} uses its fixed free contract',
        () {
          final source = buildAiRequest(
            model,
            editing ? 'Rename the app to Weekend Planner' : 'A daily planner',
            current,
            editing: editing,
          );
          final before = jsonEncode(source);
          final adapted = provider(model).adaptRequestForTransport(
            source,
            generation: true,
          );
          expect(jsonEncode(source), before);
          expect(adapted['model'], model);
          expect(adapted['provider'], {
            'allow_fallbacks': false,
            'max_price': {'prompt': 0, 'completion': 0},
            if (structured) 'require_parameters': true,
          });
          expect(adapted['max_tokens'], 8000);
          expect(adapted['temperature'], source['temperature']);
          expect(adapted['reasoning'], medium ? {'effort': 'medium'} : isNull);
          for (final key in ['models', 'plugins', 'tools', 'route']) {
            expect(adapted.containsKey(key), isFalse);
          }
          if (structured) {
            expect(adapted['response_format'], source['response_format']);
            expect(adapted['messages'], source['messages']);
            expect(
              provider(model).transportProfile,
              'openrouter-free-json-schema-v1',
            );
          } else {
            expect(adapted.containsKey('response_format'), isFalse);
            final system = adapted['messages'].first['content'] as String;
            final compacted =
                jsonDecode(system.split(_schemaMarker).last) as Map;
            final schema =
                source['response_format']['json_schema']['schema'] as Map;
            expect(system.split(_schemaMarker), hasLength(2));
            expect(
              _expandInstructionSchema(compacted, compacted),
              _expandInstructionSchema(schema, schema),
            );
            expect(system, isNot(contains('response_format')));
            expect(adapted['messages'].skip(1), source['messages'].skip(1));
            expect(
              provider(model).transportProfile,
              'openrouter-free-instruction-schema-v1',
            );
          }
        },
      );
    }

    test(
      '$model guidance keeps its full decision grammar and free routing',
      () {
        final source = buildGuidanceRequest(
          model,
          'A club app',
          definition: current,
        );
        final before = jsonEncode(source);
        final adapted = provider(model).adaptRequestForTransport(
          source,
          generation: false,
        );
        expect(jsonEncode(source), before);
        expect(adapted['max_tokens'], 2048);
        expect(adapted['messages'], source['messages']);
        expect(
          adapted['messages'].first['content'],
          contains('exactly those two keys'),
        );
        expect(
          adapted['messages'].first['content'],
          contains('needsClarification'),
        );
        expect(
          adapted['response_format'],
          structured ? {'type': 'json_object'} : isNull,
        );
        expect(adapted['provider'], {
          'allow_fallbacks': false,
          'max_price': {'prompt': 0, 'completion': 0},
          if (structured) 'require_parameters': true,
        });
        expect(adapted['reasoning'], medium ? {'effort': 'medium'} : isNull);
        expect(provider(model).generationDeadline, const Duration(seconds: 90));
      },
    );
  }

  test('evaluation accepts canonical base with one trailing slash', () {
    expect(
      ChatCompletionProvider(
        Uri.parse('https://openrouter.ai/api/v1/'),
        freeNemotronModels.first,
        'key',
        freeNemotronEvaluation: true,
      ).generationDeadline,
      const Duration(seconds: 90),
    );
  });

  test('evaluation rejects any different API origin, path, or model', () {
    for (final base in [
      'http://openrouter.ai/api/v1',
      'https://openrouter.ai.evil.test/api/v1',
      'https://user@openrouter.ai/api/v1',
      'https://openrouter.ai:444/api/v1',
      'https://openrouter.ai/api/v2',
      'https://openrouter.ai/api/v1?route=paid',
      'https://openrouter.ai/api/v1#fragment',
    ]) {
      expect(
        () => ChatCompletionProvider(
          Uri.parse(base),
          freeNemotronModels.first,
          'key',
          freeNemotronEvaluation: true,
        ),
        throwsArgumentError,
      );
    }
    for (final model in [
      'nvidia/nemotron-3-super-120b-a12b',
      freeNemotronModels.first.toUpperCase(),
      '${freeNemotronModels.first}-custom',
    ]) {
      expect(() => provider(model), throwsArgumentError);
    }
  });

  test(
    'evaluation rejects alternate routing and malformed authored contracts',
    () {
      final evaluator = provider(freeNemotronModels.first);
      final source = buildGuidanceRequest(evaluator.model, 'A club app');
      for (final body in [
        {...source, 'model': freeNemotronModels[1]},
        for (final key in [
          'models',
          'plugins',
          'tools',
          'tool_choice',
          'route',
          'transforms',
          'web_search_options',
          'audio',
          'provider',
        ])
          {...source, key: []},
        {...source, 'response_format': null},
        {
          ...source,
          'response_format': {'type': 'text'},
        },
      ]) {
        expect(
          () => evaluator.adaptRequestForTransport(body, generation: false),
          throwsArgumentError,
        );
      }
      expect(
        () => evaluator.adaptRequestForTransport(source, generation: true),
        throwsArgumentError,
      );
    },
  );

  test('other hosts and routes retain ordinary transport without opt-in', () {
    for (final base in [
      'https://example.test/v1',
      'https://openrouter.ai/api/v1',
    ]) {
      final ordinary = ChatCompletionProvider(
        Uri.parse(base),
        freeNemotronModels.first,
        'key',
      );
      final source = buildAiRequest(
        ordinary.model,
        'A daily planner',
        current,
        editing: false,
      );
      expect(
        ordinary.adaptRequestForTransport(source, generation: true),
        same(source),
      );
      expect(ordinary.generationDeadline, const Duration(seconds: 45));
    }
  });

  test(
    'evaluation generation forbids HTTP redirects before dispatch',
    () async {
      for (final model in freeNemotronModels) {
        final evaluator = provider(
          model,
          clientFactory: () => MockClient((request) async {
            expect(request.followRedirects, isFalse);
            expect(
              request.url.toString(),
              'https://openrouter.ai/api/v1/chat/completions',
            );
            return http.Response(
              jsonEncode({
                'choices': [
                  {
                    'finish_reason': 'stop',
                    'message': {'content': '{"unsupported":"Synthetic only"}'},
                  },
                ],
              }),
              200,
            );
          }),
        );
        await evaluator.generate('Execute code', current, editing: false);
      }
    },
  );

  test('failed evaluation completions retain usage and synthetic output without logging it', () async {
    for (final reason in ['length', 'content_filter', 'tool_calls', 'error']) {
      final logs = <String>[];
      final evaluator = provider(
        freeNemotronModels.first,
        log: logs.add,
        clientFactory: () => MockClient(
          (request) async => http.Response(
            jsonEncode({
              'choices': [
                {
                  'finish_reason': reason,
                  'message': {'content': 'synthetic-truncated-output'},
                },
              ],
              'usage': {'prompt_tokens': 80, 'completion_tokens': 30},
            }),
            200,
          ),
        ),
      );
      await expectLater(
        evaluator.generate('A daily planner', current, editing: false),
        throwsA(
          isA<AiResponseException>()
              .having((error) => error.usage, 'usage', {
                'prompt_tokens': 80,
                'completion_tokens': 30,
              })
              .having(
                (error) => error.syntheticResponse,
                'synthetic response',
                'synthetic-truncated-output',
              ),
        ),
      );
      expect(logs.single, isNot(contains('synthetic-truncated-output')));
    }
  });
}

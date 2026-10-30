import 'dart:convert';
import 'dart:io';

import 'package:appnest_spec/appnest_spec.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import '../../lib/providers/provider.dart';

// This is a generic transport fixture, not a claim about a live provider's
// current model availability or support for Tinkerloom's schema dialect.
const _base = 'https://api.tokenfactory.nebius.com/v1';
const _model = 'nvidia/nemotron-3-super-120b-a12b';
const _fixtureKey = 'fixture-key-only';

void main() {
  late HttpOverrides? previousOverrides;
  setUpAll(() {
    previousOverrides = HttpOverrides.current;
    HttpOverrides.global = _DenyNetwork();
  });
  tearDownAll(() => HttpOverrides.global = previousOverrides);

  ChatCompletionProvider configured() {
    final provider = ChatCompletionProvider.configured({
      'AI_BASE_URL': _base,
      'AI_MODEL': _model,
      'AI_API_KEY': _fixtureKey,
      'NVIDIA_API_KEY': 'different-fixture-key',
    });
    expect(provider, isNotNull);
    return provider!;
  }

  Map<String, dynamic> checkRequest(http.Request request) {
    expect(request.method, 'POST');
    expect(request.url.toString(), '$_base/chat/completions');
    expect(request.headers['Authorization'], 'Bearer $_fixtureKey');
    expect(request.headers['Content-Type'], 'application/json');
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    expect(body['model'], _model);
    return body;
  }

  http.Response completion(String content) => http.Response(
    jsonEncode({
      'choices': [
        {
          'finish_reason': 'stop',
          'message': {'content': content},
        },
      ],
      'usage': {'completion_tokens': 1},
    }),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  test('generic configuration uses the generic key and bounded deadline', () {
    final provider = configured();
    expect(provider.base.toString(), _base);
    expect(provider.model, _model);
    expect(provider.key, _fixtureKey);
    expect(provider.transportProfile, 'standard-chat-completions-v1');
    expect(provider.generationDeadline, const Duration(seconds: 45));
    expect(
      ChatCompletionProvider.configured({
        'AI_BASE_URL': _base,
        'AI_MODEL': _model,
        'NVIDIA_API_KEY': 'different-fixture-key',
      }),
      isNull,
    );
  });

  test(
    'mock generation sends the authored schema and parses its response',
    () async {
      final config = configured();
      final current = starterTemplates()['planner']!;
      final provider = ChatCompletionProvider(
        config.base,
        config.model,
        config.key,
        clientFactory: () => MockClient((request) async {
          final body = checkRequest(request);
          final format = body['response_format'] as Map;
          expect(format['type'], 'json_schema');
          expect((format['json_schema'] as Map)['schema'], isA<Map>());
          expect(body['messages'], isA<List>());
          return completion(current.canonical);
        }),
      );
      final result = await provider.generate(
        'A planner',
        current,
        editing: false,
      );
      expect(result.provider, 'api.tokenfactory.nebius.com');
      expect(result.model, _model);
      expect(parseAiOutput(result.text), isA<Map<String, dynamic>>());
      expect(AppSpec.parse(result.text).canonical, current.canonical);
    },
  );

  test(
    'mock guidance uses JSON object mode and parses a valid decision',
    () async {
      final config = configured();
      final provider = ChatCompletionProvider(
        config.base,
        config.model,
        config.key,
        clientFactory: () => MockClient((request) async {
          final body = checkRequest(request);
          expect(body['response_format'], {'type': 'json_object'});
          return completion('{"needsClarification":false,"questions":[]}');
        }),
      );
      expect(await provider.suggestQuestions('A planner'), isEmpty);
    },
  );

  test('a mocked HTTP success does not bypass local JSON validation', () async {
    final config = configured();
    final provider = ChatCompletionProvider(
      config.base,
      config.model,
      config.key,
      clientFactory: () => MockClient((request) async {
        checkRequest(request);
        return completion('{invalid json}');
      }),
    );
    final result = await provider.generate(
      'A planner',
      starterTemplates()['planner']!,
      editing: false,
    );
    expect(
      () => parseAiOutput(result.text),
      throwsA(
        isA<AiResponseException>().having((e) => e.kind, 'kind', 'output_json'),
      ),
    );
  });
}

class _DenyNetwork extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      throw StateError('Provider unit tests forbid live network access');
}

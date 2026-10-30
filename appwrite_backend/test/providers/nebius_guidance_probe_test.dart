import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import '../../tool/nebius_guidance_probe.dart';

const _key = 'fixture-secret-only';
const _valid = <String, String>{
  'TINKERLOOM_NEBIUS_PROBE': '1',
  'TINKERLOOM_NEBIUS_PROBE_ENDPOINT': probeEndpoint,
  'TINKERLOOM_NEBIUS_PROBE_MODEL': probeModel,
  'NEBIUS_API_KEY': _key,
};

http.Response _response({
  String? model = probeModel,
  String content = '{"needsClarification":false,"questions":[]}',
  int status = 200,
}) => http.Response(
  jsonEncode({
    if (model != null) 'model': model,
    'choices': [
      {
        'finish_reason': 'stop',
        'message': {'content': content},
      },
    ],
    'usage': {'completion_tokens': 4},
  }),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  late Directory directory;
  late HttpOverrides? originalOverrides;
  setUpAll(() {
    originalOverrides = HttpOverrides.current;
    HttpOverrides.global = _DenyNetwork();
  });
  tearDownAll(() => HttpOverrides.global = originalOverrides);
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('nebius-probe-test-');
  });
  tearDown(() async => directory.delete(recursive: true));

  test('opt-in, exact target, model and credential are required', () async {
    for (final invalid in [
      {..._valid, 'TINKERLOOM_NEBIUS_PROBE': '0'},
      {..._valid, 'TINKERLOOM_NEBIUS_PROBE_ENDPOINT': 'https://example.test'},
      {..._valid, 'TINKERLOOM_NEBIUS_PROBE_MODEL': 'other-model'},
      {..._valid, 'NEBIUS_API_KEY': ''},
    ]) {
      var calls = 0;
      await expectLater(
        runGuidanceProbe(
          environment: invalid,
          receiptDirectory: directory,
          clientFactory: () {
            calls++;
            return MockClient((_) async => _response());
          },
        ),
        throwsStateError,
      );
      expect(calls, 0);
      expect(await File('${directory.path}/receipt.json').exists(), isFalse);
    }
  });

  test(
    'one mocked call writes ahead, disables redirects and validates model',
    () async {
      var calls = 0;
      final result = await runGuidanceProbe(
        environment: _valid,
        receiptDirectory: directory,
        clientFactory: () => MockClient((request) async {
          calls++;
          final journal =
              jsonDecode(
                    File('${directory.path}/receipt.json').readAsStringSync(),
                  )
                  as Map;
          expect(journal['status'], 'dispatching');
          expect(journal['requestCount'], isNull);
          expect(journal['attemptMayHaveBeenSent'], isTrue);
          expect(request.url.toString(), '$probeEndpoint/chat/completions');
          expect(request.method, 'POST');
          expect(request.followRedirects, isFalse);
          expect(request.maxRedirects, 0);
          expect(request.headers['Authorization'], 'Bearer $_key');
          final body = jsonDecode(request.body) as Map;
          expect(body['model'], probeModel);
          expect(body['response_format'], {'type': 'json_object'});
          return _response();
        }),
      );
      expect(calls, 1);
      expect(result['status'], 'passed');
      expect(result['providerReportedModel'], probeModel);
      expect(result['maximumCompletionTokens'], 2048);
      expect(result['servedModelStatus'], 'matched');
      expect(result['requestCount'], 1);
      expect(result['providerUsageStatus'], 'reported');
      final receipt = File('${directory.path}/receipt.json');
      final text = await receipt.readAsString();
      expect(text, isNot(contains(_key)));
      expect(text, isNot(contains('personal reading list')));
      expect(text, isNot(contains('needsClarification')));
      expect((await receipt.stat()).mode & 63, 0);
      var duplicateCalls = 0;
      await expectLater(
        runGuidanceProbe(
          environment: _valid,
          receiptDirectory: directory,
          clientFactory: () {
            duplicateCalls++;
            return MockClient((_) async => _response());
          },
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(duplicateCalls, 0);
    },
  );

  test(
    'second request and wrong request model are refused before dispatch',
    () async {
      var calls = 0;
      final guard = OneRequestClient(
        MockClient((_) async {
          calls++;
          return _response();
        }),
      );
      http.Request request(String model, {int maxTokens = 2048}) =>
          http.Request('POST', Uri.parse('$probeEndpoint/chat/completions'))
            ..body = jsonEncode({'model': model, 'max_tokens': maxTokens});
      await expectLater(guard.send(request('wrong')), throwsStateError);
      await expectLater(
        guard.send(request(probeModel, maxTokens: 2049)),
        throwsStateError,
      );
      expect(calls, 0);
      await guard.send(request(probeModel));
      await expectLater(guard.send(request(probeModel)), throwsStateError);
      expect(calls, 1);
    },
  );

  test(
    'missing or mismatched model and malformed guidance do not pass',
    () async {
      final responses = [
        _response(model: null),
        _response(model: 'different-model'),
        _response(content: '{invalid json}'),
        http.Response('x' * 8193, 200),
      ];
      for (var i = 0; i < responses.length; i++) {
        final child = Directory('${directory.path}/case$i');
        var calls = 0;
        final result = await runGuidanceProbe(
          environment: _valid,
          receiptDirectory: child,
          clientFactory: () => MockClient((_) async {
            calls++;
            return responses[i];
          }),
        );
        expect(result['status'], 'invalid_response');
        expect(result['requestCount'], 1);
        expect(calls, 1);
      }
    },
  );

  test('lost response body after HTTP 200 remains uncertain', () async {
    var calls = 0;
    final result = await runGuidanceProbe(
      environment: _valid,
      receiptDirectory: directory,
      clientFactory: () => MockClient.streaming((request, stream) async {
        calls++;
        await stream.drain<void>();
        return http.StreamedResponse(
          Stream<List<int>>.error(
            http.ClientException('private stream details'),
          ),
          200,
        );
      }),
    );
    expect(calls, 1);
    expect(result['requestCount'], 1);
    expect(result['httpStatus'], 200);
    expect(result['status'], 'uncertain');
    expect(jsonEncode(result), isNot(contains('private stream details')));
  });

  test(
    'failed final journal update preserves ambiguous dispatch receipt',
    () async {
      var calls = 0;
      await expectLater(
        runGuidanceProbe(
          environment: _valid,
          receiptDirectory: directory,
          clientFactory: () => MockClient((_) async {
            calls++;
            await File(
              '${directory.path}/receipt.json.tmp',
            ).create(exclusive: true);
            return _response();
          }),
        ),
        throwsA(isA<FileSystemException>()),
      );
      final receipt =
          jsonDecode(
                await File('${directory.path}/receipt.json').readAsString(),
              )
              as Map;
      expect(receipt['status'], 'dispatching');
      expect(receipt['requestCount'], isNull);
      expect(receipt['attemptMayHaveBeenSent'], isTrue);
      await expectLater(
        runGuidanceProbe(
          environment: _valid,
          receiptDirectory: directory,
          clientFactory: () => MockClient((_) async {
            calls++;
            return _response();
          }),
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(calls, 1);
    },
  );

  test(
    'quota, server failures and lost replies never trigger a retry',
    () async {
      for (final status in [202, 302, 429, 500]) {
        var calls = 0;
        final result = await runGuidanceProbe(
          environment: _valid,
          receiptDirectory: Directory('${directory.path}/status$status'),
          clientFactory: () => MockClient((_) async {
            calls++;
            return _response(status: status);
          }),
        );
        expect(
          result['status'],
          status == 202 || status == 500 ? 'uncertain' : 'rejected',
        );
        expect(result['httpStatus'], status);
        expect(result['requestCount'], 1);
        expect(calls, 1);
      }
      var lostCalls = 0;
      final lost = await runGuidanceProbe(
        environment: _valid,
        receiptDirectory: Directory('${directory.path}/lost'),
        clientFactory: () => MockClient((_) async {
          lostCalls++;
          throw TimeoutException('private error contents');
        }),
      );
      expect(lost['status'], 'uncertain');
      expect(lost['requestCount'], 1);
      expect(lostCalls, 1);
      expect(jsonEncode(lost), isNot(contains('private error contents')));
    },
  );
}

class _DenyNetwork extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      throw StateError('Network is disabled for probe tests');
}

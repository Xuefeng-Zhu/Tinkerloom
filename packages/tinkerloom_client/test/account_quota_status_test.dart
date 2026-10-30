import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:tinkerloom_client/tinkerloom_client.dart';

import '../live_smoke/real_http.dart';

class _EphemeralCookies extends PathProviderPlatform {
  _EphemeralCookies(this.path);
  final String path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

Future<void> _withAccountFixture({
  required int status,
  required String body,
  required Future<void> Function(Client, RequestBudget, int Function()) verify,
}) async {
  final directory = await Directory.systemTemp.createTemp(
    'tinkerloom-account-',
  );
  final previous = PathProviderPlatform.instance;
  PathProviderPlatform.instance = _EphemeralCookies(directory.path);
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  var requests = 0;
  final subscription = server.listen((request) async {
    requests++;
    expect(request.uri.path, startsWith('/v1/account'));
    await utf8.decoder.bind(request).join();
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.json;
    request.response.write(body);
    await request.response.close();
  });
  try {
    await withRealHttp(() async {
      final budget = RequestBudget(maxAccounts: 5);
      final client = Client(
        'http://127.0.0.1:${server.port}/v1',
        projectId: 'fixture',
        functionId: 'fixture',
        budget: budget,
      );
      try {
        await verify(client, budget, () => requests);
      } finally {
        await client.close();
      }
    });
  } finally {
    PathProviderPlatform.instance = previous;
    await subscription.cancel();
    await server.close(force: true);
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}

Future<void> _invoke(Client client, String operation) => switch (operation) {
  'restore' => client.auth.restore(),
  'signin' => client.auth.signIn('fixture@example.invalid', 'fixture-password'),
  'signup' => client.auth.signUp('fixture@example.invalid', 'fixture-password'),
  'signout' => client.auth.signOutDevice(),
  _ => throw StateError('unknown fixture operation'),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final status in [402, 429]) {
    for (final body in ['', '{invalid']) {
      for (final operation in ['restore', 'signin', 'signup', 'signout']) {
        test(
          'Account $operation $status ${body.isEmpty ? 'empty' : 'malformed'} stops its budget',
          () async {
            await _withAccountFixture(
              status: status,
              body: body,
              verify: (client, budget, requests) async {
                if (operation == 'signout')
                  client.auth.setSession({'id': 'alice'});
                await expectLater(
                  _invoke(client, operation),
                  throwsA(isA<NestError>()),
                );
                expect(budget.stopped, isTrue);
                expect(budget.accounts, 1);
                expect(requests(), 1);
                if (operation == 'signout')
                  expect(client.auth.actorId, 'alice');
                await expectLater(
                  client.auth.signIn(
                    'fixture@example.invalid',
                    'fixture-password',
                  ),
                  throwsA(
                    isA<NestError>().having(
                      (e) => e.category,
                      'category',
                      'request_budget',
                    ),
                  ),
                );
                expect(
                  requests(),
                  1,
                  reason: 'No automatic retry or further auth request.',
                );
              },
            );
          },
        );
      }
    }
  }
  for (final body in [
    '',
    jsonEncode({
      'message': 'not signed in',
      'code': 401,
      'type': 'user_unauthorized',
    }),
  ]) {
    test(
      'known 401 ${body.isEmpty ? 'empty' : 'JSON'} restore remains signed out without stopping budget',
      () async {
        await _withAccountFixture(
          status: 401,
          body: body,
          verify: (client, budget, requests) async {
            await client.auth.restore();
            expect(client.auth.isAuthenticated, isFalse);
            expect(budget.stopped, isFalse);
            expect(budget.accounts, 1);
            await client.auth.restore();
            expect(requests(), 1);
          },
        );
      },
    );
  }
  test('known 401 sign-out clears the local session', () async {
    await _withAccountFixture(
      status: 401,
      body: '',
      verify: (client, budget, requests) async {
        client.auth.setSession({'id': 'alice'});
        await client.auth.signOutDevice();
        expect(client.auth.isAuthenticated, isFalse);
        expect(budget.stopped, isFalse);
        expect(requests(), 1);
      },
    );
  });
  test('malformed 401 does not falsely classify an unknown session', () async {
    await _withAccountFixture(
      status: 401,
      body: '{invalid',
      verify: (client, budget, requests) async {
        await expectLater(
          client.auth.restore(),
          throwsA(
            isA<NestError>().having(
              (e) => e.category,
              'category',
              'account_unavailable',
            ),
          ),
        );
        expect(budget.stopped, isTrue);
        expect(client.auth.isAuthenticated, isFalse);
        expect(requests(), 1);
      },
    );
  });
  test('known 400 rejection does not stop the budget', () async {
    await _withAccountFixture(
      status: 400,
      body: jsonEncode({'message': 'invalid', 'code': 400, 'type': 'fixture'}),
      verify: (client, budget, requests) async {
        await expectLater(
          client.auth.signIn('fixture@example.invalid', 'fixture-password'),
          throwsA(isA<NestError>().having((e) => e.status, 'status', 400)),
        );
        expect(budget.stopped, isFalse);
        expect(requests(), 1);
      },
    );
  });
}

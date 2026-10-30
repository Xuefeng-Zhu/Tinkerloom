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

/// Runs the actual Appwrite SDK execution transport against loopback only.
Future<void> _withFixture({
  required int status,
  required bool gateway,
  required Future<void> Function(Client, int Function()) verify,
  RequestBudget? budget,
  String? rawBody,
  String executionStatus = 'completed',
}) async {
  final directory = await Directory.systemTemp.createTemp('tinkerloom-status-');
  final previous = PathProviderPlatform.instance;
  PathProviderPlatform.instance = _EphemeralCookies(directory.path);
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  var dispatches = 0;
  final subscription = server.listen((request) async {
    dispatches++;
    expect(request.method, 'POST');
    expect(request.uri.path, '/v1/functions/fixture/executions');
    await utf8.decoder.bind(request).join();
    request.response.headers.contentType = ContentType.json;
    if (gateway) {
      request.response.statusCode = status;
      request.response.write(
        rawBody ??
            jsonEncode({
              'message': 'fixture failure',
              'code': status,
              'type': 'fixture',
            }),
      );
    } else {
      request.response.statusCode = 201;
      request.response.write(
        jsonEncode({
          'trigger': 'http',
          'status': executionStatus,
          'responseStatusCode': status,
          'responseBody': rawBody ?? jsonEncode({'error': 'fixture_failure'}),
        }),
      );
    }
    await request.response.close();
  });
  try {
    await withRealHttp(() async {
      final client = Client(
        'http://127.0.0.1:${server.port}/v1',
        projectId: 'fixture',
        functionId: 'fixture',
        auth: ClientAuth()..setSession({'id': 'alice'}),
        budget: budget,
      );
      try {
        await verify(client, () => dispatches);
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

Map<String, dynamic> _command(String operationId) => {
  'op': 'spec.generate',
  'appId': 'app',
  'operationId': operationId,
  'expectedRevision': 0,
  'expectedVersionId': null,
  'request': 'idea',
  'startFromScratch': true,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final gateway in [true, false]) {
    for (final status in [408, 425]) {
      final source = gateway ? 'gateway' : 'function';
      test(
        '$source $status keeps a mutation uncertain without replay',
        () async {
          final budget = RequestBudget();
          await _withFixture(
            status: status,
            gateway: gateway,
            budget: budget,
            verify: (client, dispatches) async {
              await expectLater(
                client.request(_command('one')),
                throwsA(
                  isA<BackendNetworkException>().having(
                    (e) => e.uncertain,
                    'uncertain',
                    isTrue,
                  ),
                ),
              );
              expect(dispatches(), 1);
              expect(budget.stopped, isTrue);
              await expectLater(
                client.request(_command('two')),
                throwsA(
                  isA<NestError>().having(
                    (e) => e.category,
                    'category',
                    'pending_command',
                  ),
                ),
              );
              expect(
                dispatches(),
                1,
                reason: 'No mutation is retried or replaced.',
              );
            },
          );
        },
      );
      test('$source $status read does not retain a mutation', () async {
        await _withFixture(
          status: status,
          gateway: gateway,
          verify: (client, dispatches) async {
            await expectLater(
              client.request({'op': 'spec.capabilities'}),
              throwsA(
                isA<BackendNetworkException>().having(
                  (e) => e.uncertain,
                  'uncertain',
                  isFalse,
                ),
              ),
            );
            await expectLater(
              client.request({'op': 'spec.templates'}),
              throwsA(
                isA<BackendNetworkException>().having(
                  (e) => e.uncertain,
                  'uncertain',
                  isFalse,
                ),
              ),
            );
            expect(dispatches(), 2);
          },
        );
      });
    }
    test(
      '${gateway ? 'gateway' : 'function'} 400 remains a definite rejection',
      () async {
        await _withFixture(
          status: 400,
          gateway: gateway,
          verify: (client, dispatches) async {
            for (final id in ['one', 'two']) {
              await expectLater(
                client.request(_command(id)),
                throwsA(
                  isA<NestError>()
                      .having((e) => e.status, 'status', 400)
                      .having((e) => e.uncertain, 'uncertain', isFalse),
                ),
              );
            }
            expect(dispatches(), 2);
          },
        );
      },
    );
    for (final status in [402, 429]) {
      test(
        '${gateway ? 'gateway' : 'function'} $status stops the smoke budget',
        () async {
          final budget = RequestBudget();
          await _withFixture(
            status: status,
            gateway: gateway,
            budget: budget,
            verify: (client, dispatches) async {
              await expectLater(
                client.request(_command('one')),
                throwsA(isA<NestError>()),
              );
              expect(budget.stopped, isTrue);
              await expectLater(
                client.request({'op': 'spec.capabilities'}),
                throwsA(
                  isA<NestError>().having(
                    (e) => e.category,
                    'category',
                    'request_budget',
                  ),
                ),
              );
              expect(dispatches(), 1);
            },
          );
        },
      );
    }
  }
  for (final gateway in [true, false]) {
    for (final status in [402, 429]) {
      for (final rawBody in ['', '{invalid']) {
        for (final mutation in [false, true]) {
          test(
            '${gateway ? 'gateway' : 'function'} $status ${rawBody.isEmpty ? 'empty' : 'malformed'} ${mutation ? 'write' : 'read'} stops the budget',
            () async {
              final budget = RequestBudget();
              await _withFixture(
                status: status,
                gateway: gateway,
                rawBody: rawBody,
                budget: budget,
                verify: (client, dispatches) async {
                  final request = mutation
                      ? _command('one')
                      : <String, dynamic>{'op': 'spec.capabilities'};
                  if (gateway && rawBody.isEmpty) {
                    // The SDK preserves the status for an empty gateway body.
                    await expectLater(
                      client.request(request),
                      throwsA(
                        isA<NestError>().having(
                          (e) => e.status,
                          'status',
                          status,
                        ),
                      ),
                    );
                  } else {
                    // Invalid Function bodies or a lost SDK status cannot
                    // establish whether a submitted mutation committed.
                    await expectLater(
                      client.request(request),
                      throwsA(
                        isA<BackendNetworkException>().having(
                          (e) => e.uncertain,
                          'uncertain',
                          mutation,
                        ),
                      ),
                    );
                  }
                  expect(budget.stopped, isTrue);
                  expect(dispatches(), 1);
                  await expectLater(
                    client.request({'op': 'spec.templates'}),
                    throwsA(
                      isA<NestError>().having(
                        (e) => e.category,
                        'category',
                        'request_budget',
                      ),
                    ),
                  );
                  expect(dispatches(), 1, reason: 'No automatic retry.');
                },
              );
            },
          );
        }
      }
    }
  }
  for (final status in [402, 429]) {
    for (final mutation in [false, true]) {
      test(
        'incomplete function $status ${mutation ? 'write' : 'read'} stops the budget',
        () async {
          final budget = RequestBudget();
          await _withFixture(
            status: status,
            gateway: false,
            executionStatus: 'failed',
            budget: budget,
            verify: (client, dispatches) async {
              final request = mutation
                  ? _command('one')
                  : <String, dynamic>{'op': 'spec.capabilities'};
              await expectLater(
                client.request(request),
                throwsA(
                  isA<BackendNetworkException>().having(
                    (e) => e.uncertain,
                    'uncertain',
                    mutation,
                  ),
                ),
              );
              expect(budget.stopped, isTrue);
              expect(dispatches(), 1);
              await expectLater(
                client.request({'op': 'spec.templates'}),
                throwsA(
                  isA<NestError>().having(
                    (e) => e.category,
                    'category',
                    'request_budget',
                  ),
                ),
              );
              expect(dispatches(), 1, reason: 'No automatic retry.');
            },
          );
        },
      );
    }
  }
}

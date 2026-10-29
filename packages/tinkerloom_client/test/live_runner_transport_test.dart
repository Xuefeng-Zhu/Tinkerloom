import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../live_smoke/real_http.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('explicit live runner HTTP override reaches only the local fixture and restores scope', () async {
    final before = HttpOverrides.current;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final handled = server.first.then((request) async {
      request.response.statusCode = 200;
      request.response.write('local fixture');
      await request.response.close();
    });
    try {
      final result = await withRealHttp(() async {
        final client = HttpClient();
        try {
          final request = await client.getUrl(
            Uri.parse('http://127.0.0.1:${server.port}/fixture'),
          );
          final response = await request.close();
          expect(response.statusCode, 200);
          return await response.transform(utf8.decoder).join();
        } finally {
          client.close(force: true);
        }
      });
      expect(result, 'local fixture');
      await handled;
      expect(identical(HttpOverrides.current, before), true);
    } finally {
      await server.close(force: true);
    }
  });
}

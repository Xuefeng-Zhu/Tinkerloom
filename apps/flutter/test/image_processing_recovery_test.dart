import 'dart:convert';
import 'dart:typed_data';

import 'package:appnest_renderer/appnest_renderer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tinkerloom_client/tinkerloom_client.dart';
import 'package:tinkerloom_flutter/features/media/image_upload.dart';

// Synthetic image bytes, never uploaded to Cloud in these tests.
final png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAABAAAAAICAIAAAB/FOjAAAAAE0lEQVR4nGO4ZGBGEmIY1UALDQDGgZwBzNOGvQAAAABJRU5ErkJggg==',
);

class MediaFixture {
  MediaFixture() {
    auth.setSession({'id': 'synthetic-owner', 'email': 'owner@example.test'});
    client = Client(
      'https://appwrite.invalid/v1',
      auth: auth,
      transport: (input) async {
        operations.add(input['op'] as String);
        switch (input['op']) {
          case 'spec.media.begin':
            return {
              'asset': {
                'assetId': 'synthetic-image',
                'status': 'uploading',
                'uploadedBytes': 0,
              },
              'chunkBytes': 262144,
            };
          case 'spec.media.chunk':
            return {'assetId': 'synthetic-image', 'uploadedBytes': png.length};
          case 'spec.media.complete':
            return {
              'asset': {'assetId': 'synthetic-image', 'status': 'queued'},
            };
          case 'spec.media.status':
            return {
              'asset': {
                'assetId': 'synthetic-image',
                'status': ready ? 'ready' : 'processing',
                if (ready) ...{
                  'contentType': 'image/png',
                  'width': 16,
                  'height': 8,
                  'byteLength': png.length,
                },
              },
            };
          default:
            fail('Unexpected transport operation: ${input['op']}');
        }
      },
    );
  }
  final auth = ClientAuth();
  late final Client client;
  final operations = <String>[];
  bool ready = false;
  Future<PendingImageUpload> upload({
    Future<void> Function()? validateContext,
  }) async {
    try {
      await uploadAppImage(
        client,
        Uint8List.fromList(png),
        appId: 'synthetic-app',
        actionId: 'addRecord',
        fieldId: 'photo',
        expectedDefinitionVersionId: 'version-1',
        validateContext: validateContext,
      );
      fail(
        'Queued completion must remain pending until an explicit status check.',
      );
    } on PendingImageUpload catch (pending) {
      return pending;
    }
  }
}

void main() {
  test(
    'queued upload retains one asset; explicit checks attach only READY',
    () async {
      final fixture = MediaFixture();
      addTearDown(fixture.client.close);
      final pending = await fixture.upload();
      expect(pending.assetId, 'synthetic-image');
      expect(fixture.operations, [
        'spec.media.begin',
        'spec.media.chunk',
        'spec.media.complete',
      ]);
      await expectLater(
        pending.checkReady(),
        throwsA(isA<PendingImageUpload>()),
      );
      fixture.ready = true;
      expect(await pending.checkReady(), 'synthetic-image');
      expect(
        fixture.operations.where((op) => op == 'spec.media.begin'),
        hasLength(1),
      );
      expect(
        fixture.operations.where((op) => op == 'spec.media.status'),
        hasLength(2),
      );
    },
  );

  test(
    'a changed actor cannot dispatch the retained image status check',
    () async {
      final fixture = MediaFixture();
      addTearDown(fixture.client.close);
      final pending = await fixture.upload();
      fixture.auth.setSession({
        'id': 'another-owner',
        'email': 'another@example.test',
      });
      await expectLater(
        pending.checkReady(),
        throwsA(isA<BackendUnauthorized>()),
      );
      expect(
        fixture.operations.where((op) => op == 'spec.media.status'),
        isEmpty,
      );
    },
  );

  test(
    'a rejected form definition stops status IO and preserves pending identity',
    () async {
      final fixture = MediaFixture();
      addTearDown(fixture.client.close);
      var validations = 0;
      final pending = await fixture.upload(
        validateContext: () async {
          validations++;
          throw NestError(
            category: 'staleDefinition',
            message: 'Reopen the form.',
          );
        },
      );
      await expectLater(pending.checkReady(), throwsA(isA<NestError>()));
      expect(validations, 1);
      expect(pending.assetId, 'synthetic-image');
      expect(
        fixture.operations.where((op) => op == 'spec.media.status'),
        isEmpty,
      );
    },
  );
}

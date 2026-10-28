import 'dart:convert';
import 'dart:typed_data';

import 'package:appnest_server/src/generated/protocol.dart';
import 'package:appnest_server/src/modules/builder/builder.dart';
import 'package:appnest_server/src/modules/definitions/apps.dart';
import 'package:appnest_server/src/modules/media/media.dart';
import 'package:appnest_server/src/modules/runtime/access.dart';
import 'package:appnest_server/src/modules/runtime/aggregates.dart';
import 'package:appnest_server/src/modules/runtime/commands.dart';
import 'package:appnest_server/src/modules/runtime/integrity.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:image/image.dart' as image;
import 'package:http/http.dart' as http;
import 'package:serverpod/serverpod.dart';
import 'package:test/test.dart';

import 'test_tools/serverpod_test_tools.dart';

void main() {
  withServerpod('Rich component data and private media', (sessions, endpoints) {
    late Session owner, stranger;
    late int workspace, appId, version;
    var sequence = 0;
    Session user(String id) => sessions
        .copyWith(
          authentication: AuthenticationOverride.authenticationInfo(id, {}),
        )
        .build();

    setUpAll(() async => Integrity.ensure(sessions.build()));
    setUp(() async {
      owner = user('rich-owner-${randomToken()}');
      stranger = user('rich-other-${randomToken()}');
      workspace = await Apps.createWorkspace(owner, 'Rich components');
      final json = jsonDecode(starterTemplates()['reading']!.canonical);
      (json['collections'][0]['fields'] as List).addAll([
        {'id': 'photo', 'label': 'Photo', 'type': 'image', 'required': false},
        {'id': 'when', 'label': 'When', 'type': 'timestamp', 'required': false},
      ]);
      (json['requires'] as List).add('fields.image.v1');
      appId = await Apps.create(
        owner,
        workspace,
        AppSpec.parse(jsonEncode(json)),
      );
      version = (await Apps.manifest(owner, appId)).versionId!;
    });

    Future<int> create(Map<String, dynamic> data) async =>
        (await Commands.execute(
          owner,
          ActionRequest(
            appId: appId,
            actionId: 'addBook',
            expectedDefinitionVersionId: version,
            input: {
              'data': {'title': 'Book', 'status': 'Reading', ...data},
            },
            idempotencyKey: 'create-${sequence++}',
          ),
        )).recordId;

    Future<MediaUploadTicket> begin({int? draftId}) => Media.beginUpload(
      owner,
      MediaUploadRequest(
        appId: appId,
        draftId: draftId,
        actionId: draftId == null ? 'addBook' : null,
        fieldId: draftId == null ? 'photo' : null,
        expectedDefinitionVersionId: draftId == null ? version : null,
        byteLength: picture.length,
        contentType: 'image/png',
        idempotencyKey: 'image-${sequence++}',
      ),
    );

    Future<MediaInfo> finish(MediaUploadTicket ticket) async {
      final row = await MediaAsset.db.findFirstRow(
        owner,
        where: (t) => t.assetId.equals(ticket.assetId),
      );
      // Service integration test: store the uploaded original through Serverpod's
      // private storage. HTTP upload transport is a separate browser acceptance check.
      await owner.storage.storeFile(
        storageId: 'private',
        path: Media.path(row!, 'original'),
        byteData: ByteData.sublistView(picture),
      );
      return Media.completeUpload(owner, appId, ticket.assetId);
    }

    test(
      'aggregates cover every page and typed metrics ignore missing values',
      () async {
        for (var i = 0; i < 105; i++) {
          await create({'rating': i.isEven ? 2 : -1});
        }
        await create({});
        Future<Map<String, dynamic>> metric(String op) async => jsonDecode(
          await Aggregates.aggregate(
            owner,
            appId,
            'books',
            '{"limit":1}',
            jsonEncode({
              'metric': op,
              if (op != 'count') 'fieldId': 'rating',
              'groupFieldId': 'status',
            }),
          ),
        ) as Map<String, dynamic>;
        final count = await metric('count');
        expect(count['total'], 106);
        expect(count['value'], 106);
        expect((await metric('sum'))['value'], 54);
        expect((await metric('average'))['value'], closeTo(54 / 105, .00001));
        final empty = jsonDecode(
          await Aggregates.aggregate(
            owner,
            appId,
            'books',
            '{"filters":[{"fieldId":"status","operator":"eq","value":"Finished"}]}',
            '{"metric":"average","fieldId":"rating"}',
          ),
        );
        expect(empty['value'], isNull);
        expect(empty['total'], 0);
        await expectLater(
          Aggregates.aggregate(
            stranger,
            appId,
            'books',
            '{}',
            '{"metric":"count"}',
          ),
          throwsA(isA<NestError>()),
        );
      },
    );

    test('time series use explicit exclusive UTC buckets including a DST-length day', () async {
      await create({'rating': 2, 'when': '2030-03-10T08:00:00Z'});
      await create({'rating': 5, 'when': '2030-03-11T06:59:59Z'});
      await create({'rating': 7, 'when': '2030-03-11T07:00:00Z'});
      await create({'rating': 100});
      final result = jsonDecode(
        await Aggregates.aggregate(
          owner,
          appId,
          'books',
          '{}',
          jsonEncode({
            'metric': 'sum',
            'fieldId': 'rating',
            'dateFieldId': 'when',
            'buckets': [
              {
                'key': 'short day',
                'start': '2030-03-10T08:00:00Z',
                'end': '2030-03-11T07:00:00Z',
              },
              {
                'key': 'next day',
                'start': '2030-03-11T07:00:00Z',
                'end': '2030-03-12T07:00:00Z',
              },
              {
                'key': 'empty',
                'start': '2030-03-12T07:00:00Z',
                'end': '2030-03-13T07:00:00Z',
              },
            ],
          }),
        ),
      );
      expect(result['groups'], [
        {'key': 'short day', 'count': 2, 'value': 7},
        {'key': 'next day', 'count': 1, 'value': 7},
        {'key': 'empty', 'count': 0, 'value': 0},
      ]);
    });

    test(
      'private images require access, ready state and same-app references',
      () async {
        final ticket = await begin();
        await expectLater(
          Media.readImage(owner, appId, ticket.assetId, 'display'),
          throwsA(isA<NestError>()),
        );
        await expectLater(
          create({'photo': ticket.assetId}),
          throwsA(isA<NestError>()),
        );
        final ready = await finish(ticket);
        expect(ready.width, 2);
        expect(
          (await Media.completeUpload(owner, appId, ticket.assetId)).assetId,
          ticket.assetId,
        );
        expect(
          (await Media.readImage(
            owner,
            appId,
            ticket.assetId,
            'display',
          )).lengthInBytes,
          greaterThan(0),
        );
        await expectLater(
          Media.readImage(stranger, appId, ticket.assetId, 'display'),
          throwsA(isA<NestError>()),
        );
        await expectLater(
          Media.readImage(owner, appId, ticket.assetId, 'original'),
          throwsA(isA<NestError>()),
        );
        final recordId = await create({'photo': ticket.assetId});
        expect(
          await MediaReference.db.count(
            owner,
            where: (t) => t.recordId.equals(recordId),
          ),
          1,
        );
        final other = await Apps.instantiate(owner, workspace, 'reading');
        await expectLater(
          Media.readImage(owner, other, ticket.assetId, 'display'),
          throwsA(isA<NestError>()),
        );
        await Apps.archive(owner, appId);
        expect(
          (await Media.readImage(
            owner,
            appId,
            ticket.assetId,
            'thumbnail',
          )).lengthInBytes,
          greaterThan(0),
        );
        await expectLater(begin(), throwsA(isA<NestError>()));
      },
    );

    test('draft and retained version references survive cleanup; remix clears assets', () async {
      var draft = await Builder.begin(owner, workspace, 'reading', appId);
      final ticket = await begin(draftId: draft.draftId);
      await finish(ticket);
      draft = await Builder.patch(
        owner,
        draft.draftId,
        draft.mutation,
        jsonEncode({
          'type': 'AddPage',
          'page': {'title': 'Welcome'},
          'tab': {'label': 'Welcome', 'icon': 'spark'},
          'newViews': [
            {
              'type': 'banner',
              'label': 'Welcome',
              'actionIds': [],
              'options': {
                'imageAssetId': ticket.assetId,
                'imageAlt': 'Library image',
                'title': 'Our library',
              },
            },
          ],
        }),
      );
      final spec = AppSpec.parse(draft.candidateJson);
      final sourceHash = spec.hash;
      expect(Media.definitionAssets(Media.withoutAssets(spec)), isEmpty);
      expect(spec.hash, sourceHash);
      expect(Media.definitionAssets(spec), {ticket.assetId});
      final published = await Builder.publish(
        owner,
        PublishRequest(
          draftId: draft.draftId,
          candidateHash: draft.candidateHash,
          expectedCurrentVersionId: version,
          enabledRuleIds: [],
          activateExistingRecordIds: [],
          reviewHash: hashJson({
            'candidateHash': draft.candidateHash,
            'enabledRuleIds': [],
            'activateExistingRecordIds': [],
          }),
          idempotencyKey: 'publish-image',
        ),
      );
      expect(
        await MediaReference.db.count(
          owner,
          where: (t) => t.versionId.equals(published),
        ),
        1,
      );
      final remix = await Apps.remix(owner, appId, workspace);
      expect(
        Media.definitionAssets(
          AppSpec.parse((await Apps.manifest(owner, remix)).specJson!),
        ),
        isEmpty,
      );
      await owner.db.unsafeExecute(
        'UPDATE nest_media_asset SET "updatedAt"=@old WHERE "assetId"=@asset',
        parameters: QueryParameters.named({
          'old': clock().subtract(const Duration(days: 2)),
          'asset': ticket.assetId,
        }),
      );
      await Media.cleanup(owner);
      expect(
        (await Media.readImage(
          owner,
          appId,
          ticket.assetId,
          'display',
        )).lengthInBytes,
        greaterThan(0),
      );
    });

    test(
      'unreferenced images expire and revoked grants lose image reads',
      () async {
        final ticket = await begin();
        await finish(ticket);
        await create({'photo': ticket.assetId});
        final guest = user('media-guest-${randomToken()}');
        await WorkspaceMember.db.insertRow(
          owner,
          WorkspaceMember(
            workspaceId: workspace,
            actorId: actor(guest),
            role: 'member',
          ),
        );
        var grant = await MiniAppGrant.db.insertRow(
          owner,
          MiniAppGrant(
            appId: appId,
            workspaceId: workspace,
            actorId: actor(guest),
            role: 'viewer',
          ),
        );
        expect(
          (await Media.readImage(
            guest,
            appId,
            ticket.assetId,
            'display',
          )).lengthInBytes,
          greaterThan(0),
        );
        grant.revoked = true;
        await MiniAppGrant.db.updateRow(owner, grant);
        await expectLater(
          Media.readImage(guest, appId, ticket.assetId, 'display'),
          throwsA(isA<NestError>()),
        );
        final orphan = await begin();
        await finish(orphan);
        await owner.db.unsafeExecute(
          'UPDATE nest_media_asset SET "updatedAt"=@old WHERE "assetId"=@asset',
          parameters: QueryParameters.named({
            'old': clock().subtract(const Duration(days: 2)),
            'asset': orphan.assetId,
          }),
        );
        await Media.cleanup(owner);
        expect(
          await MediaAsset.db.count(
            owner,
            where: (t) => t.assetId.equals(orphan.assetId),
          ),
          0,
        );
      },
    );

    test('original cleanup recovers after ready commit and preserves quota accounting', () async {
      final ticket = await begin();
      await finish(ticket);
      var row = (await MediaAsset.db.findFirstRow(
        owner,
        where: (t) => t.assetId.equals(ticket.assetId),
      ))!;
      final readyBytes = row.storedBytes;
      expect(row.originalRemoved, isTrue);
      // Simulate interruption between ready publication and original deletion.
      await owner.storage.storeFile(
        storageId: 'private',
        path: Media.path(row, 'original'),
        byteData: ByteData.sublistView(picture),
      );
      row.originalRemoved = false;
      row.storedBytes += picture.length;
      await MediaAsset.db.updateRow(owner, row);
      await create({'photo': ticket.assetId});
      await Media.cleanup(owner);
      row = (await MediaAsset.db.findById(owner, row.id!))!;
      expect(row.originalRemoved, isTrue);
      expect(row.storedBytes, readyBytes);
      expect(
        await owner.storage.fileExists(
          storageId: 'private',
          path: Media.path(row, 'original'),
        ),
        isFalse,
      );
      await Media.cleanup(owner);
      expect(
        (await MediaAsset.db.findById(owner, row.id!))!.storedBytes,
        readyBytes,
      );
    });

    test(
      'last-reference removal starts a fresh cleanup grace period',
      () async {
        final ticket = await begin();
        await finish(ticket);
        final recordId = await create({'photo': ticket.assetId});
        await owner.db.unsafeExecute(
          'UPDATE nest_media_asset SET "updatedAt"=@old WHERE "assetId"=@asset',
          parameters: QueryParameters.named({
            'old': clock().subtract(const Duration(days: 3)),
            'asset': ticket.assetId,
          }),
        );
        await Commands.execute(
          owner,
          ActionRequest(
            appId: appId,
            actionId: 'editBook',
            targetRecordId: recordId,
            expectedDefinitionVersionId: version,
            expectedRecordRevision: 1,
            input: {
              'data': {'photo': null},
            },
            idempotencyKey: 'remove-photo',
          ),
        );
        await Media.cleanup(owner);
        expect(
          await MediaAsset.db.count(
            owner,
            where: (t) => t.assetId.equals(ticket.assetId),
          ),
          1,
        );
        expect(
          await MediaReference.db.count(
            owner,
            where: (t) => t.recordId.equals(recordId),
          ),
          0,
        );
      },
    );

    test(
      'upload bounds, quota reservations and expired cleanup are enforced',
      () async {
        await expectLater(
          Media.beginUpload(
            owner,
            MediaUploadRequest(
              appId: appId,
              actionId: 'addBook',
              fieldId: 'photo',
              expectedDefinitionVersionId: version,
              byteLength: Media.maxOriginalBytes + 1,
              contentType: 'image/png',
              idempotencyKey: 'oversized',
            ),
          ),
          throwsA(isA<NestError>()),
        );
        final ticket = await begin();
        var row = (await MediaAsset.db.findFirstRow(
          owner,
          where: (t) => t.assetId.equals(ticket.assetId),
        ))!;
        row.storedBytes = Media.maxAppBytes;
        await MediaAsset.db.updateRow(owner, row);
        await expectLater(begin(), throwsA(isA<NestError>()));
        row.expiresAt = clock().subtract(const Duration(minutes: 1));
        await MediaAsset.db.updateRow(owner, row);
        await expectLater(
          Media.completeUpload(owner, appId, ticket.assetId),
          throwsA(isA<NestError>()),
        );
        await Media.cleanup(owner);
        expect(
          await MediaAsset.db.count(
            owner,
            where: (t) => t.assetId.equals(ticket.assetId),
          ),
          0,
        );
      },
    );
    test('real binary HTTP upload accepts more than 512 KiB and completion stays authorized', () async {
      final bytes = image.encodePng(
        image.Image(width: 600, height: 400, numChannels: 3),
        level: 0,
      );
      expect(bytes.length, greaterThan(512 * 1024));
      final ticket = await Media.beginUpload(
        owner,
        MediaUploadRequest(
          appId: appId,
          actionId: 'addBook',
          fieldId: 'photo',
          expectedDefinitionVersionId: version,
          byteLength: bytes.length,
          contentType: 'image/png',
          idempotencyKey: 'http-upload',
        ),
      );
      final description =
          jsonDecode(ticket.uploadDescription) as Map<String, dynamic>;
      expect(description['type'], 'binary');
      // test.yaml binds port 0; use that test server's actual assigned API port.
      // This never starts or contacts the user's development server.
      final url = Uri.parse(description['url'] as String)
          .replace(port: owner.server.port);
      final invalidUrl = url.replace(
        queryParameters: {...url.queryParameters, 'key': 'invalid'},
      );
      await http.post(
        invalidUrl,
        headers: {'Content-Type': 'application/octet-stream'},
        body: bytes,
      );
      await expectLater(
        Media.completeUpload(owner, appId, ticket.assetId),
        throwsA(anything),
      );
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/octet-stream'},
        body: bytes,
      );
      expect(response.statusCode, 200);
      await expectLater(
        Media.completeUpload(stranger, appId, ticket.assetId),
        throwsA(isA<NestError>()),
      );
      final result = await Media.completeUpload(owner, appId, ticket.assetId);
      expect(result.width, 600);
      expect(result.height, 400);
      expect(
        (await Media.readImage(
          owner,
          appId,
          ticket.assetId,
          'thumbnail',
        )).lengthInBytes,
        greaterThan(0),
      );
    });
    test('concurrent image calls do not hold the entire pool while awaiting storage', () async {
      final tickets = await Future.wait(
        List.generate(
          20,
          (i) => Media.beginUpload(
            user(actor(owner)),
            MediaUploadRequest(
              appId: appId,
              actionId: 'addBook',
              fieldId: 'photo',
              expectedDefinitionVersionId: version,
              byteLength: picture.length,
              contentType: 'image/png',
              idempotencyKey: 'parallel-$i',
            ),
          ),
        ),
      ).timeout(const Duration(seconds: 20));
      expect(tickets.map((t) => t.assetId).toSet(), hasLength(20));
      await finish(tickets.first);
      final images = await Future.wait(
        List.generate(
          20,
          (_) => Media.readImage(
            user(actor(owner)),
            appId,
            tickets.first.assetId,
            'thumbnail',
          ),
        ),
      ).timeout(const Duration(seconds: 20));
      expect(images.every((bytes) => bytes.lengthInBytes > 0), isTrue);
    });
  }, rollbackDatabase: RollbackDatabase.disabled);
}

final picture = image.encodePng(
  image.Image(width: 2, height: 2, numChannels: 4),
);

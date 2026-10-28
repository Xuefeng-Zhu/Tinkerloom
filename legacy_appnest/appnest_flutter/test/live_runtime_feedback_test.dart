import 'package:appnest_client/appnest_client.dart';
import 'package:appnest_flutter/features/mini_app/live_adapter.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  LiveRuntimeAdapter runtime({bool archived = false, String role = 'member'}) {
    final client = Client('http://localhost:1/');
    addTearDown(client.close);
    final spec = starterTemplates()['reading']!;
    return LiveRuntimeAdapter(
      client,
      AppManifest(
        appId: 1,
        workspaceId: 1,
        name: spec.name,
        versionId: 1,
        specJson: spec.canonical,
        role: role,
        archived: archived,
        pinned: false,
        recordCount: 0,
        availablePlaces: 0,
      ),
    );
  }

  test(
    'active personal-app members see a permission message, not Archived',
    () {
      final adapter = runtime();
      expect(adapter.readOnly, isTrue);
      expect(adapter.archived, isFalse);
      expect(adapter.readOnlyMessage, isNot(contains('Archived')));
      expect(adapter.permits(adapter.spec.actions.first), isFalse);
      expect(runtime(archived: true).readOnlyMessage, contains('Archived'));
    },
  );

  test(
    'server business failures display their message without raw diagnostics',
    () {
      final adapter = runtime(role: 'owner');
      final error = NestError(
        category: 'exhaustedCapacity',
        message: 'All places are allocated.',
      );
      expect(adapter.errorMessage(error), 'All places are allocated.');
      expect(adapter.commandMayHaveSucceeded(error), isFalse);
      expect(
        adapter.commandMayHaveSucceeded(const SpecException('Invalid value')),
        isFalse,
      );
      expect(
        adapter.commandMayHaveSucceeded(StateError('Response lost')),
        isTrue,
      );
      expect(
        adapter.errorMessage(StateError('private transport diagnostic')),
        'Could not complete the request. Try again.',
      );
    },
  );
}

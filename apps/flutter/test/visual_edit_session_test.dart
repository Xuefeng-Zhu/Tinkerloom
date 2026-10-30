import 'dart:async';
import 'dart:convert';

import 'package:tinkerloom_client/tinkerloom_client.dart';
import 'package:tinkerloom_flutter/features/builder/visual_edit_session.dart';
import 'package:tinkerloom_flutter/features/builder/visual_inspector.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:flutter_test/flutter_test.dart';

BuilderSnapshot snapshot(AppSpec spec, int revision) => BuilderSnapshot(
  candidateReady: true,
  appId: '1',
  draftId: '2',
  mutation: revision,
  stage: 'preview ready',
  candidateJson: spec.canonical,
  candidateHash: spec.hash,
  diagnostics: [],
  changes: [],
  enabledRuleIds: [],
);
VisualPatch rename(String name) =>
    (_) => {'type': 'RenameLabel', 'targetId': 'app', 'label': name};

void main() {
  late BuilderSnapshot server;
  late VisualEditSession session;
  final calls = <int>[];
  Completer<void>? pause;
  Completer<BuilderSnapshot>? pauseRecovery;
  bool failWrite = false, failRead = false, commitBeforeFailure = false;
  bool failConfirmation = false;
  int recoveryReads = 0;
  int confirmationChecks = 0;
  int sessionEpoch = 0;
  setUp(() {
    server = snapshot(starterTemplates()['planner']!, 0);
    calls.clear();
    pause = null;
    pauseRecovery = null;
    failWrite = failRead = commitBeforeFailure = false;
    failConfirmation = false;
    recoveryReads = 0;
    confirmationChecks = 0;
    sessionEpoch = 0;
    session = VisualEditSession(
      snapshot: server,
      sessionEpoch: () => sessionEpoch,
      read: () async {
        if (failRead) throw StateError('offline');
        return server;
      },
      readForRecovery: () async {
        recoveryReads++;
        if (pauseRecovery != null) return await pauseRecovery!.future;
        if (failRead) throw StateError('offline');
        return server;
      },
      write: (revision, json) async {
        calls.add(revision);
        if (pause != null) await pause!.future;
        if (revision != server.mutation) {
          throw NestError(category: 'revision_conflict', message: 'conflict');
        }
        if (!failWrite || commitBeforeFailure) {
          server = snapshot(
            AppSpec.parse(server.candidateJson)
                .patch(jsonDecode(json), () => 'unused'),
            revision + 1,
          );
        }
        if (failWrite) {
          throw BackendNetworkException('offline', uncertain: true);
        }
        return server;
      },
      confirmSave: (_, _) async {
        confirmationChecks++;
        if (failConfirmation) throw StateError('offline');
        return commitBeforeFailure
            ? RetainedCommandStatus.confirmed
            : RetainedCommandStatus.pending;
      },
      onSaved: (_, _) {},
    );
  });
  tearDown(() => session.dispose());

  test(
    'serializes and coalesces newer text without losing another control',
    () async {
      pause = Completer();
      session.enqueue('name', rename('First'));
      final saving = session.flush();
      session.enqueue('name', rename('Second'));
      session.enqueue('name', rename('Newest'));
      session.enqueue(
        'date',
        (spec) => editPage(spec, spec.navigation!.pages.first.id, {
          'showDate': false,
        }),
      );
      pause!.complete();
      expect(await saving, true);
      expect(calls, [0, 1, 2]);
      expect(session.spec.name, 'Newest');
      expect(session.spec.navigation!.pages.first.showDate, false);
      expect(session.pending, false);
    },
  );
  test('invalid text never writes and can be corrected', () async {
    session.enqueue('name', rename(' '));
    expect(await session.flush(), false);
    expect(calls, isEmpty);
    session.enqueue('name', rename('Valid'));
    expect(await session.flush(), true);
    expect(session.spec.name, 'Valid');
  });
  test(
    'lost write response is reconciled without duplicate mutation',
    () async {
      failWrite = commitBeforeFailure = true;
      session.enqueue('name', rename('Saved remotely'));
      expect(await session.flush(), false);
      expect(await session.flush(retry: true), true);
      expect(calls, [0]);
      expect(session.spec.name, 'Saved remotely');
    },
  );
  test('lost response and failed read are reconciled on retry', () async {
    failWrite = commitBeforeFailure = failRead = true;
    session.enqueue('name', rename('Saved remotely'));
    expect(await session.flush(), false);
    expect(session.pending, true);
    failRead = false;
    expect(await session.flush(retry: true), true);
    expect(calls, [0]);
  });
  test(
    'a confirmed receipt is retained across a failed current-draft read',
    () async {
      failWrite = commitBeforeFailure = failRead = true;
      session.enqueue('name', rename('Saved remotely'));
      expect(await session.flush(), false);
      expect(await session.flush(retry: true), false);
      expect(session.uncertain, true);
      await expectLater(session.reload(), throwsStateError);
      failRead = false;
      expect(await session.flush(retry: true), true);
      expect(session.uncertain, false);
      expect(recoveryReads, 2);
      expect(calls, [0]);
    },
  );
  test(
    'an uncertain write cannot be confirmed after the session changes',
    () async {
      failWrite = commitBeforeFailure = true;
      session.enqueue('name', rename('Saved remotely'));
      expect(await session.flush(), false);
      sessionEpoch++;
      expect(await session.flush(retry: true), false);
      expect(confirmationChecks, 0);
      expect(recoveryReads, 0);
      expect(session.uncertain, true);
      expect(calls, [0]);
    },
  );

  test('a confirmed receipt is not reused after the session changes', () async {
    failWrite = commitBeforeFailure = failRead = true;
    session.enqueue('name', rename('Saved remotely'));
    expect(await session.flush(), false);
    expect(await session.flush(retry: true), false);
    expect(recoveryReads, 1);
    sessionEpoch++;
    failRead = false;
    expect(await session.flush(retry: true), false);
    expect(recoveryReads, 1);
    expect(session.uncertain, true);
    expect(session.pending, true);
    expect(calls, [0]);
    await expectLater(session.reload(), throwsStateError);
  });
  test('a late recovery read does not acknowledge a changed session', () async {
    failWrite = commitBeforeFailure = true;
    session.enqueue('name', rename('Saved remotely'));
    expect(await session.flush(), false);
    pauseRecovery = Completer<BuilderSnapshot>();
    final checking = session.flush(retry: true);
    await Future<void>.delayed(Duration.zero);
    expect(recoveryReads, 1);
    sessionEpoch++;
    pauseRecovery!.complete(server);
    expect(await checking, false);
    expect(session.uncertain, true);
    expect(session.pending, true);
    expect(session.snapshot.mutation, 0);
    expect(calls, [0]);
  });
  test(
    'an unresolved save cannot resend or discard even when reads succeed',
    () async {
      failWrite = true;
      session.enqueue('name', rename('Pending'));
      expect(await session.flush(), false);
      expect(await session.flush(retry: true), false);
      expect(calls, [0]);
      expect(session.uncertain, true);
      await expectLater(session.reload(), throwsStateError);
      failConfirmation = true;
      expect(await session.flush(retry: true), false);
      expect(calls, [0]);
      expect(session.pending, true);
    },
  );
  test(
    'revision conflict stops instead of overwriting another editor',
    () async {
      server = snapshot(
        session.spec.patch(
          rename('Other editor')(session.spec),
          () => 'unused',
        ),
        1,
      );
      session.enqueue('name', rename('My edit'));
      expect(await session.flush(), false);
      expect(session.conflict, true);
      expect(await session.flush(retry: true), false);
      expect(calls, [0]);
      await session.reload();
      expect(session.spec.name, 'Other editor');
      expect(session.pending, false);
    },
  );
  test('full page and view payloads retain settings and tab labels', () async {
    final page = session.spec.navigation!.pages.first;
    final tabs = session.spec.navigation!.tabs.map((v) => v.toJson()).toList();
    session.enqueue(
      'title',
      (s) => editPage(s, page.id, {'title': 'New heading'}),
    );
    session.enqueue('date', (s) => editPage(s, page.id, {'showDate': false}));
    expect(await session.flush(), true);
    expect(session.spec.page(page.id).title, 'New heading');
    expect(session.spec.page(page.id).viewIds, page.viewIds);
    expect(session.spec.page(page.id).primaryActionId, page.primaryActionId);
    expect(session.spec.navigation!.tabs.map((v) => v.toJson()), tabs);
  });
  testWidgets('text edits wait 600ms and coalesce', (tester) async {
    session.enqueue('name', rename('First'));
    await tester.pump(const Duration(milliseconds: 300));
    session.enqueue('name', rename('Final'));
    await tester.pump(const Duration(milliseconds: 599));
    expect(calls, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(calls, [0]);
    expect(session.spec.name, 'Final');
  });
}

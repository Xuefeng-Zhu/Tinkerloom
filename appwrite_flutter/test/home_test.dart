import 'package:appwrite_flutter/backend.dart';
import 'package:appwrite_flutter/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Backend implements AppBackend {
  String? email = 'person@example.test';
  final attempts = <(String, String)>[];
  bool failFirst = true;
  final workspaces = <Workspace>[];

  @override
  String newId() => 'request-1';
  @override
  Future<String?> currentEmail() async => email;
  @override
  Future<void> signIn(String email, String password) async {
    this.email = email;
  }

  @override
  Future<void> signUp(String email, String password) async {
    this.email = email;
  }

  @override
  Future<void> signOut() async {
    email = null;
  }

  @override
  Future<List<Workspace>> listWorkspaces() async => List.of(workspaces);
  @override
  Future<List<MiniApp>> listApps(String workspaceId) async => [];
  @override
  Future<void> createApp(String id, String workspaceId, String name) async {}
  @override
  Future<void> createWorkspace(String id, String name) async {
    attempts.add((id, name));
    if (failFirst) {
      failFirst = false;
      throw const BackendFailure('response lost');
    }
    workspaces.add(Workspace(id, name));
  }
}

void main() {
  testWidgets('an uncertain create retries with the same ID and name', (
    tester,
  ) async {
    final backend = _Backend();
    await tester.pumpWidget(MaterialApp(home: Home(backend: backend)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('New workspace'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Neighbors');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(find.textContaining('could not be confirmed'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, false);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(backend.attempts, [
      ('request-1', 'Neighbors'),
      ('request-1', 'Neighbors'),
    ]);
    expect(find.text('Neighbors'), findsOneWidget);
  });
}

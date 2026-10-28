import 'dart:convert';

import 'package:appwrite/appwrite.dart';
import 'package:appwrite/enums.dart' as enums;

class Workspace {
  const Workspace(this.id, this.name);
  final String id;
  final String name;

  factory Workspace.fromJson(Map<String, dynamic> json) =>
      Workspace(json['id'] as String, json['name'] as String);
}

class MiniApp {
  const MiniApp(this.id, this.workspaceId, this.name);
  final String id;
  final String workspaceId;
  final String name;

  factory MiniApp.fromJson(Map<String, dynamic> json) => MiniApp(
    json['id'] as String,
    json['workspaceId'] as String,
    json['name'] as String,
  );
}

class BackendFailure implements Exception {
  const BackendFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract interface class AppBackend {
  String newId();
  Future<String?> currentEmail();
  Future<void> signIn(String email, String password);
  Future<void> signUp(String email, String password);
  Future<void> signOut();
  Future<List<Workspace>> listWorkspaces();
  Future<void> createWorkspace(String id, String name);
  Future<List<MiniApp>> listApps(String workspaceId);
  Future<void> createApp(String id, String workspaceId, String name);
}

class AppwriteBackend implements AppBackend {
  AppwriteBackend({
    required String endpoint,
    required String projectId,
    required this.functionId,
  }) : _client = Client().setEndpoint(endpoint).setProject(projectId) {
    _account = Account(_client);
    _functions = Functions(_client);
  }

  final Client _client;
  late final Account _account;
  late final Functions _functions;
  final String functionId;

  @override
  String newId() => ID.unique();

  @override
  Future<String?> currentEmail() async {
    try {
      return (await _account.get()).email;
    } on AppwriteException catch (error) {
      if (error.code == 401) return null;
      rethrow;
    }
  }

  @override
  Future<void> signIn(String email, String password) async {
    await _account.createEmailPasswordSession(email: email, password: password);
  }

  @override
  Future<void> signUp(String email, String password) async {
    await _account.create(
      userId: ID.unique(),
      email: email,
      password: password,
    );
    await signIn(email, password);
  }

  @override
  Future<void> signOut() async {
    await _account.deleteSession(sessionId: 'current');
  }

  Future<Map<String, dynamic>> _request(Map<String, Object> request) async {
    final execution = await _functions.createExecution(
      functionId: functionId,
      body: jsonEncode(request),
      xasync: false,
      headers: {'content-type': 'application/json'},
    );
    if (execution.status != enums.ExecutionStatus.completed) {
      throw const BackendFailure(
        'The server did not complete the request. Please retry.',
      );
    }
    Object? body;
    try {
      body = jsonDecode(execution.responseBody);
    } on FormatException {
      throw const BackendFailure('The server returned an invalid response.');
    }
    if (body is! Map<String, dynamic>) {
      throw const BackendFailure('The server returned an invalid response.');
    }
    if (execution.responseStatusCode < 200 ||
        execution.responseStatusCode >= 300) {
      throw BackendFailure(
        'Request failed (${body['error'] ?? execution.responseStatusCode}).',
      );
    }
    return body;
  }

  @override
  Future<List<Workspace>> listWorkspaces() async {
    final data = await _request({'op': 'listWorkspaces'});
    return (data['workspaces'] as List)
        .map((value) => Workspace.fromJson(value as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> createWorkspace(String id, String name) async {
    await _request({'op': 'createWorkspace', 'id': id, 'name': name});
  }

  @override
  Future<List<MiniApp>> listApps(String workspaceId) async {
    final data = await _request({'op': 'listApps', 'workspaceId': workspaceId});
    return (data['apps'] as List)
        .map((value) => MiniApp.fromJson(value as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> createApp(String id, String workspaceId, String name) async {
    await _request({
      'op': 'createApp',
      'id': id,
      'workspaceId': workspaceId,
      'name': name,
    });
  }
}

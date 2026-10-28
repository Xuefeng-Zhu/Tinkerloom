import 'dart:convert';
import 'dart:math';

import 'package:appnest_spec/appnest_spec.dart';
import 'package:serverpod/serverpod.dart';

import '../../generated/protocol.dart';

Never fail(String category, String message) =>
    throw NestError(category: category, message: message);
String actor(Session s) =>
    s.authenticated?.userIdentifier ??
    fail('forbidden', 'Sign in to continue.');
DateTime Function() clock = () => DateTime.now().toUtc();
Future<void> reserveAppSlot(Session s, int workspaceId, Transaction tx) async {
  await Workspace.db.findFirstRow(
    s,
    where: (t) => t.id.equals(workspaceId),
    transaction: tx,
    lockMode: LockMode.forUpdate,
  );
  if (await MiniApp.db.count(
        s,
        where: (t) => t.workspaceId.equals(workspaceId),
        transaction: tx,
      ) >=
      Limits.appsPerWorkspace) {
    fail(
      'quotaExceeded',
      'Workspace app limit reached, including unpublished drafts.',
    );
  }
}

String randomToken() => base64Url
    .encode(List.generate(32, (_) => Random.secure().nextInt(256)))
    .replaceAll('=', '');
Map<String, dynamic> payload(dynamic value) {
  // ORM unwraps Serverpod's dynamic JSONB envelope; query the typed projection instead.
  if (value is! Map) fail('invalidInput', 'Expected an object.');
  return Map<String, dynamic>.from(value);
}

Future<T> validated<T>(Future<T> Function() body) async {
  try {
    return await body();
  } on SpecException catch (e) {
    fail('invalidInput', e.message);
  } on FormatException {
    fail('invalidInput', 'Invalid JSON or value format.');
  }
}

class Access {
  final MiniApp app;
  final String role;
  Access(this.app, this.role);
  bool get builder => role == 'owner' || role == 'builder';
  void requireBuilder() {
    if (!builder) fail('forbidden', 'Only builders can do that.');
  }

  void writable() {
    if (app.archived) fail('forbidden', 'This app is archived and read-only.');
  }

  Future<AppSpec> spec(Session s, {Transaction? tx}) async {
    final v = app.activeVersionId == null
        ? null
        : await AppVersion.db.findById(
            s,
            app.activeVersionId!,
            transaction: tx,
          );
    if (v == null || v.appId != app.id) {
      fail('staleDefinition', 'Publish a definition first.');
    }
    return AppSpec.parse(v.specJson);
  }
}

Future<Access> access(
  Session s,
  int appId, {
  Transaction? tx,
  bool lock = false,
}) async {
  final app = await MiniApp.db.findFirstRow(
    s,
    where: (t) => t.id.equals(appId),
    transaction: tx,
    lockMode: lock ? LockMode.forUpdate : null,
  );
  if (app == null) fail('notFound', 'App unavailable.');
  final id = actor(s);
  if (await WorkspaceMember.db.findFirstRow(
        s,
        where: (t) =>
            t.workspaceId.equals(app.workspaceId) & t.actorId.equals(id),
        transaction: tx,
      ) ==
      null) {
    fail('notFound', 'App unavailable.');
  }
  if (app.ownerId == id) return Access(app, 'owner');
  final grant = await MiniAppGrant.db.findFirstRow(
    s,
    where: (t) =>
        t.appId.equals(appId) & t.actorId.equals(id) & t.revoked.equals(false),
    transaction: tx,
  );
  if (grant == null || grant.workspaceId != app.workspaceId) {
    fail('notFound', 'App unavailable.');
  }
  return Access(app, grant.role);
}

Future<void> workspaceAccess(Session s, int id, {Transaction? tx}) async {
  if (await WorkspaceMember.db.findFirstRow(
        s,
        where: (t) => t.workspaceId.equals(id) & t.actorId.equals(actor(s)),
        transaction: tx,
      ) ==
      null) {
    fail('notFound', 'Workspace unavailable.');
  }
}

Future<EntityRecord> record(
  Session s,
  Access a,
  int id, {
  Transaction? tx,
}) async {
  final row = await EntityRecord.db.findFirstRow(
    s,
    where: (t) =>
        t.id.equals(id) & t.appId.equals(a.app.id!) & t.deleted.equals(false),
    transaction: tx,
  );
  if (row == null || row.workspaceId != a.app.workspaceId) {
    fail('notFound', 'Record unavailable.');
  }
  return row;
}

Future<void> changed(
  Session s,
  Access a,
  String kind,
  Transaction tx, {
  int? recordId,
  String? requestId,
}) async {
  a.app.controlRevision++;
  await MiniApp.db.updateRow(s, a.app, transaction: tx);
  await AuditEntry.db.insertRow(
    s,
    AuditEntry(
      appId: a.app.id!,
      actorId: actor(s),
      action: kind,
      targetRecordId: recordId,
      requestId: requestId ?? randomToken(),
      createdAt: clock(),
    ),
    transaction: tx,
  );
  await OutboxEvent.db.insertRow(
    s,
    OutboxEvent(
      appId: a.app.id!,
      recordId: recordId,
      kind: kind,
      nextAttemptAt: clock(),
      createdAt: clock(),
    ),
    transaction: tx,
  );
}

bool allowed(Access a, AppSpec spec, ActionSpec action) {
  if (a.app.archived || a.role == 'viewer') return false;
  if (a.builder) return true;
  if (action.capability == 'records.create.v1' &&
      spec
          .collection(action.collectionId)
          .behaviors
          .any((b) => b.type == 'capacity.v1')) {
    return false;
  }
  return switch (spec.policyPresetRequest) {
    'groupCapacitySignup.v1' => {
      'capacity.claim.v1',
      'capacity.release.v1',
    }.contains(action.capability),
    'groupWorkflow.v1' => {
      'records.create.v1',
      'records.patch.v1',
      'assignment.assign.v1',
      'workflow.transition.v1',
    }.contains(action.capability),
    _ => false,
  };
}

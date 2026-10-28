import 'package:serverpod/serverpod.dart';

import '../generated/protocol.dart';
import '../modules/definitions/apps.dart';
import '../modules/collaboration/sharing.dart';
import '../modules/runtime/access.dart';

class AppsEndpoint extends Endpoint {
  @override
  bool get requireLogin => true;
  Future<List<WorkspaceInfo>> workspaces(Session session) =>
      Apps.workspaces(session);
  Future<int> createWorkspace(Session session, String name) =>
      Apps.createWorkspace(session, name);
  Future<List<AppManifest>> list(Session session, int workspaceId) =>
      Apps.list(session, workspaceId);
  Future<AppManifest> manifest(Session session, int appId) =>
      Apps.manifest(session, appId);
  Future<List<TemplateInfo>> templates(Session session) async =>
      Apps.templates();
  Future<int> instantiate(
    Session session,
    int workspaceId,
    String templateKey,
  ) => validated(() => Apps.instantiate(session, workspaceId, templateKey));
  Future<int> remix(Session session, int appId, int workspaceId) =>
      Apps.remix(session, appId, workspaceId);
  Future<void> pin(Session session, int appId, bool pinned) =>
      Apps.pin(session, appId, pinned);
  Future<void> archive(Session session, int appId) =>
      Apps.archive(session, appId);
  Future<String> invite(
    Session session,
    int appId,
    String role,
    String? recipientId,
  ) => Sharing.invite(session, appId, role, recipientId);
  Future<int> acceptInvitation(Session session, String token) =>
      Sharing.accept(session, token);
  Future<void> revokeInvitation(Session session, int appId, String token) =>
      Sharing.revokeInvite(session, appId, token);
  Future<List<MemberInfo>> members(Session session, int appId) =>
      Sharing.members(session, appId);
  Future<void> setGrant(
    Session session,
    int appId,
    String target,
    String? role,
  ) => Sharing.setGrant(session, appId, target, role);
  Future<List<ActivityItem>> activity(Session session, int appId) =>
      Sharing.activity(session, appId);
}

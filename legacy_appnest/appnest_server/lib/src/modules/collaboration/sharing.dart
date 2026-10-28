import 'package:appnest_spec/appnest_spec.dart';
import 'package:serverpod/serverpod.dart';

import '../../generated/protocol.dart';
import '../runtime/access.dart';

class Sharing {
  static Future<String> invite(
    Session s,
    int appId,
    String role,
    String? recipientId,
  ) => s.db.transaction((tx) async {
    final a = await access(s, appId, tx: tx, lock: true);
    a.requireBuilder();
    a.writable();
    if (!{'builder', 'member', 'viewer'}.contains(role)) {
      fail('invalidInput', 'Choose builder, member, or viewer.');
    }
    if (recipientId != null &&
        (recipientId.isEmpty || recipientId.length > 100)) {
      fail('invalidInput', 'Invalid recipient.');
    }
    await s.db.unsafeQuery(
      'SELECT pg_advisory_xact_lock(hashtextextended(@actor,2))',
      parameters: QueryParameters.named({'actor': actor(s)}),
      transaction: tx,
    );
    if (await Invitation.db.count(
          s,
          where: (t) =>
              t.issuerId.equals(actor(s)) &
              (t.createdAt > clock().subtract(const Duration(days: 1))),
          transaction: tx,
        ) >=
        Limits.invitationsPerDay) {
      fail('quotaExceeded', 'Daily invitation limit reached.');
    }
    final token = randomToken();
    await Invitation.db.insertRow(
      s,
      Invitation(
        appId: appId,
        workspaceId: a.app.workspaceId,
        issuerId: actor(s),
        tokenHash: hashJson(token),
        role: role,
        recipientId: recipientId,
        expiresAt: clock().add(const Duration(days: 7)),
        createdAt: clock(),
      ),
      transaction: tx,
    );
    await changed(s, a, 'invite', tx);
    return token;
  });
  static Future<int> accept(Session s, String token) => s.db.transaction((
    tx,
  ) async {
    if (token.length > 100) fail('notFound', 'Invitation unavailable.');
    var invite = await Invitation.db.findFirstRow(
      s,
      where: (t) => t.tokenHash.equals(hashJson(token)),
      transaction: tx,
    );
    if (invite == null) fail('notFound', 'Invitation unavailable.');
    final app = await MiniApp.db.findFirstRow(
      s,
      where: (t) => t.id.equals(invite!.appId),
      lockMode: LockMode.forUpdate,
      transaction: tx,
    );
    invite = await Invitation.db.findById(s, invite.id!, transaction: tx);
    final id = actor(s);
    if (app == null ||
        app.archived ||
        invite == null ||
        invite.revoked ||
        !invite.expiresAt.isAfter(clock()) ||
        (invite.acceptedBy != null && invite.acceptedBy != id) ||
        (invite.recipientId != null && invite.recipientId != id)) {
      fail('notFound', 'Invitation unavailable.');
    }
    if (invite.acceptedBy == id) return app.id!;
    // Issuer must still have sharing rights. A stale invitation cannot restore revoked authority.
    if (invite.issuerId != app.ownerId) {
      final grant = await MiniAppGrant.db.findFirstRow(
        s,
        where: (t) =>
            t.appId.equals(app.id!) &
            t.actorId.equals(invite!.issuerId) &
            t.revoked.equals(false),
        transaction: tx,
      );
      if (grant?.role != 'builder') fail('notFound', 'Invitation unavailable.');
    }
    if (await WorkspaceMember.db.findFirstRow(
          s,
          where: (t) =>
              t.workspaceId.equals(app.workspaceId) & t.actorId.equals(id),
          transaction: tx,
        ) ==
        null) {
      await WorkspaceMember.db.insertRow(
        s,
        WorkspaceMember(
          workspaceId: app.workspaceId,
          actorId: id,
          role: 'member',
        ),
        transaction: tx,
      );
    }
    final grant = await MiniAppGrant.db.findFirstRow(
      s,
      where: (t) => t.appId.equals(app.id!) & t.actorId.equals(id),
      transaction: tx,
    );
    if (grant == null) {
      await MiniAppGrant.db.insertRow(
        s,
        MiniAppGrant(
          appId: app.id!,
          workspaceId: app.workspaceId,
          actorId: id,
          role: invite.role,
        ),
        transaction: tx,
      );
    } else {
      grant.role = invite.role;
      grant.revoked = false;
      await MiniAppGrant.db.updateRow(s, grant, transaction: tx);
    }
    invite.acceptedBy = id;
    await Invitation.db.updateRow(s, invite, transaction: tx);
    if (await AppShortcut.db.findFirstRow(
          s,
          where: (t) => t.appId.equals(app.id!) & t.actorId.equals(id),
          transaction: tx,
        ) ==
        null) {
      await AppShortcut.db.insertRow(
        s,
        AppShortcut(appId: app.id!, actorId: id),
        transaction: tx,
      );
    }
    await changed(s, Access(app, invite.role), 'join', tx);
    return app.id!;
  });
  static Future<void> revokeInvite(Session s, int appId, String token) =>
      s.db.transaction((tx) async {
        final a = await access(s, appId, tx: tx, lock: true);
        a.requireBuilder();
        final invite = await Invitation.db.findFirstRow(
          s,
          where: (t) =>
              t.appId.equals(appId) & t.tokenHash.equals(hashJson(token)),
          transaction: tx,
        );
        if (invite == null) fail('notFound', 'Invitation unavailable.');
        invite.revoked = true;
        await Invitation.db.updateRow(s, invite, transaction: tx);
        await changed(s, a, 'revokeInvitation', tx);
      });
  static Future<List<MemberInfo>> members(Session s, int appId) async {
    final a = await access(s, appId);
    final grants = await MiniAppGrant.db.find(
      s,
      where: (t) => t.appId.equals(appId) & t.revoked.equals(false),
      limit: 100,
    );
    return [
      MemberInfo(actorId: a.app.ownerId, role: 'owner'),
      ...grants
          .where((g) => g.actorId != a.app.ownerId)
          .map((g) => MemberInfo(actorId: g.actorId, role: g.role)),
    ];
  }

  static Future<void> setGrant(
    Session s,
    int appId,
    String target,
    String? role,
  ) => s.db.transaction((tx) async {
    final a = await access(s, appId, tx: tx, lock: true);
    a.requireBuilder();
    a.writable();
    if (target == a.app.ownerId) {
      fail('forbidden', 'The owner grant cannot be changed.');
    }
    if (role != null && !{'builder', 'member', 'viewer'}.contains(role)) {
      fail('invalidInput', 'Invalid role.');
    }
    final grant = await MiniAppGrant.db.findFirstRow(
      s,
      where: (t) => t.appId.equals(appId) & t.actorId.equals(target),
      transaction: tx,
    );
    if (grant == null) {
      fail(
        'notFound',
        'Member unavailable. Use an invitation to add a member.',
      );
    }
    grant.revoked = role == null;
    if (role != null) grant.role = role;
    await MiniAppGrant.db.updateRow(s, grant, transaction: tx);
    await changed(s, a, 'grantChanged', tx);
  });
  static Future<List<InboxItem>> inbox(Session s) async {
    final rows = await s.db.unsafeQuery(
      '''SELECT n.id,n."appId",n.title,n.body,n."createdAt",n."readAt",r.id,r."collectionId" FROM nest_notification n
      JOIN nest_app a ON a.id=n."appId" JOIN nest_workspace_member m ON m."workspaceId"=a."workspaceId" AND m."actorId"=@actor
      LEFT JOIN nest_grant g ON g."appId"=a.id AND g."actorId"=@actor AND NOT g.revoked
      LEFT JOIN nest_run u ON u.id=n."runId" AND u."appId"=a.id
      LEFT JOIN nest_record r ON r.id=u."recordId" AND r."appId"=a.id AND NOT r.deleted
      WHERE n."actorId"=@actor AND (a."ownerId"=@actor OR g.id IS NOT NULL) ORDER BY n.id DESC LIMIT 100''',
      parameters: QueryParameters.named({'actor': actor(s)}),
    );
    return rows
        .map(
          (r) => InboxItem(
            id: r[0] as int,
            appId: r[1] as int,
            title: r[2] as String,
            body: r[3] as String,
            createdAt: r[4] as DateTime,
            isRead: r[5] != null,
            recordId: r[6] as int?,
            collectionId: r[7] as String?,
          ),
        )
        .toList();
  }

  static Future<void> read(Session s, int id) => s.db.transaction((tx) async {
    final n = await Notification.db.findFirstRow(
      s,
      where: (t) => t.id.equals(id) & t.actorId.equals(actor(s)),
      transaction: tx,
    );
    if (n == null) fail('notFound', 'Notification unavailable.');
    await access(s, n.appId, tx: tx, lock: true);
    n.readAt = clock();
    await Notification.db.updateRow(s, n, transaction: tx);
  });
  static Future<List<ActivityItem>> activity(Session s, int appId) async {
    await access(s, appId);
    final rows = await AuditEntry.db.find(
      s,
      where: (t) => t.appId.equals(appId),
      orderBy: (t) => t.id,
      limit: 100,
    );
    return rows
        .map(
          (r) => ActivityItem(
            id: r.id!,
            action: r.action,
            createdAt: r.createdAt,
            status: 'committed',
          ),
        )
        .toList();
  }
}

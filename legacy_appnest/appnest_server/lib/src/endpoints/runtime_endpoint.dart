import 'package:serverpod/serverpod.dart';

import '../generated/protocol.dart';
import '../modules/runtime/access.dart';
import '../modules/runtime/commands.dart';
import '../modules/runtime/queries.dart';
import '../modules/runtime/aggregates.dart';
import '../modules/collaboration/sharing.dart';
import '../modules/runtime/revision_events.dart';

class RuntimeEndpoint extends Endpoint {
  @override
  bool get requireLogin => true;
  Future<RecordPage> query(
    Session session,
    int appId,
    String collectionId,
    String queryJson,
  ) => Queries.query(session, appId, collectionId, queryJson);
  Future<RecordSummary> summary(
    Session session,
    int appId,
    String collectionId,
    String queryJson,
    String groupFieldId,
  ) => Queries.summary(session, appId, collectionId, queryJson, groupFieldId);
  Future<String> aggregate(
    Session session,
    int appId,
    String collectionId,
    String queryJson,
    String aggregateJson,
  ) => Aggregates.aggregate(
    session,
    appId,
    collectionId,
    queryJson,
    aggregateJson,
  );
  Future<List<ReminderState>> reminderState(
    Session session,
    int appId,
    int recordId,
  ) => Queries.reminderState(session, appId, recordId);
  Future<RuntimeRecord> get(Session session, int appId, int recordId) =>
      Queries.get(session, appId, recordId);
  Future<ActionOutcome> execute(Session session, ActionRequest request) =>
      Commands.execute(session, request);
  Future<List<InboxItem>> inbox(Session session) => Sharing.inbox(session);
  Future<void> readNotification(Session session, int id) =>
      Sharing.read(session, id);
  Stream<AppEvent> events(Session session, int appId) {
    late final RevisionEvents events;
    void closing(Session _) => events.stop();
    events = RevisionEvents(
      () async => (await access(session, appId)).app.controlRevision,
      onStop: () => session.removeWillCloseListener(closing),
    );
    session.addWillCloseListener(closing);
    return events.stream.map(
      (revision) => AppEvent(appId: appId, revision: revision, kind: 'refresh'),
    );
  }
}

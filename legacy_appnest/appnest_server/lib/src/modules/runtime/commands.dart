import 'dart:convert';

import 'package:appnest_spec/appnest_spec.dart';
import 'package:serverpod/serverpod.dart';

import '../../generated/protocol.dart';
import 'access.dart';
import '../media/media.dart';

class Commands {
  static Future<ActionOutcome> execute(
    Session s,
    ActionRequest request,
  ) => validated(
    () => s.db.transaction((tx) async {
      final a = await access(s, request.appId, tx: tx, lock: true);
      final key = str(request.idempotencyKey, 'command key', max: 128);
      final requestHash = hashJson(request.toJson()..remove('idempotencyKey'));
      final previous = await ActionReceipt.db.findFirstRow(
        s,
        where: (t) =>
            t.appId.equals(request.appId) &
            t.actorId.equals(actor(s)) &
            t.idempotencyKey.equals(key),
        transaction: tx,
      );
      if (previous != null) {
        if (previous.requestHash != requestHash) {
          fail(
            'invalidInput',
            'This command key was already used for different input.',
          );
        }
        return ActionOutcome.fromJson(jsonDecode(previous.outcomeJson));
      }
      a.writable();
      if (a.app.activeVersionId != request.expectedDefinitionVersionId) {
        fail(
          'staleDefinition',
          'The app changed. Refresh before trying again.',
        );
      }
      final spec = await a.spec(s, tx: tx),
          action = spec.action(request.actionId),
          input = payload(request.input);
      if (!allowed(a, spec, action)) {
        fail('forbidden', 'Your role cannot perform this action.');
      }
      final col = spec.collection(action.collectionId);
      EntityRecord row;
      if (action.capability == 'records.create.v1') {
        keys(input, {'data', 'capacity'}, 'create input');
        final data = col.normalizeRecord(payload(input['data']));
        await _members(s, a, col, data, tx);
        for (final b in col.behaviors.where((b) => b.type == 'workflow.v1')) {
          if (data[b.fieldId] != col.field(b.fieldId!).choices.first) {
            fail(
              'invalidInput',
              'New records must start in ${col.field(b.fieldId!).choices.first}.',
            );
          }
        }
        row = await EntityRecord.db.insertRow(
          s,
          EntityRecord(
            appId: a.app.id!,
            workspaceId: a.app.workspaceId,
            collectionId: col.id,
            data: data,
            creatorId: actor(s),
            revision: 1,
            writtenUnderVersionId: a.app.activeVersionId!,
            createdAt: clock(),
            updatedAt: clock(),
          ),
          transaction: tx,
        );
        final behaviors = col.behaviors.where((b) => b.type == 'capacity.v1');
        if (behaviors.isNotEmpty) {
          a.requireBuilder();
          final capacity = _capacity(input['capacity']);
          for (final b in behaviors) {
            await ResourcePool.db.insertRow(
              s,
              ResourcePool(
                appId: a.app.id!,
                workspaceId: a.app.workspaceId,
                recordId: row.id!,
                behaviorId: b.id,
                capacity: capacity,
              ),
              transaction: tx,
            );
          }
        } else if (input.containsKey('capacity')) {
          fail('invalidInput', 'This collection does not support capacity.');
        }
        await project(s, row, col, tx);
        await Media.syncRecord(s, a, row, col, tx);
      } else {
        if (request.targetRecordId == null) {
          fail('invalidInput', 'Choose a record.');
        }
        row = await record(s, a, request.targetRecordId!, tx: tx);
        if (row.collectionId != col.id) fail('notFound', 'Record unavailable.');
        if (action.capability.startsWith('capacity.')) {
          await _capacityCommand(s, a, row, action, input, tx);
        } else {
          if (request.expectedRecordRevision != row.revision) {
            fail(
              'recordConflict',
              'Someone changed this record. Refresh to review their changes.',
            );
          }
          final previousData = payload(row.data);
          final data = {...previousData};
          String? assignedField;
          if (action.capability == 'records.patch.v1') {
            keys(input, {'data'}, 'patch input');
            final patch = payload(input['data']);
            final protected = col.behaviors
                .where(
                  (b) => b.type == 'workflow.v1' || b.type == 'assignment.v1',
                )
                .map((b) => b.fieldId)
                .toSet();
            if (patch.keys.any(protected.contains)) {
              fail(
                'forbidden',
                'Use the approved status or assignment action.',
              );
            }
            data.addAll(patch);
          } else {
            keys(input, {'value'}, 'action input');
            final behavior = col.behavior(action.behaviorId!);
            if (action.capability == 'assignment.assign.v1') {
              assignedField = behavior.fieldId;
            }
            if (action.capability == 'workflow.transition.v1' &&
                !(behavior.transitions[data[behavior.fieldId]] ?? []).contains(
                  input['value'],
                )) {
              fail('invalidInput', 'That status transition is not allowed.');
            }
            data[behavior.fieldId!] = input['value'];
          }
          row.data = col.normalizeRecord(data);
          await _members(
            s,
            a,
            col,
            payload(row.data),
            tx,
            previousData: previousData,
            assignedField: assignedField,
          );
          row.revision++;
          row.updatedAt = clock();
          row.writtenUnderVersionId = a.app.activeVersionId!;
          await EntityRecord.db.updateRow(s, row, transaction: tx);
          await project(s, row, col, tx);
          await Media.syncRecord(s, a, row, col, tx);
        }
      }
      final result = ActionOutcome(
        recordId: row.id!,
        revision: row.revision,
        message: 'Saved',
      );
      await changed(
        s,
        a,
        action.capability,
        tx,
        recordId: row.id,
        requestId: key,
      );
      await ActionReceipt.db.insertRow(
        s,
        ActionReceipt(
          appId: a.app.id!,
          actorId: actor(s),
          idempotencyKey: key,
          requestHash: requestHash,
          outcomeJson: jsonEncode(result.toJson()),
          createdAt: clock(),
        ),
        transaction: tx,
      );
      return result;
    }),
  );
  static int _capacity(dynamic value) {
    if (value is! int || value < 0 || value > 10000) {
      fail('invalidInput', 'Capacity must be between 0 and 10,000.');
    }
    return value;
  }

  static Future<void> _capacityCommand(
    Session s,
    Access a,
    EntityRecord row,
    ActionSpec action,
    Map<String, dynamic> input,
    Transaction tx,
  ) async {
    final pool = await ResourcePool.db.findFirstRow(
      s,
      where: (t) =>
          t.appId.equals(a.app.id!) &
          t.recordId.equals(row.id!) &
          t.behaviorId.equals(action.behaviorId!),
      transaction: tx,
      lockMode: LockMode.forUpdate,
    );
    if (pool == null) {
      fail('invalidInput', 'The owner must configure capacity first.');
    }
    if (action.capability == 'capacity.configure.v1') {
      a.requireBuilder();
      keys(input, {'capacity'}, 'capacity input');
      final capacity = _capacity(input['capacity']);
      if (capacity < pool.allocated) {
        fail('invalidInput', 'Capacity cannot be less than current sign-ups.');
      }
      pool.capacity = capacity;
    } else {
      keys(input, {}, 'claim input');
      var claim = await Claim.db.findFirstRow(
        s,
        where: (t) => t.poolId.equals(pool.id!) & t.actorId.equals(actor(s)),
        transaction: tx,
      );
      if (action.capability == 'capacity.claim.v1') {
        if (claim?.active == true) return;
        if (pool.allocated >= pool.capacity) {
          fail(
            'exhaustedCapacity',
            'This shift is full. No place was reserved.',
          );
        }
        if (claim == null) {
          await Claim.db.insertRow(
            s,
            Claim(
              appId: a.app.id!,
              workspaceId: a.app.workspaceId,
              poolId: pool.id!,
              actorId: actor(s),
              active: true,
              createdAt: clock(),
              updatedAt: clock(),
            ),
            transaction: tx,
          );
        } else {
          claim.active = true;
          claim.updatedAt = clock();
          await Claim.db.updateRow(s, claim, transaction: tx);
        }
        pool.allocated++;
      } else {
        if (claim?.active != true) return;
        claim!.active = false;
        claim.updatedAt = clock();
        await Claim.db.updateRow(s, claim, transaction: tx);
        pool.allocated--;
      }
    }
    await ResourcePool.db.updateRow(s, pool, transaction: tx);
  }

  static Future<void> _members(
    Session s,
    Access a,
    CollectionSpec col,
    Map<String, dynamic> data,
    Transaction tx, {
    Map<String, dynamic>? previousData,
    String? assignedField,
  }) async {
    for (final field in col.fields.where(
      (f) => f.type == FieldType.member && data[f.id] != null,
    )) {
      final id = data[field.id] as String;
      // Existing references are historical data, not authority. Preserve them
      // on unrelated edits after revocation, but require current membership
      // for creates, changed references, and explicit assignment actions.
      if (field.id != assignedField && previousData?[field.id] == id) continue;
      if (id == a.app.ownerId) continue;
      final grant = await MiniAppGrant.db.findFirstRow(
        s,
        where: (t) =>
            t.appId.equals(a.app.id!) &
            t.actorId.equals(id) &
            t.revoked.equals(false),
        transaction: tx,
      );
      final member = await WorkspaceMember.db.findFirstRow(
        s,
        where: (t) =>
            t.workspaceId.equals(a.app.workspaceId) & t.actorId.equals(id),
        transaction: tx,
      );
      if (grant == null || member == null) {
        fail('invalidInput', 'Choose a member of this app.');
      }
    }
  }

  static Future<void> project(
    Session s,
    EntityRecord row,
    CollectionSpec col,
    Transaction tx,
  ) async {
    await FieldValue.db.deleteWhere(
      s,
      where: (t) => t.recordId.equals(row.id!),
      transaction: tx,
    );
    final data = payload(row.data);
    for (final f in col.fields) {
      final value = data[f.id];
      if (value == null) continue;
      await FieldValue.db.insertRow(
        s,
        FieldValue(
          recordId: row.id!,
          appId: row.appId,
          collectionId: row.collectionId,
          fieldId: f.id,
          textValue:
              {
                FieldType.text,
                FieldType.choice,
                FieldType.member,
                FieldType.image,
              }.contains(f.type)
              ? value as String
              : null,
          numberValue: value is num ? value.toDouble() : null,
          boolValue: value is bool ? value : null,
          timestampValue: f.type == FieldType.timestamp
              ? DateTime.parse(value as String)
              : null,
        ),
        transaction: tx,
      );
    }
  }
}

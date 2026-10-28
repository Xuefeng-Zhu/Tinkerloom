import 'package:serverpod/serverpod.dart';

/// Companion migration: tenant consistency triggers + capacity CHECKs.
/// Single-column foreign keys remain generated from .spy.yaml.
class Integrity {
  static Future<void> ensure(Session s) => s.db.transaction((tx) async {
    await s.db.unsafeQuery(
      'SELECT pg_advisory_xact_lock(712349821)',
      transaction: tx,
    );
    final tables = <String, (List<String>, List<String>)>{
      'nest_app': (
        ['workspaceId', 'ownerId'],
        [
          'NEW."activeVersionId" IS NULL OR EXISTS (SELECT 1 FROM nest_version v WHERE v.id=NEW."activeVersionId" AND v."appId"=NEW.id AND v."workspaceId"=NEW."workspaceId")',
        ],
      ),
      for (final table in [
        'nest_grant',
        'nest_invitation',
        'nest_draft',
        'nest_version',
        'nest_record',
        'nest_pool',
        'nest_claim',
        'nest_automation',
        'nest_notification',
        'nest_media_asset',
      ])
        table: (
          ['appId', 'workspaceId'],
          [
            'EXISTS (SELECT 1 FROM nest_app a WHERE a.id=NEW."appId" AND a."workspaceId"=NEW."workspaceId")',
            if (table == 'nest_record') 'EXISTS (SELECT 1 FROM nest_version v WHERE v.id=NEW."writtenUnderVersionId" AND v."appId"=NEW."appId")',
            if (table == 'nest_pool') 'EXISTS (SELECT 1 FROM nest_record r WHERE r.id=NEW."recordId" AND r."appId"=NEW."appId")',
            if (table == 'nest_claim') 'EXISTS (SELECT 1 FROM nest_pool p WHERE p.id=NEW."poolId" AND p."appId"=NEW."appId")',
            if (table == 'nest_notification') 'EXISTS (SELECT 1 FROM nest_run r WHERE r.id=NEW."runId" AND r."appId"=NEW."appId")',
            if (table == 'nest_draft') 'NEW."baseVersionId" IS NULL OR EXISTS (SELECT 1 FROM nest_version v WHERE v.id=NEW."baseVersionId" AND v."appId"=NEW."appId")',
            if (table == 'nest_draft') 'NEW."publishedVersionId" IS NULL OR EXISTS (SELECT 1 FROM nest_version v WHERE v.id=NEW."publishedVersionId" AND v."appId"=NEW."appId")',
          ],
        ),
      'nest_generation': (
        ['appId', 'draftId'],
        [
          'EXISTS (SELECT 1 FROM nest_draft d WHERE d.id=NEW."draftId" AND d."appId"=NEW."appId")',
        ],
      ),
      'nest_media_reference': (
        ['appId', 'assetRowId'],
        [
          'EXISTS (SELECT 1 FROM nest_media_asset a WHERE a.id=NEW."assetRowId" AND a."appId"=NEW."appId")',
          'num_nonnulls(NEW."draftId",NEW."versionId",NEW."recordId")=1',
          'NEW."draftId" IS NULL OR EXISTS (SELECT 1 FROM nest_draft d WHERE d.id=NEW."draftId" AND d."appId"=NEW."appId")',
          'NEW."versionId" IS NULL OR EXISTS (SELECT 1 FROM nest_version v WHERE v.id=NEW."versionId" AND v."appId"=NEW."appId")',
          'NEW."recordId" IS NULL OR EXISTS (SELECT 1 FROM nest_record r WHERE r.id=NEW."recordId" AND r."appId"=NEW."appId")',
        ],
      ),
      'nest_field_value': (
        ['appId', 'recordId', 'collectionId'],
        [
          'EXISTS (SELECT 1 FROM nest_record r WHERE r.id=NEW."recordId" AND r."appId"=NEW."appId" AND r."collectionId"=NEW."collectionId")',
        ],
      ),
      'nest_run': (
        ['appId', 'recordId', 'automationId'],
        [
          'EXISTS (SELECT 1 FROM nest_record r WHERE r.id=NEW."recordId" AND r."appId"=NEW."appId")',
          'EXISTS (SELECT 1 FROM nest_automation a WHERE a.id=NEW."automationId" AND a."appId"=NEW."appId")',
        ],
      ),
      'nest_outbox': (
        ['appId'],
        [
          'NEW."recordId" IS NULL OR EXISTS (SELECT 1 FROM nest_record r WHERE r.id=NEW."recordId" AND r."appId"=NEW."appId")',
        ],
      ),
      'nest_audit': (
        ['appId'],
        [
          'NEW."targetRecordId" IS NULL OR EXISTS (SELECT 1 FROM nest_record r WHERE r.id=NEW."targetRecordId" AND r."appId"=NEW."appId")',
        ],
      ),
    };
    for (final e in tables.entries) {
      final fixed = e.value.$1
          .map((f) => 'NEW."$f" IS DISTINCT FROM OLD."$f"')
          .join(' OR ');
      final valid = e.value.$2.map((c) => '($c)').join(' AND ');
      await s.db.unsafeExecute('''
        CREATE OR REPLACE FUNCTION ${e.key}_tenant_guard() RETURNS trigger LANGUAGE plpgsql AS \$\$
        BEGIN
          IF TG_OP='UPDATE' AND ($fixed) THEN RAISE EXCEPTION 'Immutable scope' USING ERRCODE='23514'; END IF;
          IF NOT ($valid) THEN RAISE EXCEPTION 'Invalid tenant relationship' USING ERRCODE='23514'; END IF;
          RETURN NEW;
        END; \$\$
      ''', transaction: tx);
      await s.db.unsafeExecute(
        'CREATE OR REPLACE TRIGGER ${e.key}_tenant_guard BEFORE INSERT OR UPDATE ON ${e.key} FOR EACH ROW EXECUTE FUNCTION ${e.key}_tenant_guard()',
        transaction: tx,
      );
    }
    for (final c in {
      'nest_capacity_bounds': (
        'nest_pool',
        'capacity >= 0 AND capacity <= 10000 AND allocated >= 0 AND allocated <= capacity',
      ),
      'nest_record_revision': ('nest_record', 'revision >= 1'),
    }.entries) {
      final exists = await s.db.unsafeQuery(
        'SELECT 1 FROM pg_constraint WHERE conname=@name',
        parameters: QueryParameters.named({'name': c.key}),
        transaction: tx,
      );
      if (exists.isEmpty) {
        await s.db.unsafeExecute(
          'ALTER TABLE ${c.value.$1} ADD CONSTRAINT ${c.key} CHECK (${c.value.$2})',
          transaction: tx,
        );
      }
    }
  });
}

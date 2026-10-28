BEGIN;
-- Replace pre-release custom FKs with generated foreign keys below; preserves all rows.
ALTER TABLE "nest_app" DROP CONSTRAINT IF EXISTS "nest_app_workspace_fk";
ALTER TABLE "nest_workspace_member" DROP CONSTRAINT IF EXISTS "nest_member_workspace_fk";
ALTER TABLE "nest_version" DROP CONSTRAINT IF EXISTS "nest_version_app_fk";
ALTER TABLE "nest_record" DROP CONSTRAINT IF EXISTS "nest_record_app_fk";
ALTER TABLE "nest_record" DROP CONSTRAINT IF EXISTS "nest_record_version_fk";
ALTER TABLE "nest_pool" DROP CONSTRAINT IF EXISTS "nest_pool_record_fk";
ALTER TABLE "nest_claim" DROP CONSTRAINT IF EXISTS "nest_claim_pool_fk";
ALTER TABLE "nest_run" DROP CONSTRAINT IF EXISTS "nest_run_rule_fk";
ALTER TABLE "nest_notification" DROP CONSTRAINT IF EXISTS "nest_notification_run_fk";
ALTER TABLE "nest_grant" DROP CONSTRAINT IF EXISTS "nest_grant_scope_fk";
ALTER TABLE "nest_invitation" DROP CONSTRAINT IF EXISTS "nest_invitation_scope_fk";
ALTER TABLE "nest_draft" DROP CONSTRAINT IF EXISTS "nest_draft_scope_fk";
ALTER TABLE "nest_automation" DROP CONSTRAINT IF EXISTS "nest_automation_scope_fk";
ALTER TABLE "nest_notification" DROP CONSTRAINT IF EXISTS "nest_notification_scope_fk";
ALTER TABLE "nest_receipt" DROP CONSTRAINT IF EXISTS "nest_receipt_app_fk";
ALTER TABLE "nest_outbox" DROP CONSTRAINT IF EXISTS "nest_outbox_app_fk";
ALTER TABLE "nest_audit" DROP CONSTRAINT IF EXISTS "nest_audit_app_fk";
ALTER TABLE "nest_shortcut" DROP CONSTRAINT IF EXISTS "nest_shortcut_app_fk";
ALTER TABLE "nest_generation" DROP CONSTRAINT IF EXISTS "nest_generation_app_fk";
DROP INDEX IF EXISTS "nest_app_scope";
DROP INDEX IF EXISTS "nest_version_scope";
DROP INDEX IF EXISTS "nest_record_scope";
DROP INDEX IF EXISTS "nest_pool_scope";
DROP INDEX IF EXISTS "nest_rule_scope";
DROP INDEX IF EXISTS "nest_run_scope";

--
-- ACTION ALTER TABLE
--
--
-- ACTION ALTER TABLE
--
--
-- ACTION ALTER TABLE
--
--
-- ACTION ALTER TABLE
--
--
-- ACTION ALTER TABLE
--
--
-- ACTION ALTER TABLE
--
--
-- ACTION ALTER TABLE
--
--
-- ACTION ALTER TABLE
--
--
-- ACTION ALTER TABLE
--
--
-- ACTION ALTER TABLE
--
--
-- ACTION ALTER TABLE
--
--
-- ACTION ALTER TABLE
--
--
-- ACTION ALTER TABLE
--
--
-- ACTION ALTER TABLE
--
--
-- ACTION ALTER TABLE
--
--
-- ACTION ALTER TABLE
--
--
-- ACTION ALTER TABLE
--
--
-- ACTION ALTER TABLE
--
--
-- ACTION CREATE FOREIGN KEY
--
ALTER TABLE ONLY "nest_app"
    ADD CONSTRAINT "nest_app_fk_0"
    FOREIGN KEY("workspaceId")
    REFERENCES "nest_workspace"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;
ALTER TABLE ONLY "nest_app"
    ADD CONSTRAINT "nest_app_fk_1"
    FOREIGN KEY("activeVersionId")
    REFERENCES "nest_version"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;
--
-- ACTION CREATE FOREIGN KEY
--
ALTER TABLE ONLY "nest_audit"
    ADD CONSTRAINT "nest_audit_fk_0"
    FOREIGN KEY("appId")
    REFERENCES "nest_app"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;
ALTER TABLE ONLY "nest_audit"
    ADD CONSTRAINT "nest_audit_fk_1"
    FOREIGN KEY("targetRecordId")
    REFERENCES "nest_record"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;
--
-- ACTION CREATE FOREIGN KEY
--
ALTER TABLE ONLY "nest_automation"
    ADD CONSTRAINT "nest_automation_fk_0"
    FOREIGN KEY("appId")
    REFERENCES "nest_app"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;
ALTER TABLE ONLY "nest_automation"
    ADD CONSTRAINT "nest_automation_fk_1"
    FOREIGN KEY("workspaceId")
    REFERENCES "nest_workspace"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;
--
-- ACTION CREATE FOREIGN KEY
--
ALTER TABLE ONLY "nest_claim"
    ADD CONSTRAINT "nest_claim_fk_0"
    FOREIGN KEY("appId")
    REFERENCES "nest_app"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;
ALTER TABLE ONLY "nest_claim"
    ADD CONSTRAINT "nest_claim_fk_1"
    FOREIGN KEY("workspaceId")
    REFERENCES "nest_workspace"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;
ALTER TABLE ONLY "nest_claim"
    ADD CONSTRAINT "nest_claim_fk_2"
    FOREIGN KEY("poolId")
    REFERENCES "nest_pool"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;
--
-- ACTION CREATE FOREIGN KEY
--
ALTER TABLE ONLY "nest_draft"
    ADD CONSTRAINT "nest_draft_fk_0"
    FOREIGN KEY("appId")
    REFERENCES "nest_app"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;
ALTER TABLE ONLY "nest_draft"
    ADD CONSTRAINT "nest_draft_fk_1"
    FOREIGN KEY("workspaceId")
    REFERENCES "nest_workspace"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;
ALTER TABLE ONLY "nest_draft"
    ADD CONSTRAINT "nest_draft_fk_2"
    FOREIGN KEY("baseVersionId")
    REFERENCES "nest_version"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;
ALTER TABLE ONLY "nest_draft"
    ADD CONSTRAINT "nest_draft_fk_3"
    FOREIGN KEY("activeJobId")
    REFERENCES "nest_generation"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;
ALTER TABLE ONLY "nest_draft"
    ADD CONSTRAINT "nest_draft_fk_4"
    FOREIGN KEY("publishedVersionId")
    REFERENCES "nest_version"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;
--
-- ACTION CREATE FOREIGN KEY
--
ALTER TABLE ONLY "nest_field_value"
    ADD CONSTRAINT "nest_field_value_fk_0"
    FOREIGN KEY("recordId")
    REFERENCES "nest_record"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;
ALTER TABLE ONLY "nest_field_value"
    ADD CONSTRAINT "nest_field_value_fk_1"
    FOREIGN KEY("appId")
    REFERENCES "nest_app"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;
--
-- ACTION CREATE FOREIGN KEY
--
ALTER TABLE ONLY "nest_generation"
    ADD CONSTRAINT "nest_generation_fk_0"
    FOREIGN KEY("appId")
    REFERENCES "nest_app"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;
ALTER TABLE ONLY "nest_generation"
    ADD CONSTRAINT "nest_generation_fk_1"
    FOREIGN KEY("draftId")
    REFERENCES "nest_draft"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;
--
-- ACTION CREATE FOREIGN KEY
--
ALTER TABLE ONLY "nest_grant"
    ADD CONSTRAINT "nest_grant_fk_0"
    FOREIGN KEY("appId")
    REFERENCES "nest_app"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;
ALTER TABLE ONLY "nest_grant"
    ADD CONSTRAINT "nest_grant_fk_1"
    FOREIGN KEY("workspaceId")
    REFERENCES "nest_workspace"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;
--
-- ACTION CREATE FOREIGN KEY
--
ALTER TABLE ONLY "nest_invitation"
    ADD CONSTRAINT "nest_invitation_fk_0"
    FOREIGN KEY("appId")
    REFERENCES "nest_app"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;
ALTER TABLE ONLY "nest_invitation"
    ADD CONSTRAINT "nest_invitation_fk_1"
    FOREIGN KEY("workspaceId")
    REFERENCES "nest_workspace"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;
--
-- ACTION CREATE FOREIGN KEY
--
ALTER TABLE ONLY "nest_notification"
    ADD CONSTRAINT "nest_notification_fk_0"
    FOREIGN KEY("appId")
    REFERENCES "nest_app"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;
ALTER TABLE ONLY "nest_notification"
    ADD CONSTRAINT "nest_notification_fk_1"
    FOREIGN KEY("workspaceId")
    REFERENCES "nest_workspace"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;
ALTER TABLE ONLY "nest_notification"
    ADD CONSTRAINT "nest_notification_fk_2"
    FOREIGN KEY("runId")
    REFERENCES "nest_run"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;
--
-- ACTION CREATE FOREIGN KEY
--
ALTER TABLE ONLY "nest_outbox"
    ADD CONSTRAINT "nest_outbox_fk_0"
    FOREIGN KEY("appId")
    REFERENCES "nest_app"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;
ALTER TABLE ONLY "nest_outbox"
    ADD CONSTRAINT "nest_outbox_fk_1"
    FOREIGN KEY("recordId")
    REFERENCES "nest_record"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;
--
-- ACTION CREATE FOREIGN KEY
--
ALTER TABLE ONLY "nest_pool"
    ADD CONSTRAINT "nest_pool_fk_0"
    FOREIGN KEY("appId")
    REFERENCES "nest_app"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;
ALTER TABLE ONLY "nest_pool"
    ADD CONSTRAINT "nest_pool_fk_1"
    FOREIGN KEY("workspaceId")
    REFERENCES "nest_workspace"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;
ALTER TABLE ONLY "nest_pool"
    ADD CONSTRAINT "nest_pool_fk_2"
    FOREIGN KEY("recordId")
    REFERENCES "nest_record"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;
--
-- ACTION CREATE FOREIGN KEY
--
ALTER TABLE ONLY "nest_receipt"
    ADD CONSTRAINT "nest_receipt_fk_0"
    FOREIGN KEY("appId")
    REFERENCES "nest_app"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;
--
-- ACTION CREATE FOREIGN KEY
--
ALTER TABLE ONLY "nest_record"
    ADD CONSTRAINT "nest_record_fk_0"
    FOREIGN KEY("appId")
    REFERENCES "nest_app"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;
ALTER TABLE ONLY "nest_record"
    ADD CONSTRAINT "nest_record_fk_1"
    FOREIGN KEY("workspaceId")
    REFERENCES "nest_workspace"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;
ALTER TABLE ONLY "nest_record"
    ADD CONSTRAINT "nest_record_fk_2"
    FOREIGN KEY("writtenUnderVersionId")
    REFERENCES "nest_version"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;
--
-- ACTION CREATE FOREIGN KEY
--
ALTER TABLE ONLY "nest_run"
    ADD CONSTRAINT "nest_run_fk_0"
    FOREIGN KEY("appId")
    REFERENCES "nest_app"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;
ALTER TABLE ONLY "nest_run"
    ADD CONSTRAINT "nest_run_fk_1"
    FOREIGN KEY("automationId")
    REFERENCES "nest_automation"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;
ALTER TABLE ONLY "nest_run"
    ADD CONSTRAINT "nest_run_fk_2"
    FOREIGN KEY("recordId")
    REFERENCES "nest_record"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;
--
-- ACTION CREATE FOREIGN KEY
--
ALTER TABLE ONLY "nest_shortcut"
    ADD CONSTRAINT "nest_shortcut_fk_0"
    FOREIGN KEY("appId")
    REFERENCES "nest_app"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;
--
-- ACTION CREATE FOREIGN KEY
--
ALTER TABLE ONLY "nest_version"
    ADD CONSTRAINT "nest_version_fk_0"
    FOREIGN KEY("appId")
    REFERENCES "nest_app"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;
ALTER TABLE ONLY "nest_version"
    ADD CONSTRAINT "nest_version_fk_1"
    FOREIGN KEY("workspaceId")
    REFERENCES "nest_workspace"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;
--
-- ACTION CREATE FOREIGN KEY
--
ALTER TABLE ONLY "nest_workspace_member"
    ADD CONSTRAINT "nest_workspace_member_fk_0"
    FOREIGN KEY("workspaceId")
    REFERENCES "nest_workspace"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;

--
-- MIGRATION VERSION FOR appnest
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('appnest', '20260921192040469-integrity', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20260921192040469-integrity', "timestamp" = now();

--
-- MIGRATION VERSION FOR serverpod
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('serverpod', '20260824182259319', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20260824182259319', "timestamp" = now();

--
-- MIGRATION VERSION FOR serverpod_auth_idp
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('serverpod_auth_idp', '20260910193913364-string-rate-limit-keys', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20260910193913364-string-rate-limit-keys', "timestamp" = now();

--
-- MIGRATION VERSION FOR serverpod_auth_core
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('serverpod_auth_core', '20260824182354731', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20260824182354731', "timestamp" = now();


COMMIT;

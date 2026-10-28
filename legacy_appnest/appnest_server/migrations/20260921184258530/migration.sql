BEGIN;

--
-- ACTION CREATE TABLE
--
CREATE TABLE "nest_app" (
    "id" bigserial PRIMARY KEY,
    "workspaceId" bigint NOT NULL,
    "ownerId" text NOT NULL,
    "name" text NOT NULL,
    "activeVersionId" bigint,
    "archived" boolean NOT NULL DEFAULT false,
    "controlRevision" bigint NOT NULL DEFAULT 0,
    "createdAt" timestamp without time zone NOT NULL
);

--
-- ACTION CREATE TABLE
--
CREATE TABLE "nest_audit" (
    "id" bigserial PRIMARY KEY,
    "appId" bigint NOT NULL,
    "actorId" text NOT NULL,
    "action" text NOT NULL,
    "targetRecordId" bigint,
    "requestId" text NOT NULL,
    "createdAt" timestamp without time zone NOT NULL
);

--
-- ACTION CREATE TABLE
--
CREATE TABLE "nest_automation" (
    "id" bigserial PRIMARY KEY,
    "appId" bigint NOT NULL,
    "workspaceId" bigint NOT NULL,
    "ruleId" text NOT NULL,
    "ruleVersion" bigint NOT NULL,
    "ruleJson" text NOT NULL,
    "enabled" boolean NOT NULL,
    "executionActorId" text NOT NULL,
    "activateExisting" boolean NOT NULL,
    "activatedAt" timestamp without time zone NOT NULL
);

-- Indexes
CREATE UNIQUE INDEX "rule_unique" ON "nest_automation" USING btree ("appId", "ruleId");

--
-- ACTION CREATE TABLE
--
CREATE TABLE "nest_claim" (
    "id" bigserial PRIMARY KEY,
    "appId" bigint NOT NULL,
    "workspaceId" bigint NOT NULL,
    "poolId" bigint NOT NULL,
    "actorId" text NOT NULL,
    "active" boolean NOT NULL,
    "createdAt" timestamp without time zone NOT NULL,
    "updatedAt" timestamp without time zone NOT NULL
);

-- Indexes
CREATE UNIQUE INDEX "claim_unique" ON "nest_claim" USING btree ("poolId", "actorId");

--
-- ACTION CREATE TABLE
--
CREATE TABLE "nest_draft" (
    "id" bigserial PRIMARY KEY,
    "appId" bigint NOT NULL,
    "workspaceId" bigint NOT NULL,
    "actorId" text NOT NULL,
    "baseVersionId" bigint,
    "candidateJson" text NOT NULL,
    "candidateHash" text NOT NULL,
    "mutation" bigint NOT NULL DEFAULT 0,
    "activeJobId" bigint,
    "publishedVersionId" bigint,
    "updatedAt" timestamp without time zone NOT NULL
);

--
-- ACTION CREATE TABLE
--
CREATE TABLE "nest_field_value" (
    "id" bigserial PRIMARY KEY,
    "recordId" bigint NOT NULL,
    "appId" bigint NOT NULL,
    "collectionId" text NOT NULL,
    "fieldId" text NOT NULL,
    "textValue" text,
    "numberValue" double precision,
    "boolValue" boolean,
    "timestampValue" timestamp without time zone
);

-- Indexes
CREATE UNIQUE INDEX "record_field" ON "nest_field_value" USING btree ("recordId", "fieldId");
CREATE INDEX "query_field" ON "nest_field_value" USING btree ("appId", "collectionId", "fieldId");

--
-- ACTION CREATE TABLE
--
CREATE TABLE "nest_generation" (
    "id" bigserial PRIMARY KEY,
    "appId" bigint NOT NULL,
    "draftId" bigint NOT NULL,
    "actorId" text NOT NULL,
    "mutation" bigint NOT NULL,
    "status" text NOT NULL,
    "requestText" text NOT NULL,
    "mode" text NOT NULL,
    "provider" text,
    "model" text,
    "promptVersion" text NOT NULL,
    "attempts" bigint NOT NULL DEFAULT 0,
    "leaseGeneration" bigint NOT NULL DEFAULT 0,
    "leaseUntil" timestamp without time zone,
    "nextAttemptAt" timestamp without time zone NOT NULL,
    "diagnostics" text NOT NULL,
    "usageJson" text NOT NULL,
    "createdAt" timestamp without time zone NOT NULL,
    "updatedAt" timestamp without time zone NOT NULL
);

--
-- ACTION CREATE TABLE
--
CREATE TABLE "nest_grant" (
    "id" bigserial PRIMARY KEY,
    "appId" bigint NOT NULL,
    "workspaceId" bigint NOT NULL,
    "actorId" text NOT NULL,
    "role" text NOT NULL,
    "revoked" boolean NOT NULL DEFAULT false
);

-- Indexes
CREATE UNIQUE INDEX "grant_unique" ON "nest_grant" USING btree ("appId", "actorId");

--
-- ACTION CREATE TABLE
--
CREATE TABLE "nest_invitation" (
    "id" bigserial PRIMARY KEY,
    "appId" bigint NOT NULL,
    "workspaceId" bigint NOT NULL,
    "issuerId" text NOT NULL,
    "tokenHash" text NOT NULL,
    "role" text NOT NULL,
    "recipientId" text,
    "expiresAt" timestamp without time zone NOT NULL,
    "revoked" boolean NOT NULL DEFAULT false,
    "acceptedBy" text,
    "createdAt" timestamp without time zone NOT NULL
);

-- Indexes
CREATE UNIQUE INDEX "invitation_token" ON "nest_invitation" USING btree ("tokenHash");

--
-- ACTION CREATE TABLE
--
CREATE TABLE "nest_notification" (
    "id" bigserial PRIMARY KEY,
    "appId" bigint NOT NULL,
    "workspaceId" bigint NOT NULL,
    "actorId" text NOT NULL,
    "runId" bigint NOT NULL,
    "deliveryKey" text NOT NULL,
    "title" text NOT NULL,
    "body" text NOT NULL,
    "readAt" timestamp without time zone,
    "createdAt" timestamp without time zone NOT NULL
);

-- Indexes
CREATE UNIQUE INDEX "delivery_unique" ON "nest_notification" USING btree ("deliveryKey");
CREATE INDEX "inbox_actor" ON "nest_notification" USING btree ("actorId", "createdAt");

--
-- ACTION CREATE TABLE
--
CREATE TABLE "nest_outbox" (
    "id" bigserial PRIMARY KEY,
    "appId" bigint NOT NULL,
    "recordId" bigint,
    "kind" text NOT NULL,
    "planned" boolean NOT NULL DEFAULT false,
    "invalidated" boolean NOT NULL DEFAULT false,
    "attempts" bigint NOT NULL DEFAULT 0,
    "nextAttemptAt" timestamp without time zone NOT NULL,
    "createdAt" timestamp without time zone NOT NULL
);

--
-- ACTION CREATE TABLE
--
CREATE TABLE "nest_pool" (
    "id" bigserial PRIMARY KEY,
    "appId" bigint NOT NULL,
    "workspaceId" bigint NOT NULL,
    "recordId" bigint NOT NULL,
    "behaviorId" text NOT NULL,
    "capacity" bigint NOT NULL,
    "allocated" bigint NOT NULL DEFAULT 0
);

-- Indexes
CREATE UNIQUE INDEX "pool_unique" ON "nest_pool" USING btree ("appId", "recordId", "behaviorId");

--
-- ACTION CREATE TABLE
--
CREATE TABLE "nest_receipt" (
    "id" bigserial PRIMARY KEY,
    "appId" bigint NOT NULL,
    "actorId" text NOT NULL,
    "idempotencyKey" text NOT NULL,
    "requestHash" text NOT NULL,
    "outcomeJson" text NOT NULL,
    "createdAt" timestamp without time zone NOT NULL
);

-- Indexes
CREATE UNIQUE INDEX "receipt_unique" ON "nest_receipt" USING btree ("appId", "actorId", "idempotencyKey");

--
-- ACTION CREATE TABLE
--
CREATE TABLE "nest_record" (
    "id" bigserial PRIMARY KEY,
    "appId" bigint NOT NULL,
    "workspaceId" bigint NOT NULL,
    "collectionId" text NOT NULL,
    "data" jsonb NOT NULL,
    "creatorId" text NOT NULL,
    "revision" bigint NOT NULL,
    "writtenUnderVersionId" bigint NOT NULL,
    "createdAt" timestamp without time zone NOT NULL,
    "updatedAt" timestamp without time zone NOT NULL,
    "deleted" boolean NOT NULL DEFAULT false
);

-- Indexes
CREATE INDEX "record_scope_time" ON "nest_record" USING btree ("appId", "collectionId", "createdAt");

--
-- ACTION CREATE TABLE
--
CREATE TABLE "nest_run" (
    "id" bigserial PRIMARY KEY,
    "appId" bigint NOT NULL,
    "automationId" bigint NOT NULL,
    "recordId" bigint NOT NULL,
    "occurrenceKey" text NOT NULL,
    "scheduleSignature" text NOT NULL,
    "dueAt" timestamp without time zone NOT NULL,
    "nextAttemptAt" timestamp without time zone NOT NULL,
    "status" text NOT NULL,
    "attempts" bigint NOT NULL DEFAULT 0,
    "leaseGeneration" bigint NOT NULL DEFAULT 0,
    "leaseUntil" timestamp without time zone,
    "errorCategory" text,
    "createdAt" timestamp without time zone NOT NULL,
    "completedAt" timestamp without time zone
);

-- Indexes
CREATE UNIQUE INDEX "occurrence_unique" ON "nest_run" USING btree ("occurrenceKey");
CREATE INDEX "run_due" ON "nest_run" USING btree ("status", "nextAttemptAt");

--
-- ACTION CREATE TABLE
--
CREATE TABLE "nest_shortcut" (
    "id" bigserial PRIMARY KEY,
    "appId" bigint NOT NULL,
    "actorId" text NOT NULL
);

-- Indexes
CREATE UNIQUE INDEX "shortcut_unique" ON "nest_shortcut" USING btree ("appId", "actorId");

--
-- ACTION CREATE TABLE
--
CREATE TABLE "nest_template" (
    "id" bigserial PRIMARY KEY,
    "key" text NOT NULL,
    "specJson" text NOT NULL,
    "description" text NOT NULL
);

-- Indexes
CREATE UNIQUE INDEX "template_key" ON "nest_template" USING btree ("key");

--
-- ACTION CREATE TABLE
--
CREATE TABLE "nest_version" (
    "id" bigserial PRIMARY KEY,
    "appId" bigint NOT NULL,
    "workspaceId" bigint NOT NULL,
    "number" bigint NOT NULL,
    "specJson" text NOT NULL,
    "candidateHash" text NOT NULL,
    "publisherId" text NOT NULL,
    "createdAt" timestamp without time zone NOT NULL
);

-- Indexes
CREATE UNIQUE INDEX "version_unique" ON "nest_version" USING btree ("appId", "number");

--
-- ACTION CREATE TABLE
--
CREATE TABLE "nest_workspace" (
    "id" bigserial PRIMARY KEY,
    "name" text NOT NULL,
    "ownerId" text NOT NULL,
    "personal" boolean NOT NULL DEFAULT false,
    "createdAt" timestamp without time zone NOT NULL
);

--
-- ACTION CREATE TABLE
--
CREATE TABLE "nest_workspace_member" (
    "id" bigserial PRIMARY KEY,
    "workspaceId" bigint NOT NULL,
    "actorId" text NOT NULL,
    "role" text NOT NULL
);

-- Indexes
CREATE UNIQUE INDEX "membership_unique" ON "nest_workspace_member" USING btree ("workspaceId", "actorId");


--
-- MIGRATION VERSION FOR appnest
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('appnest', '20260921184258530', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20260921184258530', "timestamp" = now();

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

BEGIN;

--
-- Function: gen_random_uuid_v7()
-- Source: https://gist.github.com/kjmph/5bd772b2c2df145aa645b837da7eca74
-- License: MIT (copyright notice included on the generator source code).
--
create or replace function gen_random_uuid_v7()
returns uuid
as $$
begin
  -- use random v4 uuid as starting point (which has the same variant we need)
  -- then overlay timestamp
  -- then set version 7 by flipping the 2 and 1 bit in the version 4 string
  return encode(
    set_bit(
      set_bit(
        overlay(uuid_send(gen_random_uuid())
                placing substring(int8send(floor(extract(epoch from clock_timestamp()) * 1000)::bigint) from 3)
                from 1 for 6
        ),
        52, 1
      ),
      53, 1
    ),
    'hex')::uuid;
end
$$
language plpgsql
volatile;

--
-- Class MiniApp as table nest_app
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
-- Class AuditEntry as table nest_audit
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
-- Class Automation as table nest_automation
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
-- Class Claim as table nest_claim
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
-- Class AppDraft as table nest_draft
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
-- Class FieldValue as table nest_field_value
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
-- Class GenerationJob as table nest_generation
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
-- Class MiniAppGrant as table nest_grant
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
-- Class Invitation as table nest_invitation
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
-- Class Notification as table nest_notification
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
-- Class OutboxEvent as table nest_outbox
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
-- Class ResourcePool as table nest_pool
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
-- Class ActionReceipt as table nest_receipt
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
-- Class EntityRecord as table nest_record
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
-- Class AutomationRun as table nest_run
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
-- Class AppShortcut as table nest_shortcut
--
CREATE TABLE "nest_shortcut" (
    "id" bigserial PRIMARY KEY,
    "appId" bigint NOT NULL,
    "actorId" text NOT NULL
);

-- Indexes
CREATE UNIQUE INDEX "shortcut_unique" ON "nest_shortcut" USING btree ("appId", "actorId");

--
-- Class Template as table nest_template
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
-- Class AppVersion as table nest_version
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
-- Class Workspace as table nest_workspace
--
CREATE TABLE "nest_workspace" (
    "id" bigserial PRIMARY KEY,
    "name" text NOT NULL,
    "ownerId" text NOT NULL,
    "personal" boolean NOT NULL DEFAULT false,
    "createdAt" timestamp without time zone NOT NULL
);

--
-- Class WorkspaceMember as table nest_workspace_member
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
-- Class CloudStorageEntry as table serverpod_cloud_storage
--
CREATE TABLE "serverpod_cloud_storage" (
    "id" bigserial PRIMARY KEY,
    "storageId" text NOT NULL,
    "path" text NOT NULL,
    "addedTime" timestamp without time zone NOT NULL,
    "expiration" timestamp without time zone,
    "byteData" bytea NOT NULL,
    "verified" boolean NOT NULL,
    "contentType" text,
    "cacheControl" text,
    "contentDisposition" text,
    "contentEncoding" text,
    "customMetadata" text
);

-- Indexes
CREATE UNIQUE INDEX "serverpod_cloud_storage_path_idx" ON "serverpod_cloud_storage" USING btree ("storageId", "path");
CREATE INDEX "serverpod_cloud_storage_expiration" ON "serverpod_cloud_storage" USING btree ("expiration");

--
-- Class CloudStorageDirectDownloadEntry as table serverpod_cloud_storage_direct_download
--
CREATE TABLE "serverpod_cloud_storage_direct_download" (
    "id" bigserial PRIMARY KEY,
    "storageId" text NOT NULL,
    "path" text NOT NULL,
    "expiration" timestamp without time zone NOT NULL,
    "authKey" text NOT NULL,
    "downloadFileName" text,
    "contentType" text
);

-- Indexes
CREATE UNIQUE INDEX "serverpod_cloud_storage_direct_download_auth_key" ON "serverpod_cloud_storage_direct_download" USING btree ("authKey");
CREATE INDEX "serverpod_cloud_storage_direct_download_expiration" ON "serverpod_cloud_storage_direct_download" USING btree ("expiration");

--
-- Class CloudStorageDirectUploadEntry as table serverpod_cloud_storage_direct_upload
--
CREATE TABLE "serverpod_cloud_storage_direct_upload" (
    "id" bigserial PRIMARY KEY,
    "storageId" text NOT NULL,
    "path" text NOT NULL,
    "expiration" timestamp without time zone NOT NULL,
    "authKey" text NOT NULL,
    "maxFileSize" bigint NOT NULL DEFAULT 10485760,
    "contentLength" bigint,
    "preventOverwrite" boolean NOT NULL DEFAULT false,
    "contentType" text,
    "cacheControl" text,
    "contentDisposition" text,
    "contentEncoding" text,
    "customMetadata" text
);

-- Indexes
CREATE UNIQUE INDEX "serverpod_cloud_storage_direct_upload_storage_path" ON "serverpod_cloud_storage_direct_upload" USING btree ("storageId", "path");

--
-- Class FutureCallEntry as table serverpod_future_call
--
CREATE TABLE "serverpod_future_call" (
    "id" bigserial PRIMARY KEY,
    "name" text NOT NULL,
    "time" timestamp without time zone NOT NULL,
    "serializedObject" text,
    "serverId" text NOT NULL,
    "identifier" text,
    "scheduling" json
);

-- Indexes
CREATE INDEX "serverpod_future_call_time_idx" ON "serverpod_future_call" USING btree ("time");
CREATE INDEX "serverpod_future_call_serverId_idx" ON "serverpod_future_call" USING btree ("serverId");
CREATE INDEX "serverpod_future_call_identifier_idx" ON "serverpod_future_call" USING btree ("identifier");

--
-- Class FutureCallClaimEntry as table serverpod_future_call_claim
--
CREATE TABLE "serverpod_future_call_claim" (
    "id" bigserial PRIMARY KEY,
    "futureCallId" bigint,
    "lastHeartbeatTime" timestamp without time zone NOT NULL
);

-- Indexes
CREATE UNIQUE INDEX "future_call_unique_idx" ON "serverpod_future_call_claim" USING btree ("futureCallId");

--
-- Class ServerHealthConnectionInfo as table serverpod_health_connection_info
--
CREATE TABLE "serverpod_health_connection_info" (
    "id" bigserial PRIMARY KEY,
    "serverId" text NOT NULL,
    "timestamp" timestamp without time zone NOT NULL,
    "active" bigint NOT NULL,
    "closing" bigint NOT NULL,
    "idle" bigint NOT NULL,
    "granularity" bigint NOT NULL
);

-- Indexes
CREATE UNIQUE INDEX "serverpod_health_connection_info_timestamp_idx" ON "serverpod_health_connection_info" USING btree ("timestamp", "serverId", "granularity");

--
-- Class ServerHealthMetric as table serverpod_health_metric
--
CREATE TABLE "serverpod_health_metric" (
    "id" bigserial PRIMARY KEY,
    "name" text NOT NULL,
    "serverId" text NOT NULL,
    "timestamp" timestamp without time zone NOT NULL,
    "isHealthy" boolean NOT NULL,
    "value" double precision NOT NULL,
    "granularity" bigint NOT NULL
);

-- Indexes
CREATE UNIQUE INDEX "serverpod_health_metric_timestamp_idx" ON "serverpod_health_metric" USING btree ("timestamp", "serverId", "name", "granularity");

--
-- Class LogEntry as table serverpod_log
--
CREATE TABLE "serverpod_log" (
    "id" bigserial PRIMARY KEY,
    "sessionLogId" bigint NOT NULL,
    "messageId" bigint,
    "reference" text,
    "serverId" text NOT NULL,
    "time" timestamp without time zone NOT NULL,
    "logLevel" bigint NOT NULL,
    "message" text NOT NULL,
    "error" text,
    "stackTrace" text,
    "order" bigint NOT NULL
);

-- Indexes
CREATE INDEX "serverpod_log_sessionLogId_idx" ON "serverpod_log" USING btree ("sessionLogId", "order");

--
-- Class MessageLogEntry as table serverpod_message_log
--
CREATE TABLE "serverpod_message_log" (
    "id" bigserial PRIMARY KEY,
    "sessionLogId" bigint NOT NULL,
    "serverId" text NOT NULL,
    "messageId" bigint NOT NULL,
    "endpoint" text NOT NULL,
    "messageName" text NOT NULL,
    "duration" double precision NOT NULL,
    "error" text,
    "stackTrace" text,
    "slow" boolean NOT NULL,
    "order" bigint NOT NULL
);

-- Indexes
CREATE INDEX "serverpod_message_log_sessionLogId_idx" ON "serverpod_message_log" USING btree ("sessionLogId", "order");

--
-- Class MethodInfo as table serverpod_method
--
CREATE TABLE "serverpod_method" (
    "id" bigserial PRIMARY KEY,
    "endpoint" text NOT NULL,
    "method" text NOT NULL
);

-- Indexes
CREATE UNIQUE INDEX "serverpod_method_endpoint_method_idx" ON "serverpod_method" USING btree ("endpoint", "method");

--
-- Class DatabaseMigrationVersion as table serverpod_migrations
--
CREATE TABLE "serverpod_migrations" (
    "id" bigserial PRIMARY KEY,
    "module" text NOT NULL,
    "version" text NOT NULL,
    "timestamp" timestamp without time zone
);

-- Indexes
CREATE UNIQUE INDEX "serverpod_migrations_ids" ON "serverpod_migrations" USING btree ("module");

--
-- Class QueryLogEntry as table serverpod_query_log
--
CREATE TABLE "serverpod_query_log" (
    "id" bigserial PRIMARY KEY,
    "serverId" text NOT NULL,
    "sessionLogId" bigint NOT NULL,
    "messageId" bigint,
    "query" text NOT NULL,
    "duration" double precision NOT NULL,
    "numRows" bigint,
    "error" text,
    "stackTrace" text,
    "slow" boolean NOT NULL,
    "order" bigint NOT NULL
);

-- Indexes
CREATE INDEX "serverpod_query_log_sessionLogId_idx" ON "serverpod_query_log" USING btree ("sessionLogId", "order");

--
-- Class ReadWriteTestEntry as table serverpod_readwrite_test
--
CREATE TABLE "serverpod_readwrite_test" (
    "id" bigserial PRIMARY KEY,
    "number" bigint NOT NULL
);

--
-- Class RuntimeSettings as table serverpod_runtime_settings
--
CREATE TABLE "serverpod_runtime_settings" (
    "id" bigserial PRIMARY KEY,
    "logSettings" json NOT NULL,
    "logSettingsOverrides" json NOT NULL,
    "logServiceCalls" boolean NOT NULL,
    "logMalformedCalls" boolean NOT NULL
);

--
-- Class SessionLogEntry as table serverpod_session_log
--
CREATE TABLE "serverpod_session_log" (
    "id" bigserial PRIMARY KEY,
    "serverId" text NOT NULL,
    "time" timestamp without time zone NOT NULL,
    "module" text,
    "endpoint" text,
    "method" text,
    "duration" double precision,
    "numQueries" bigint,
    "slow" boolean,
    "error" text,
    "stackTrace" text,
    "authenticatedUserId" bigint,
    "userId" text,
    "isOpen" boolean,
    "touched" timestamp without time zone NOT NULL
);

-- Indexes
CREATE INDEX "serverpod_session_log_serverid_idx" ON "serverpod_session_log" USING btree ("serverId");
CREATE INDEX "serverpod_session_log_time_idx" ON "serverpod_session_log" USING btree ("time");
CREATE INDEX "serverpod_session_log_touched_idx" ON "serverpod_session_log" USING btree ("touched");
CREATE INDEX "serverpod_session_log_isopen_idx" ON "serverpod_session_log" USING btree ("isOpen");

--
-- Class AnonymousAccount as table serverpod_auth_idp_anonymous_account
--
CREATE TABLE "serverpod_auth_idp_anonymous_account" (
    "id" uuid PRIMARY KEY DEFAULT gen_random_uuid_v7(),
    "authUserId" uuid NOT NULL,
    "createdAt" timestamp without time zone NOT NULL
);

--
-- Class AppleAccount as table serverpod_auth_idp_apple_account
--
CREATE TABLE "serverpod_auth_idp_apple_account" (
    "id" uuid PRIMARY KEY DEFAULT gen_random_uuid_v7(),
    "userIdentifier" text NOT NULL,
    "refreshToken" text NOT NULL,
    "refreshTokenRequestedWithBundleIdentifier" boolean NOT NULL,
    "lastRefreshedAt" timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "authUserId" uuid NOT NULL,
    "createdAt" timestamp without time zone NOT NULL,
    "email" text,
    "isEmailVerified" boolean,
    "isPrivateEmail" boolean,
    "firstName" text,
    "lastName" text
);

-- Indexes
CREATE UNIQUE INDEX "serverpod_auth_apple_account_identifier" ON "serverpod_auth_idp_apple_account" USING btree ("userIdentifier");

--
-- Class EmailAccount as table serverpod_auth_idp_email_account
--
CREATE TABLE "serverpod_auth_idp_email_account" (
    "id" uuid PRIMARY KEY DEFAULT gen_random_uuid_v7(),
    "authUserId" uuid NOT NULL,
    "createdAt" timestamp without time zone NOT NULL,
    "email" text NOT NULL,
    "passwordHash" text NOT NULL
);

-- Indexes
CREATE UNIQUE INDEX "serverpod_auth_idp_email_account_email" ON "serverpod_auth_idp_email_account" USING btree ("email");

--
-- Class EmailAccountPasswordResetRequest as table serverpod_auth_idp_email_account_password_reset_request
--
CREATE TABLE "serverpod_auth_idp_email_account_password_reset_request" (
    "id" uuid PRIMARY KEY DEFAULT gen_random_uuid_v7(),
    "emailAccountId" uuid NOT NULL,
    "createdAt" timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "challengeId" uuid NOT NULL,
    "setPasswordChallengeId" uuid
);

--
-- Class EmailAccountRequest as table serverpod_auth_idp_email_account_request
--
CREATE TABLE "serverpod_auth_idp_email_account_request" (
    "id" uuid PRIMARY KEY DEFAULT gen_random_uuid_v7(),
    "createdAt" timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "email" text NOT NULL,
    "challengeId" uuid NOT NULL,
    "createAccountChallengeId" uuid
);

-- Indexes
CREATE UNIQUE INDEX "serverpod_auth_idp_email_account_request_email" ON "serverpod_auth_idp_email_account_request" USING btree ("email");

--
-- Class FacebookAccount as table serverpod_auth_idp_facebook_account
--
CREATE TABLE "serverpod_auth_idp_facebook_account" (
    "id" uuid PRIMARY KEY DEFAULT gen_random_uuid_v7(),
    "authUserId" uuid NOT NULL,
    "createdAt" timestamp without time zone NOT NULL,
    "userIdentifier" text NOT NULL,
    "email" text,
    "fullName" text,
    "firstName" text,
    "lastName" text
);

-- Indexes
CREATE UNIQUE INDEX "serverpod_auth_facebook_account_user_identifier" ON "serverpod_auth_idp_facebook_account" USING btree ("userIdentifier");

--
-- Class FirebaseAccount as table serverpod_auth_idp_firebase_account
--
CREATE TABLE "serverpod_auth_idp_firebase_account" (
    "id" uuid PRIMARY KEY DEFAULT gen_random_uuid_v7(),
    "authUserId" uuid NOT NULL,
    "created" timestamp without time zone NOT NULL,
    "email" text,
    "phone" text,
    "userIdentifier" text NOT NULL
);

-- Indexes
CREATE UNIQUE INDEX "serverpod_auth_firebase_account_user_identifier" ON "serverpod_auth_idp_firebase_account" USING btree ("userIdentifier");

--
-- Class GitHubAccount as table serverpod_auth_idp_github_account
--
CREATE TABLE "serverpod_auth_idp_github_account" (
    "id" uuid PRIMARY KEY DEFAULT gen_random_uuid_v7(),
    "authUserId" uuid NOT NULL,
    "userIdentifier" text NOT NULL,
    "email" text,
    "created" timestamp without time zone NOT NULL
);

-- Indexes
CREATE UNIQUE INDEX "serverpod_auth_github_account_user_identifier" ON "serverpod_auth_idp_github_account" USING btree ("userIdentifier");

--
-- Class GoogleAccount as table serverpod_auth_idp_google_account
--
CREATE TABLE "serverpod_auth_idp_google_account" (
    "id" uuid PRIMARY KEY DEFAULT gen_random_uuid_v7(),
    "authUserId" uuid NOT NULL,
    "created" timestamp without time zone NOT NULL,
    "email" text NOT NULL,
    "userIdentifier" text NOT NULL
);

-- Indexes
CREATE UNIQUE INDEX "serverpod_auth_google_account_user_identifier" ON "serverpod_auth_idp_google_account" USING btree ("userIdentifier");

--
-- Class MicrosoftAccount as table serverpod_auth_idp_microsoft_account
--
CREATE TABLE "serverpod_auth_idp_microsoft_account" (
    "id" uuid PRIMARY KEY DEFAULT gen_random_uuid_v7(),
    "authUserId" uuid NOT NULL,
    "userIdentifier" text NOT NULL,
    "email" text,
    "created" timestamp without time zone NOT NULL
);

-- Indexes
CREATE UNIQUE INDEX "serverpod_auth_microsoft_account_user_identifier" ON "serverpod_auth_idp_microsoft_account" USING btree ("userIdentifier");

--
-- Class PasskeyAccount as table serverpod_auth_idp_passkey_account
--
CREATE TABLE "serverpod_auth_idp_passkey_account" (
    "id" uuid PRIMARY KEY DEFAULT gen_random_uuid_v7(),
    "authUserId" uuid NOT NULL,
    "createdAt" timestamp without time zone NOT NULL,
    "keyId" bytea NOT NULL,
    "keyIdBase64" text NOT NULL,
    "clientDataJSON" bytea NOT NULL,
    "attestationObject" bytea NOT NULL,
    "originalChallenge" bytea NOT NULL
);

-- Indexes
CREATE UNIQUE INDEX "serverpod_auth_idp_passkey_account_key_id_base64" ON "serverpod_auth_idp_passkey_account" USING btree ("keyIdBase64");

--
-- Class PasskeyChallenge as table serverpod_auth_idp_passkey_challenge
--
CREATE TABLE "serverpod_auth_idp_passkey_challenge" (
    "id" uuid PRIMARY KEY DEFAULT gen_random_uuid_v7(),
    "createdAt" timestamp without time zone NOT NULL,
    "challenge" bytea NOT NULL
);

--
-- Class RateLimitedRequestAttempt as table serverpod_auth_idp_rate_limited_request_attempt
--
CREATE TABLE "serverpod_auth_idp_rate_limited_request_attempt" (
    "id" uuid PRIMARY KEY DEFAULT gen_random_uuid_v7(),
    "domain" text NOT NULL,
    "source" text NOT NULL,
    "key" text NOT NULL,
    "ipAddress" text,
    "attemptedAt" timestamp without time zone NOT NULL,
    "extraData" json
);

-- Indexes
CREATE INDEX "serverpod_auth_idp_rate_limited_request_attempt_composite" ON "serverpod_auth_idp_rate_limited_request_attempt" USING btree ("domain", "source", "key", "attemptedAt");

--
-- Class SecretChallenge as table serverpod_auth_idp_secret_challenge
--
CREATE TABLE "serverpod_auth_idp_secret_challenge" (
    "id" uuid PRIMARY KEY DEFAULT gen_random_uuid_v7(),
    "challengeCodeHash" text NOT NULL
);

--
-- Class RefreshToken as table serverpod_auth_core_jwt_refresh_token
--
CREATE TABLE "serverpod_auth_core_jwt_refresh_token" (
    "id" uuid PRIMARY KEY DEFAULT gen_random_uuid_v7(),
    "authUserId" uuid NOT NULL,
    "scopeNames" json NOT NULL,
    "extraClaims" text,
    "method" text NOT NULL,
    "fixedSecret" bytea NOT NULL,
    "rotatingSecretHash" text NOT NULL,
    "lastUpdatedAt" timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "createdAt" timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Indexes
CREATE INDEX "serverpod_auth_core_jwt_refresh_token_last_updated_at" ON "serverpod_auth_core_jwt_refresh_token" USING btree ("lastUpdatedAt");

--
-- Class UserProfile as table serverpod_auth_core_profile
--
CREATE TABLE "serverpod_auth_core_profile" (
    "id" uuid PRIMARY KEY DEFAULT gen_random_uuid_v7(),
    "authUserId" uuid NOT NULL,
    "userName" text,
    "fullName" text,
    "email" text,
    "createdAt" timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "imageId" uuid
);

-- Indexes
CREATE UNIQUE INDEX "serverpod_auth_profile_user_profile_email_auth_user_id" ON "serverpod_auth_core_profile" USING btree ("authUserId");

--
-- Class UserProfileImage as table serverpod_auth_core_profile_image
--
CREATE TABLE "serverpod_auth_core_profile_image" (
    "id" uuid PRIMARY KEY DEFAULT gen_random_uuid_v7(),
    "userProfileId" uuid NOT NULL,
    "createdAt" timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "storageId" text NOT NULL,
    "path" text NOT NULL,
    "url" text NOT NULL
);

--
-- Class ServerSideSession as table serverpod_auth_core_session
--
CREATE TABLE "serverpod_auth_core_session" (
    "id" uuid PRIMARY KEY DEFAULT gen_random_uuid_v7(),
    "authUserId" uuid NOT NULL,
    "scopeNames" json NOT NULL,
    "createdAt" timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "lastUsedAt" timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "expiresAt" timestamp without time zone,
    "expireAfterUnusedFor" bigint,
    "sessionKeyHash" bytea NOT NULL,
    "sessionKeySalt" bytea NOT NULL,
    "method" text NOT NULL
);

--
-- Class AuthUser as table serverpod_auth_core_user
--
CREATE TABLE "serverpod_auth_core_user" (
    "id" uuid PRIMARY KEY DEFAULT gen_random_uuid_v7(),
    "createdAt" timestamp without time zone NOT NULL,
    "scopeNames" json NOT NULL,
    "blocked" boolean NOT NULL
);

--
-- Foreign relations for "nest_app" table
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
-- Foreign relations for "nest_audit" table
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
-- Foreign relations for "nest_automation" table
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
-- Foreign relations for "nest_claim" table
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
-- Foreign relations for "nest_draft" table
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
-- Foreign relations for "nest_field_value" table
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
-- Foreign relations for "nest_generation" table
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
-- Foreign relations for "nest_grant" table
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
-- Foreign relations for "nest_invitation" table
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
-- Foreign relations for "nest_notification" table
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
-- Foreign relations for "nest_outbox" table
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
-- Foreign relations for "nest_pool" table
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
-- Foreign relations for "nest_receipt" table
--
ALTER TABLE ONLY "nest_receipt"
    ADD CONSTRAINT "nest_receipt_fk_0"
    FOREIGN KEY("appId")
    REFERENCES "nest_app"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;

--
-- Foreign relations for "nest_record" table
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
-- Foreign relations for "nest_run" table
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
-- Foreign relations for "nest_shortcut" table
--
ALTER TABLE ONLY "nest_shortcut"
    ADD CONSTRAINT "nest_shortcut_fk_0"
    FOREIGN KEY("appId")
    REFERENCES "nest_app"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;

--
-- Foreign relations for "nest_version" table
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
-- Foreign relations for "nest_workspace_member" table
--
ALTER TABLE ONLY "nest_workspace_member"
    ADD CONSTRAINT "nest_workspace_member_fk_0"
    FOREIGN KEY("workspaceId")
    REFERENCES "nest_workspace"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;

--
-- Foreign relations for "serverpod_future_call_claim" table
--
ALTER TABLE ONLY "serverpod_future_call_claim"
    ADD CONSTRAINT "serverpod_future_call_claim_fk_0"
    FOREIGN KEY("futureCallId")
    REFERENCES "serverpod_future_call"("id")
    ON DELETE CASCADE
    ON UPDATE NO ACTION;

--
-- Foreign relations for "serverpod_log" table
--
ALTER TABLE ONLY "serverpod_log"
    ADD CONSTRAINT "serverpod_log_fk_0"
    FOREIGN KEY("sessionLogId")
    REFERENCES "serverpod_session_log"("id")
    ON DELETE CASCADE
    ON UPDATE NO ACTION;

--
-- Foreign relations for "serverpod_message_log" table
--
ALTER TABLE ONLY "serverpod_message_log"
    ADD CONSTRAINT "serverpod_message_log_fk_0"
    FOREIGN KEY("sessionLogId")
    REFERENCES "serverpod_session_log"("id")
    ON DELETE CASCADE
    ON UPDATE NO ACTION;

--
-- Foreign relations for "serverpod_query_log" table
--
ALTER TABLE ONLY "serverpod_query_log"
    ADD CONSTRAINT "serverpod_query_log_fk_0"
    FOREIGN KEY("sessionLogId")
    REFERENCES "serverpod_session_log"("id")
    ON DELETE CASCADE
    ON UPDATE NO ACTION;

--
-- Foreign relations for "serverpod_auth_idp_anonymous_account" table
--
ALTER TABLE ONLY "serverpod_auth_idp_anonymous_account"
    ADD CONSTRAINT "serverpod_auth_idp_anonymous_account_fk_0"
    FOREIGN KEY("authUserId")
    REFERENCES "serverpod_auth_core_user"("id")
    ON DELETE CASCADE
    ON UPDATE NO ACTION;

--
-- Foreign relations for "serverpod_auth_idp_apple_account" table
--
ALTER TABLE ONLY "serverpod_auth_idp_apple_account"
    ADD CONSTRAINT "serverpod_auth_idp_apple_account_fk_0"
    FOREIGN KEY("authUserId")
    REFERENCES "serverpod_auth_core_user"("id")
    ON DELETE CASCADE
    ON UPDATE NO ACTION;

--
-- Foreign relations for "serverpod_auth_idp_email_account" table
--
ALTER TABLE ONLY "serverpod_auth_idp_email_account"
    ADD CONSTRAINT "serverpod_auth_idp_email_account_fk_0"
    FOREIGN KEY("authUserId")
    REFERENCES "serverpod_auth_core_user"("id")
    ON DELETE CASCADE
    ON UPDATE NO ACTION;

--
-- Foreign relations for "serverpod_auth_idp_email_account_password_reset_request" table
--
ALTER TABLE ONLY "serverpod_auth_idp_email_account_password_reset_request"
    ADD CONSTRAINT "serverpod_auth_idp_email_account_password_reset_request_fk_0"
    FOREIGN KEY("emailAccountId")
    REFERENCES "serverpod_auth_idp_email_account"("id")
    ON DELETE CASCADE
    ON UPDATE NO ACTION;
ALTER TABLE ONLY "serverpod_auth_idp_email_account_password_reset_request"
    ADD CONSTRAINT "serverpod_auth_idp_email_account_password_reset_request_fk_1"
    FOREIGN KEY("challengeId")
    REFERENCES "serverpod_auth_idp_secret_challenge"("id")
    ON DELETE CASCADE
    ON UPDATE NO ACTION;
ALTER TABLE ONLY "serverpod_auth_idp_email_account_password_reset_request"
    ADD CONSTRAINT "serverpod_auth_idp_email_account_password_reset_request_fk_2"
    FOREIGN KEY("setPasswordChallengeId")
    REFERENCES "serverpod_auth_idp_secret_challenge"("id")
    ON DELETE CASCADE
    ON UPDATE NO ACTION;

--
-- Foreign relations for "serverpod_auth_idp_email_account_request" table
--
ALTER TABLE ONLY "serverpod_auth_idp_email_account_request"
    ADD CONSTRAINT "serverpod_auth_idp_email_account_request_fk_0"
    FOREIGN KEY("challengeId")
    REFERENCES "serverpod_auth_idp_secret_challenge"("id")
    ON DELETE CASCADE
    ON UPDATE NO ACTION;
ALTER TABLE ONLY "serverpod_auth_idp_email_account_request"
    ADD CONSTRAINT "serverpod_auth_idp_email_account_request_fk_1"
    FOREIGN KEY("createAccountChallengeId")
    REFERENCES "serverpod_auth_idp_secret_challenge"("id")
    ON DELETE CASCADE
    ON UPDATE NO ACTION;

--
-- Foreign relations for "serverpod_auth_idp_facebook_account" table
--
ALTER TABLE ONLY "serverpod_auth_idp_facebook_account"
    ADD CONSTRAINT "serverpod_auth_idp_facebook_account_fk_0"
    FOREIGN KEY("authUserId")
    REFERENCES "serverpod_auth_core_user"("id")
    ON DELETE CASCADE
    ON UPDATE NO ACTION;

--
-- Foreign relations for "serverpod_auth_idp_firebase_account" table
--
ALTER TABLE ONLY "serverpod_auth_idp_firebase_account"
    ADD CONSTRAINT "serverpod_auth_idp_firebase_account_fk_0"
    FOREIGN KEY("authUserId")
    REFERENCES "serverpod_auth_core_user"("id")
    ON DELETE CASCADE
    ON UPDATE NO ACTION;

--
-- Foreign relations for "serverpod_auth_idp_github_account" table
--
ALTER TABLE ONLY "serverpod_auth_idp_github_account"
    ADD CONSTRAINT "serverpod_auth_idp_github_account_fk_0"
    FOREIGN KEY("authUserId")
    REFERENCES "serverpod_auth_core_user"("id")
    ON DELETE CASCADE
    ON UPDATE NO ACTION;

--
-- Foreign relations for "serverpod_auth_idp_google_account" table
--
ALTER TABLE ONLY "serverpod_auth_idp_google_account"
    ADD CONSTRAINT "serverpod_auth_idp_google_account_fk_0"
    FOREIGN KEY("authUserId")
    REFERENCES "serverpod_auth_core_user"("id")
    ON DELETE CASCADE
    ON UPDATE NO ACTION;

--
-- Foreign relations for "serverpod_auth_idp_microsoft_account" table
--
ALTER TABLE ONLY "serverpod_auth_idp_microsoft_account"
    ADD CONSTRAINT "serverpod_auth_idp_microsoft_account_fk_0"
    FOREIGN KEY("authUserId")
    REFERENCES "serverpod_auth_core_user"("id")
    ON DELETE CASCADE
    ON UPDATE NO ACTION;

--
-- Foreign relations for "serverpod_auth_idp_passkey_account" table
--
ALTER TABLE ONLY "serverpod_auth_idp_passkey_account"
    ADD CONSTRAINT "serverpod_auth_idp_passkey_account_fk_0"
    FOREIGN KEY("authUserId")
    REFERENCES "serverpod_auth_core_user"("id")
    ON DELETE CASCADE
    ON UPDATE NO ACTION;

--
-- Foreign relations for "serverpod_auth_core_jwt_refresh_token" table
--
ALTER TABLE ONLY "serverpod_auth_core_jwt_refresh_token"
    ADD CONSTRAINT "serverpod_auth_core_jwt_refresh_token_fk_0"
    FOREIGN KEY("authUserId")
    REFERENCES "serverpod_auth_core_user"("id")
    ON DELETE CASCADE
    ON UPDATE NO ACTION;

--
-- Foreign relations for "serverpod_auth_core_profile" table
--
ALTER TABLE ONLY "serverpod_auth_core_profile"
    ADD CONSTRAINT "serverpod_auth_core_profile_fk_0"
    FOREIGN KEY("authUserId")
    REFERENCES "serverpod_auth_core_user"("id")
    ON DELETE CASCADE
    ON UPDATE NO ACTION;
ALTER TABLE ONLY "serverpod_auth_core_profile"
    ADD CONSTRAINT "serverpod_auth_core_profile_fk_1"
    FOREIGN KEY("imageId")
    REFERENCES "serverpod_auth_core_profile_image"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;

--
-- Foreign relations for "serverpod_auth_core_profile_image" table
--
ALTER TABLE ONLY "serverpod_auth_core_profile_image"
    ADD CONSTRAINT "serverpod_auth_core_profile_image_fk_0"
    FOREIGN KEY("userProfileId")
    REFERENCES "serverpod_auth_core_profile"("id")
    ON DELETE CASCADE
    ON UPDATE NO ACTION;

--
-- Foreign relations for "serverpod_auth_core_session" table
--
ALTER TABLE ONLY "serverpod_auth_core_session"
    ADD CONSTRAINT "serverpod_auth_core_session_fk_0"
    FOREIGN KEY("authUserId")
    REFERENCES "serverpod_auth_core_user"("id")
    ON DELETE CASCADE
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

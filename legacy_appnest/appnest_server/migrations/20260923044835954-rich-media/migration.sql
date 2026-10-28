BEGIN;

--
-- ACTION CREATE TABLE
--
CREATE TABLE "nest_media_asset" (
    "id" bigserial PRIMARY KEY,
    "assetId" text NOT NULL,
    "appId" bigint NOT NULL,
    "workspaceId" bigint NOT NULL,
    "uploaderId" text NOT NULL,
    "idempotencyKey" text NOT NULL,
    "requestHash" text NOT NULL,
    "requestJson" text NOT NULL,
    "uploadDescription" text,
    "status" text NOT NULL,
    "contentType" text NOT NULL,
    "byteLength" bigint NOT NULL,
    "storedBytes" bigint NOT NULL,
    "width" bigint NOT NULL DEFAULT 0,
    "height" bigint NOT NULL DEFAULT 0,
    "expiresAt" timestamp without time zone NOT NULL,
    "leaseUntil" timestamp without time zone,
    "createdAt" timestamp without time zone NOT NULL,
    "updatedAt" timestamp without time zone NOT NULL
);

-- Indexes
CREATE UNIQUE INDEX "media_asset_identity" ON "nest_media_asset" USING btree ("assetId");
CREATE UNIQUE INDEX "media_upload_receipt" ON "nest_media_asset" USING btree ("appId", "uploaderId", "idempotencyKey");
CREATE INDEX "media_cleanup" ON "nest_media_asset" USING btree ("status", "updatedAt");

--
-- ACTION CREATE TABLE
--
CREATE TABLE "nest_media_reference" (
    "id" bigserial PRIMARY KEY,
    "appId" bigint NOT NULL,
    "assetRowId" bigint NOT NULL,
    "draftId" bigint,
    "versionId" bigint,
    "recordId" bigint
);

-- Indexes
CREATE INDEX "media_reference_asset" ON "nest_media_reference" USING btree ("assetRowId");
CREATE INDEX "media_reference_draft" ON "nest_media_reference" USING btree ("draftId");
CREATE INDEX "media_reference_version" ON "nest_media_reference" USING btree ("versionId");
CREATE INDEX "media_reference_record" ON "nest_media_reference" USING btree ("recordId");

--
-- ACTION CREATE FOREIGN KEY
--
ALTER TABLE ONLY "nest_media_asset"
    ADD CONSTRAINT "nest_media_asset_fk_0"
    FOREIGN KEY("appId")
    REFERENCES "nest_app"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;
ALTER TABLE ONLY "nest_media_asset"
    ADD CONSTRAINT "nest_media_asset_fk_1"
    FOREIGN KEY("workspaceId")
    REFERENCES "nest_workspace"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;

--
-- ACTION CREATE FOREIGN KEY
--
ALTER TABLE ONLY "nest_media_reference"
    ADD CONSTRAINT "nest_media_reference_fk_0"
    FOREIGN KEY("appId")
    REFERENCES "nest_app"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;
ALTER TABLE ONLY "nest_media_reference"
    ADD CONSTRAINT "nest_media_reference_fk_1"
    FOREIGN KEY("assetRowId")
    REFERENCES "nest_media_asset"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;
ALTER TABLE ONLY "nest_media_reference"
    ADD CONSTRAINT "nest_media_reference_fk_2"
    FOREIGN KEY("draftId")
    REFERENCES "nest_draft"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;
ALTER TABLE ONLY "nest_media_reference"
    ADD CONSTRAINT "nest_media_reference_fk_3"
    FOREIGN KEY("versionId")
    REFERENCES "nest_version"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;
ALTER TABLE ONLY "nest_media_reference"
    ADD CONSTRAINT "nest_media_reference_fk_4"
    FOREIGN KEY("recordId")
    REFERENCES "nest_record"("id")
    ON DELETE NO ACTION
    ON UPDATE NO ACTION;


--
-- MIGRATION VERSION FOR appnest
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('appnest', '20260923044835954-rich-media', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20260923044835954-rich-media', "timestamp" = now();

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

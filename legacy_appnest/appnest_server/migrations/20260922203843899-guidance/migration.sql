BEGIN;

--
-- ACTION CREATE TABLE
--
CREATE TABLE "nest_guidance_request" (
    "id" bigserial PRIMARY KEY,
    "actorId" text NOT NULL,
    "createdAt" timestamp without time zone NOT NULL
);

-- Indexes
CREATE INDEX "guidance_actor_created" ON "nest_guidance_request" USING btree ("actorId", "createdAt");


--
-- MIGRATION VERSION FOR appnest
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('appnest', '20260922203843899-guidance', now())
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20260922203843899-guidance', "timestamp" = now();

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

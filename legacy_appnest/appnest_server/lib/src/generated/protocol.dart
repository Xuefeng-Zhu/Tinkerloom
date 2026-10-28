/* AUTOMATICALLY GENERATED CODE DO NOT MODIFY */
/*   To generate run: "serverpod generate"    */

// ignore_for_file: implementation_imports
// ignore_for_file: library_private_types_in_public_api
// ignore_for_file: non_constant_identifier_names
// ignore_for_file: public_member_api_docs
// ignore_for_file: type_literal_in_constant_pattern
// ignore_for_file: use_super_parameters
// ignore_for_file: invalid_use_of_internal_member
// ignore_for_file: dead_code, unnecessary_type_check

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:appnest_server/src/generated/activity_item.dart' as _irfbx1ex;
import 'package:appnest_server/src/generated/app_manifest.dart' as _i5x0vch8;
import 'package:appnest_server/src/generated/guidance_question.dart'
    as _i42yij2w;
import 'package:appnest_server/src/generated/inbox_item.dart' as _iofnszjt;
import 'package:appnest_server/src/generated/member_info.dart' as _ii9ccrrn;
import 'package:appnest_server/src/generated/reminder_state.dart' as _ihdyt6mq;
import 'package:appnest_server/src/generated/template_info.dart' as _iacdzrq5;
import 'package:appnest_server/src/generated/workspace_info.dart' as _i829frra;
import 'package:serverpod/protocol.dart' as _isp;
import 'package:serverpod/serverpod.dart' as _is;
import 'package:serverpod_auth_core_server/serverpod_auth_core_server.dart'
    as _iacs;
import 'package:serverpod_auth_idp_server/serverpod_auth_idp_server.dart'
    as _iais;
import 'action_outcome.dart' as _isykbnbw;
import 'action_receipt.dart' as _izkbb96g;
import 'action_request.dart' as _ii1w3lxm;
import 'activity_item.dart' as _irh51hj1;
import 'app_draft.dart' as _iq0wu3gu;
import 'app_event.dart' as _iwn9176r;
import 'app_manifest.dart' as _i65w4jw3;
import 'app_shortcut.dart' as _i1wu1dla;
import 'app_version.dart' as _izejoxi5;
import 'audit_entry.dart' as _i1613bfs;
import 'automation.dart' as _ife4t62f;
import 'automation_run.dart' as _ixu7zng5;
import 'builder_snapshot.dart' as _i4n6ivgk;
import 'claim.dart' as _iywv5oz4;
import 'entity_record.dart' as _iy0qwluf;
import 'field_value.dart' as _iyrqavho;
import 'future_calls_generated_models/nest_worker_future_call_execute_model.dart'
    as _i2npzse7;
import 'future_calls_generated_models/nest_worker_future_call_generate_model.dart'
    as _i7d9xtt1;
import 'generation_job.dart' as _ig17l95t;
import 'greetings/greeting.dart' as _izw8z7ou;
import 'guidance_question.dart' as _istc82cm;
import 'guidance_request.dart' as _i3j1yq52;
import 'inbox_item.dart' as _iv6iq8qv;
import 'invitation.dart' as _ix00wubs;
import 'media_asset.dart' as _ivzdqkik;
import 'media_info.dart' as _iyb2dgte;
import 'media_reference.dart' as _il7l0uyh;
import 'media_upload_request.dart' as _i6mex4av;
import 'media_upload_ticket.dart' as _iu821fma;
import 'member_info.dart' as _i2slp771;
import 'mini_app.dart' as _ivniu53p;
import 'mini_app_grant.dart' as _iurwb5gp;
import 'nest_error.dart' as _i0tc2cek;
import 'notification.dart' as _irt10kca;
import 'outbox_event.dart' as _i6i2iffh;
import 'platform_info.dart' as _ici3to49;
import 'publish_request.dart' as _iijemlr5;
import 'record_page.dart' as _i4a9pphb;
import 'record_summary.dart' as _ifx2sflx;
import 'reminder_state.dart' as _ipsxd53m;
import 'resource_pool.dart' as _i6hl3xhc;
import 'runtime_record.dart' as _ilpx295a;
import 'template.dart' as _ibutn46j;
import 'template_info.dart' as _i1ykl0x7;
import 'workspace.dart' as _io6eoug6;
import 'workspace_info.dart' as _ixz9batj;
import 'workspace_member.dart' as _iidcmvkk;
export 'action_outcome.dart';
export 'action_receipt.dart';
export 'action_request.dart';
export 'activity_item.dart';
export 'app_draft.dart';
export 'app_event.dart';
export 'app_manifest.dart';
export 'app_shortcut.dart';
export 'app_version.dart';
export 'audit_entry.dart';
export 'automation.dart';
export 'automation_run.dart';
export 'builder_snapshot.dart';
export 'claim.dart';
export 'entity_record.dart';
export 'field_value.dart';
export 'generation_job.dart';
export 'greetings/greeting.dart';
export 'guidance_question.dart';
export 'guidance_request.dart';
export 'inbox_item.dart';
export 'invitation.dart';
export 'media_asset.dart';
export 'media_info.dart';
export 'media_reference.dart';
export 'media_upload_request.dart';
export 'media_upload_ticket.dart';
export 'member_info.dart';
export 'mini_app.dart';
export 'mini_app_grant.dart';
export 'nest_error.dart';
export 'notification.dart';
export 'outbox_event.dart';
export 'platform_info.dart';
export 'publish_request.dart';
export 'record_page.dart';
export 'record_summary.dart';
export 'reminder_state.dart';
export 'resource_pool.dart';
export 'runtime_record.dart';
export 'template.dart';
export 'template_info.dart';
export 'workspace.dart';
export 'workspace_info.dart';
export 'workspace_member.dart';

class Protocol extends _is.DatabaseSerializationManager {
  Protocol._();

  factory Protocol() => _instance;

  static final Protocol _instance = Protocol._().._registerHostProtocols();

  static List<_isp.TableDefinition> get targetTableDefinitions => [
    _isp.TableDefinition(
      name: 'nest_app',
      dartName: 'MiniApp',
      schema: 'public',
      module: 'appnest',
      columns: [
        _isp.ColumnDefinition(
          name: 'id',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int?',
          columnDefault: 'serial',
        ),
        _isp.ColumnDefinition(
          name: 'workspaceId',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
        ),
        _isp.ColumnDefinition(
          name: 'ownerId',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'name',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'activeVersionId',
          columnType: _isp.ColumnType.bigint,
          isNullable: true,
          dartType: 'int?',
        ),
        _isp.ColumnDefinition(
          name: 'archived',
          columnType: _isp.ColumnType.boolean,
          isNullable: false,
          dartType: 'bool',
          columnDefault: 'false',
        ),
        _isp.ColumnDefinition(
          name: 'controlRevision',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
          columnDefault: '0',
        ),
        _isp.ColumnDefinition(
          name: 'createdAt',
          columnType: _isp.ColumnType.timestampWithoutTimeZone,
          isNullable: false,
          dartType: 'DateTime',
        ),
      ],
      foreignKeys: [
        _isp.ForeignKeyDefinition(
          constraintName: 'nest_app_fk_0',
          columns: ['workspaceId'],
          referenceTable: 'nest_workspace',
          referenceTableSchema: 'public',
          referenceColumns: ['id'],
          onUpdate: _isp.ForeignKeyAction.noAction,
          onDelete: _isp.ForeignKeyAction.noAction,
          matchType: null,
        ),
        _isp.ForeignKeyDefinition(
          constraintName: 'nest_app_fk_1',
          columns: ['activeVersionId'],
          referenceTable: 'nest_version',
          referenceTableSchema: 'public',
          referenceColumns: ['id'],
          onUpdate: _isp.ForeignKeyAction.noAction,
          onDelete: _isp.ForeignKeyAction.noAction,
          matchType: null,
        ),
      ],
      indexes: [],
      managed: true,
    ),
    _isp.TableDefinition(
      name: 'nest_audit',
      dartName: 'AuditEntry',
      schema: 'public',
      module: 'appnest',
      columns: [
        _isp.ColumnDefinition(
          name: 'id',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int?',
          columnDefault: 'serial',
        ),
        _isp.ColumnDefinition(
          name: 'appId',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
        ),
        _isp.ColumnDefinition(
          name: 'actorId',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'action',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'targetRecordId',
          columnType: _isp.ColumnType.bigint,
          isNullable: true,
          dartType: 'int?',
        ),
        _isp.ColumnDefinition(
          name: 'requestId',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'createdAt',
          columnType: _isp.ColumnType.timestampWithoutTimeZone,
          isNullable: false,
          dartType: 'DateTime',
        ),
      ],
      foreignKeys: [
        _isp.ForeignKeyDefinition(
          constraintName: 'nest_audit_fk_0',
          columns: ['appId'],
          referenceTable: 'nest_app',
          referenceTableSchema: 'public',
          referenceColumns: ['id'],
          onUpdate: _isp.ForeignKeyAction.noAction,
          onDelete: _isp.ForeignKeyAction.noAction,
          matchType: null,
        ),
        _isp.ForeignKeyDefinition(
          constraintName: 'nest_audit_fk_1',
          columns: ['targetRecordId'],
          referenceTable: 'nest_record',
          referenceTableSchema: 'public',
          referenceColumns: ['id'],
          onUpdate: _isp.ForeignKeyAction.noAction,
          onDelete: _isp.ForeignKeyAction.noAction,
          matchType: null,
        ),
      ],
      indexes: [],
      managed: true,
    ),
    _isp.TableDefinition(
      name: 'nest_automation',
      dartName: 'Automation',
      schema: 'public',
      module: 'appnest',
      columns: [
        _isp.ColumnDefinition(
          name: 'id',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int?',
          columnDefault: 'serial',
        ),
        _isp.ColumnDefinition(
          name: 'appId',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
        ),
        _isp.ColumnDefinition(
          name: 'workspaceId',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
        ),
        _isp.ColumnDefinition(
          name: 'ruleId',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'ruleVersion',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
        ),
        _isp.ColumnDefinition(
          name: 'ruleJson',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'enabled',
          columnType: _isp.ColumnType.boolean,
          isNullable: false,
          dartType: 'bool',
        ),
        _isp.ColumnDefinition(
          name: 'executionActorId',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'activateExisting',
          columnType: _isp.ColumnType.boolean,
          isNullable: false,
          dartType: 'bool',
        ),
        _isp.ColumnDefinition(
          name: 'activatedAt',
          columnType: _isp.ColumnType.timestampWithoutTimeZone,
          isNullable: false,
          dartType: 'DateTime',
        ),
      ],
      foreignKeys: [
        _isp.ForeignKeyDefinition(
          constraintName: 'nest_automation_fk_0',
          columns: ['appId'],
          referenceTable: 'nest_app',
          referenceTableSchema: 'public',
          referenceColumns: ['id'],
          onUpdate: _isp.ForeignKeyAction.noAction,
          onDelete: _isp.ForeignKeyAction.noAction,
          matchType: null,
        ),
        _isp.ForeignKeyDefinition(
          constraintName: 'nest_automation_fk_1',
          columns: ['workspaceId'],
          referenceTable: 'nest_workspace',
          referenceTableSchema: 'public',
          referenceColumns: ['id'],
          onUpdate: _isp.ForeignKeyAction.noAction,
          onDelete: _isp.ForeignKeyAction.noAction,
          matchType: null,
        ),
      ],
      indexes: [
        _isp.IndexDefinition(
          indexName: 'rule_unique',
          tableSpace: null,
          elements: [
            _isp.IndexElementDefinition(
              type: _isp.IndexElementDefinitionType.column,
              definition: 'appId',
            ),
            _isp.IndexElementDefinition(
              type: _isp.IndexElementDefinitionType.column,
              definition: 'ruleId',
            ),
          ],
          type: 'btree',
          isUnique: true,
          isPrimary: false,
        ),
      ],
      managed: true,
    ),
    _isp.TableDefinition(
      name: 'nest_claim',
      dartName: 'Claim',
      schema: 'public',
      module: 'appnest',
      columns: [
        _isp.ColumnDefinition(
          name: 'id',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int?',
          columnDefault: 'serial',
        ),
        _isp.ColumnDefinition(
          name: 'appId',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
        ),
        _isp.ColumnDefinition(
          name: 'workspaceId',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
        ),
        _isp.ColumnDefinition(
          name: 'poolId',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
        ),
        _isp.ColumnDefinition(
          name: 'actorId',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'active',
          columnType: _isp.ColumnType.boolean,
          isNullable: false,
          dartType: 'bool',
        ),
        _isp.ColumnDefinition(
          name: 'createdAt',
          columnType: _isp.ColumnType.timestampWithoutTimeZone,
          isNullable: false,
          dartType: 'DateTime',
        ),
        _isp.ColumnDefinition(
          name: 'updatedAt',
          columnType: _isp.ColumnType.timestampWithoutTimeZone,
          isNullable: false,
          dartType: 'DateTime',
        ),
      ],
      foreignKeys: [
        _isp.ForeignKeyDefinition(
          constraintName: 'nest_claim_fk_0',
          columns: ['appId'],
          referenceTable: 'nest_app',
          referenceTableSchema: 'public',
          referenceColumns: ['id'],
          onUpdate: _isp.ForeignKeyAction.noAction,
          onDelete: _isp.ForeignKeyAction.noAction,
          matchType: null,
        ),
        _isp.ForeignKeyDefinition(
          constraintName: 'nest_claim_fk_1',
          columns: ['workspaceId'],
          referenceTable: 'nest_workspace',
          referenceTableSchema: 'public',
          referenceColumns: ['id'],
          onUpdate: _isp.ForeignKeyAction.noAction,
          onDelete: _isp.ForeignKeyAction.noAction,
          matchType: null,
        ),
        _isp.ForeignKeyDefinition(
          constraintName: 'nest_claim_fk_2',
          columns: ['poolId'],
          referenceTable: 'nest_pool',
          referenceTableSchema: 'public',
          referenceColumns: ['id'],
          onUpdate: _isp.ForeignKeyAction.noAction,
          onDelete: _isp.ForeignKeyAction.noAction,
          matchType: null,
        ),
      ],
      indexes: [
        _isp.IndexDefinition(
          indexName: 'claim_unique',
          tableSpace: null,
          elements: [
            _isp.IndexElementDefinition(
              type: _isp.IndexElementDefinitionType.column,
              definition: 'poolId',
            ),
            _isp.IndexElementDefinition(
              type: _isp.IndexElementDefinitionType.column,
              definition: 'actorId',
            ),
          ],
          type: 'btree',
          isUnique: true,
          isPrimary: false,
        ),
      ],
      managed: true,
    ),
    _isp.TableDefinition(
      name: 'nest_draft',
      dartName: 'AppDraft',
      schema: 'public',
      module: 'appnest',
      columns: [
        _isp.ColumnDefinition(
          name: 'id',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int?',
          columnDefault: 'serial',
        ),
        _isp.ColumnDefinition(
          name: 'appId',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
        ),
        _isp.ColumnDefinition(
          name: 'workspaceId',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
        ),
        _isp.ColumnDefinition(
          name: 'actorId',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'baseVersionId',
          columnType: _isp.ColumnType.bigint,
          isNullable: true,
          dartType: 'int?',
        ),
        _isp.ColumnDefinition(
          name: 'candidateJson',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'candidateHash',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'mutation',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
          columnDefault: '0',
        ),
        _isp.ColumnDefinition(
          name: 'activeJobId',
          columnType: _isp.ColumnType.bigint,
          isNullable: true,
          dartType: 'int?',
        ),
        _isp.ColumnDefinition(
          name: 'publishedVersionId',
          columnType: _isp.ColumnType.bigint,
          isNullable: true,
          dartType: 'int?',
        ),
        _isp.ColumnDefinition(
          name: 'updatedAt',
          columnType: _isp.ColumnType.timestampWithoutTimeZone,
          isNullable: false,
          dartType: 'DateTime',
        ),
      ],
      foreignKeys: [
        _isp.ForeignKeyDefinition(
          constraintName: 'nest_draft_fk_0',
          columns: ['appId'],
          referenceTable: 'nest_app',
          referenceTableSchema: 'public',
          referenceColumns: ['id'],
          onUpdate: _isp.ForeignKeyAction.noAction,
          onDelete: _isp.ForeignKeyAction.noAction,
          matchType: null,
        ),
        _isp.ForeignKeyDefinition(
          constraintName: 'nest_draft_fk_1',
          columns: ['workspaceId'],
          referenceTable: 'nest_workspace',
          referenceTableSchema: 'public',
          referenceColumns: ['id'],
          onUpdate: _isp.ForeignKeyAction.noAction,
          onDelete: _isp.ForeignKeyAction.noAction,
          matchType: null,
        ),
        _isp.ForeignKeyDefinition(
          constraintName: 'nest_draft_fk_2',
          columns: ['baseVersionId'],
          referenceTable: 'nest_version',
          referenceTableSchema: 'public',
          referenceColumns: ['id'],
          onUpdate: _isp.ForeignKeyAction.noAction,
          onDelete: _isp.ForeignKeyAction.noAction,
          matchType: null,
        ),
        _isp.ForeignKeyDefinition(
          constraintName: 'nest_draft_fk_3',
          columns: ['activeJobId'],
          referenceTable: 'nest_generation',
          referenceTableSchema: 'public',
          referenceColumns: ['id'],
          onUpdate: _isp.ForeignKeyAction.noAction,
          onDelete: _isp.ForeignKeyAction.noAction,
          matchType: null,
        ),
        _isp.ForeignKeyDefinition(
          constraintName: 'nest_draft_fk_4',
          columns: ['publishedVersionId'],
          referenceTable: 'nest_version',
          referenceTableSchema: 'public',
          referenceColumns: ['id'],
          onUpdate: _isp.ForeignKeyAction.noAction,
          onDelete: _isp.ForeignKeyAction.noAction,
          matchType: null,
        ),
      ],
      indexes: [],
      managed: true,
    ),
    _isp.TableDefinition(
      name: 'nest_field_value',
      dartName: 'FieldValue',
      schema: 'public',
      module: 'appnest',
      columns: [
        _isp.ColumnDefinition(
          name: 'id',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int?',
          columnDefault: 'serial',
        ),
        _isp.ColumnDefinition(
          name: 'recordId',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
        ),
        _isp.ColumnDefinition(
          name: 'appId',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
        ),
        _isp.ColumnDefinition(
          name: 'collectionId',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'fieldId',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'textValue',
          columnType: _isp.ColumnType.text,
          isNullable: true,
          dartType: 'String?',
        ),
        _isp.ColumnDefinition(
          name: 'numberValue',
          columnType: _isp.ColumnType.doublePrecision,
          isNullable: true,
          dartType: 'double?',
        ),
        _isp.ColumnDefinition(
          name: 'boolValue',
          columnType: _isp.ColumnType.boolean,
          isNullable: true,
          dartType: 'bool?',
        ),
        _isp.ColumnDefinition(
          name: 'timestampValue',
          columnType: _isp.ColumnType.timestampWithoutTimeZone,
          isNullable: true,
          dartType: 'DateTime?',
        ),
      ],
      foreignKeys: [
        _isp.ForeignKeyDefinition(
          constraintName: 'nest_field_value_fk_0',
          columns: ['recordId'],
          referenceTable: 'nest_record',
          referenceTableSchema: 'public',
          referenceColumns: ['id'],
          onUpdate: _isp.ForeignKeyAction.noAction,
          onDelete: _isp.ForeignKeyAction.noAction,
          matchType: null,
        ),
        _isp.ForeignKeyDefinition(
          constraintName: 'nest_field_value_fk_1',
          columns: ['appId'],
          referenceTable: 'nest_app',
          referenceTableSchema: 'public',
          referenceColumns: ['id'],
          onUpdate: _isp.ForeignKeyAction.noAction,
          onDelete: _isp.ForeignKeyAction.noAction,
          matchType: null,
        ),
      ],
      indexes: [
        _isp.IndexDefinition(
          indexName: 'record_field',
          tableSpace: null,
          elements: [
            _isp.IndexElementDefinition(
              type: _isp.IndexElementDefinitionType.column,
              definition: 'recordId',
            ),
            _isp.IndexElementDefinition(
              type: _isp.IndexElementDefinitionType.column,
              definition: 'fieldId',
            ),
          ],
          type: 'btree',
          isUnique: true,
          isPrimary: false,
        ),
        _isp.IndexDefinition(
          indexName: 'query_field',
          tableSpace: null,
          elements: [
            _isp.IndexElementDefinition(
              type: _isp.IndexElementDefinitionType.column,
              definition: 'appId',
            ),
            _isp.IndexElementDefinition(
              type: _isp.IndexElementDefinitionType.column,
              definition: 'collectionId',
            ),
            _isp.IndexElementDefinition(
              type: _isp.IndexElementDefinitionType.column,
              definition: 'fieldId',
            ),
          ],
          type: 'btree',
          isUnique: false,
          isPrimary: false,
        ),
      ],
      managed: true,
    ),
    _isp.TableDefinition(
      name: 'nest_generation',
      dartName: 'GenerationJob',
      schema: 'public',
      module: 'appnest',
      columns: [
        _isp.ColumnDefinition(
          name: 'id',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int?',
          columnDefault: 'serial',
        ),
        _isp.ColumnDefinition(
          name: 'appId',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
        ),
        _isp.ColumnDefinition(
          name: 'draftId',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
        ),
        _isp.ColumnDefinition(
          name: 'actorId',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'mutation',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
        ),
        _isp.ColumnDefinition(
          name: 'status',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'requestText',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'mode',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'provider',
          columnType: _isp.ColumnType.text,
          isNullable: true,
          dartType: 'String?',
        ),
        _isp.ColumnDefinition(
          name: 'model',
          columnType: _isp.ColumnType.text,
          isNullable: true,
          dartType: 'String?',
        ),
        _isp.ColumnDefinition(
          name: 'promptVersion',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'attempts',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
          columnDefault: '0',
        ),
        _isp.ColumnDefinition(
          name: 'leaseGeneration',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
          columnDefault: '0',
        ),
        _isp.ColumnDefinition(
          name: 'leaseUntil',
          columnType: _isp.ColumnType.timestampWithoutTimeZone,
          isNullable: true,
          dartType: 'DateTime?',
        ),
        _isp.ColumnDefinition(
          name: 'nextAttemptAt',
          columnType: _isp.ColumnType.timestampWithoutTimeZone,
          isNullable: false,
          dartType: 'DateTime',
        ),
        _isp.ColumnDefinition(
          name: 'diagnostics',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'usageJson',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'createdAt',
          columnType: _isp.ColumnType.timestampWithoutTimeZone,
          isNullable: false,
          dartType: 'DateTime',
        ),
        _isp.ColumnDefinition(
          name: 'updatedAt',
          columnType: _isp.ColumnType.timestampWithoutTimeZone,
          isNullable: false,
          dartType: 'DateTime',
        ),
      ],
      foreignKeys: [
        _isp.ForeignKeyDefinition(
          constraintName: 'nest_generation_fk_0',
          columns: ['appId'],
          referenceTable: 'nest_app',
          referenceTableSchema: 'public',
          referenceColumns: ['id'],
          onUpdate: _isp.ForeignKeyAction.noAction,
          onDelete: _isp.ForeignKeyAction.noAction,
          matchType: null,
        ),
        _isp.ForeignKeyDefinition(
          constraintName: 'nest_generation_fk_1',
          columns: ['draftId'],
          referenceTable: 'nest_draft',
          referenceTableSchema: 'public',
          referenceColumns: ['id'],
          onUpdate: _isp.ForeignKeyAction.noAction,
          onDelete: _isp.ForeignKeyAction.noAction,
          matchType: null,
        ),
      ],
      indexes: [],
      managed: true,
    ),
    _isp.TableDefinition(
      name: 'nest_grant',
      dartName: 'MiniAppGrant',
      schema: 'public',
      module: 'appnest',
      columns: [
        _isp.ColumnDefinition(
          name: 'id',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int?',
          columnDefault: 'serial',
        ),
        _isp.ColumnDefinition(
          name: 'appId',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
        ),
        _isp.ColumnDefinition(
          name: 'workspaceId',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
        ),
        _isp.ColumnDefinition(
          name: 'actorId',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'role',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'revoked',
          columnType: _isp.ColumnType.boolean,
          isNullable: false,
          dartType: 'bool',
          columnDefault: 'false',
        ),
      ],
      foreignKeys: [
        _isp.ForeignKeyDefinition(
          constraintName: 'nest_grant_fk_0',
          columns: ['appId'],
          referenceTable: 'nest_app',
          referenceTableSchema: 'public',
          referenceColumns: ['id'],
          onUpdate: _isp.ForeignKeyAction.noAction,
          onDelete: _isp.ForeignKeyAction.noAction,
          matchType: null,
        ),
        _isp.ForeignKeyDefinition(
          constraintName: 'nest_grant_fk_1',
          columns: ['workspaceId'],
          referenceTable: 'nest_workspace',
          referenceTableSchema: 'public',
          referenceColumns: ['id'],
          onUpdate: _isp.ForeignKeyAction.noAction,
          onDelete: _isp.ForeignKeyAction.noAction,
          matchType: null,
        ),
      ],
      indexes: [
        _isp.IndexDefinition(
          indexName: 'grant_unique',
          tableSpace: null,
          elements: [
            _isp.IndexElementDefinition(
              type: _isp.IndexElementDefinitionType.column,
              definition: 'appId',
            ),
            _isp.IndexElementDefinition(
              type: _isp.IndexElementDefinitionType.column,
              definition: 'actorId',
            ),
          ],
          type: 'btree',
          isUnique: true,
          isPrimary: false,
        ),
      ],
      managed: true,
    ),
    _isp.TableDefinition(
      name: 'nest_guidance_request',
      dartName: 'GuidanceRequest',
      schema: 'public',
      module: 'appnest',
      columns: [
        _isp.ColumnDefinition(
          name: 'id',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int?',
          columnDefault: 'serial',
        ),
        _isp.ColumnDefinition(
          name: 'actorId',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'createdAt',
          columnType: _isp.ColumnType.timestampWithoutTimeZone,
          isNullable: false,
          dartType: 'DateTime',
        ),
      ],
      foreignKeys: [],
      indexes: [
        _isp.IndexDefinition(
          indexName: 'guidance_actor_created',
          tableSpace: null,
          elements: [
            _isp.IndexElementDefinition(
              type: _isp.IndexElementDefinitionType.column,
              definition: 'actorId',
            ),
            _isp.IndexElementDefinition(
              type: _isp.IndexElementDefinitionType.column,
              definition: 'createdAt',
            ),
          ],
          type: 'btree',
          isUnique: false,
          isPrimary: false,
        ),
      ],
      managed: true,
    ),
    _isp.TableDefinition(
      name: 'nest_invitation',
      dartName: 'Invitation',
      schema: 'public',
      module: 'appnest',
      columns: [
        _isp.ColumnDefinition(
          name: 'id',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int?',
          columnDefault: 'serial',
        ),
        _isp.ColumnDefinition(
          name: 'appId',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
        ),
        _isp.ColumnDefinition(
          name: 'workspaceId',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
        ),
        _isp.ColumnDefinition(
          name: 'issuerId',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'tokenHash',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'role',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'recipientId',
          columnType: _isp.ColumnType.text,
          isNullable: true,
          dartType: 'String?',
        ),
        _isp.ColumnDefinition(
          name: 'expiresAt',
          columnType: _isp.ColumnType.timestampWithoutTimeZone,
          isNullable: false,
          dartType: 'DateTime',
        ),
        _isp.ColumnDefinition(
          name: 'revoked',
          columnType: _isp.ColumnType.boolean,
          isNullable: false,
          dartType: 'bool',
          columnDefault: 'false',
        ),
        _isp.ColumnDefinition(
          name: 'acceptedBy',
          columnType: _isp.ColumnType.text,
          isNullable: true,
          dartType: 'String?',
        ),
        _isp.ColumnDefinition(
          name: 'createdAt',
          columnType: _isp.ColumnType.timestampWithoutTimeZone,
          isNullable: false,
          dartType: 'DateTime',
        ),
      ],
      foreignKeys: [
        _isp.ForeignKeyDefinition(
          constraintName: 'nest_invitation_fk_0',
          columns: ['appId'],
          referenceTable: 'nest_app',
          referenceTableSchema: 'public',
          referenceColumns: ['id'],
          onUpdate: _isp.ForeignKeyAction.noAction,
          onDelete: _isp.ForeignKeyAction.noAction,
          matchType: null,
        ),
        _isp.ForeignKeyDefinition(
          constraintName: 'nest_invitation_fk_1',
          columns: ['workspaceId'],
          referenceTable: 'nest_workspace',
          referenceTableSchema: 'public',
          referenceColumns: ['id'],
          onUpdate: _isp.ForeignKeyAction.noAction,
          onDelete: _isp.ForeignKeyAction.noAction,
          matchType: null,
        ),
      ],
      indexes: [
        _isp.IndexDefinition(
          indexName: 'invitation_token',
          tableSpace: null,
          elements: [
            _isp.IndexElementDefinition(
              type: _isp.IndexElementDefinitionType.column,
              definition: 'tokenHash',
            ),
          ],
          type: 'btree',
          isUnique: true,
          isPrimary: false,
        ),
      ],
      managed: true,
    ),
    _isp.TableDefinition(
      name: 'nest_media_asset',
      dartName: 'MediaAsset',
      schema: 'public',
      module: 'appnest',
      columns: [
        _isp.ColumnDefinition(
          name: 'id',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int?',
          columnDefault: 'serial',
        ),
        _isp.ColumnDefinition(
          name: 'assetId',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'appId',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
        ),
        _isp.ColumnDefinition(
          name: 'workspaceId',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
        ),
        _isp.ColumnDefinition(
          name: 'uploaderId',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'idempotencyKey',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'requestHash',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'requestJson',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'uploadDescription',
          columnType: _isp.ColumnType.text,
          isNullable: true,
          dartType: 'String?',
        ),
        _isp.ColumnDefinition(
          name: 'status',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'contentType',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'byteLength',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
        ),
        _isp.ColumnDefinition(
          name: 'storedBytes',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
        ),
        _isp.ColumnDefinition(
          name: 'originalRemoved',
          columnType: _isp.ColumnType.boolean,
          isNullable: false,
          dartType: 'bool',
          columnDefault: 'false',
        ),
        _isp.ColumnDefinition(
          name: 'width',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
          columnDefault: '0',
        ),
        _isp.ColumnDefinition(
          name: 'height',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
          columnDefault: '0',
        ),
        _isp.ColumnDefinition(
          name: 'expiresAt',
          columnType: _isp.ColumnType.timestampWithoutTimeZone,
          isNullable: false,
          dartType: 'DateTime',
        ),
        _isp.ColumnDefinition(
          name: 'leaseUntil',
          columnType: _isp.ColumnType.timestampWithoutTimeZone,
          isNullable: true,
          dartType: 'DateTime?',
        ),
        _isp.ColumnDefinition(
          name: 'createdAt',
          columnType: _isp.ColumnType.timestampWithoutTimeZone,
          isNullable: false,
          dartType: 'DateTime',
        ),
        _isp.ColumnDefinition(
          name: 'updatedAt',
          columnType: _isp.ColumnType.timestampWithoutTimeZone,
          isNullable: false,
          dartType: 'DateTime',
        ),
      ],
      foreignKeys: [
        _isp.ForeignKeyDefinition(
          constraintName: 'nest_media_asset_fk_0',
          columns: ['appId'],
          referenceTable: 'nest_app',
          referenceTableSchema: 'public',
          referenceColumns: ['id'],
          onUpdate: _isp.ForeignKeyAction.noAction,
          onDelete: _isp.ForeignKeyAction.noAction,
          matchType: null,
        ),
        _isp.ForeignKeyDefinition(
          constraintName: 'nest_media_asset_fk_1',
          columns: ['workspaceId'],
          referenceTable: 'nest_workspace',
          referenceTableSchema: 'public',
          referenceColumns: ['id'],
          onUpdate: _isp.ForeignKeyAction.noAction,
          onDelete: _isp.ForeignKeyAction.noAction,
          matchType: null,
        ),
      ],
      indexes: [
        _isp.IndexDefinition(
          indexName: 'media_asset_identity',
          tableSpace: null,
          elements: [
            _isp.IndexElementDefinition(
              type: _isp.IndexElementDefinitionType.column,
              definition: 'assetId',
            ),
          ],
          type: 'btree',
          isUnique: true,
          isPrimary: false,
        ),
        _isp.IndexDefinition(
          indexName: 'media_upload_receipt',
          tableSpace: null,
          elements: [
            _isp.IndexElementDefinition(
              type: _isp.IndexElementDefinitionType.column,
              definition: 'appId',
            ),
            _isp.IndexElementDefinition(
              type: _isp.IndexElementDefinitionType.column,
              definition: 'uploaderId',
            ),
            _isp.IndexElementDefinition(
              type: _isp.IndexElementDefinitionType.column,
              definition: 'idempotencyKey',
            ),
          ],
          type: 'btree',
          isUnique: true,
          isPrimary: false,
        ),
        _isp.IndexDefinition(
          indexName: 'media_cleanup',
          tableSpace: null,
          elements: [
            _isp.IndexElementDefinition(
              type: _isp.IndexElementDefinitionType.column,
              definition: 'status',
            ),
            _isp.IndexElementDefinition(
              type: _isp.IndexElementDefinitionType.column,
              definition: 'updatedAt',
            ),
          ],
          type: 'btree',
          isUnique: false,
          isPrimary: false,
        ),
      ],
      managed: true,
    ),
    _isp.TableDefinition(
      name: 'nest_media_reference',
      dartName: 'MediaReference',
      schema: 'public',
      module: 'appnest',
      columns: [
        _isp.ColumnDefinition(
          name: 'id',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int?',
          columnDefault: 'serial',
        ),
        _isp.ColumnDefinition(
          name: 'appId',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
        ),
        _isp.ColumnDefinition(
          name: 'assetRowId',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
        ),
        _isp.ColumnDefinition(
          name: 'draftId',
          columnType: _isp.ColumnType.bigint,
          isNullable: true,
          dartType: 'int?',
        ),
        _isp.ColumnDefinition(
          name: 'versionId',
          columnType: _isp.ColumnType.bigint,
          isNullable: true,
          dartType: 'int?',
        ),
        _isp.ColumnDefinition(
          name: 'recordId',
          columnType: _isp.ColumnType.bigint,
          isNullable: true,
          dartType: 'int?',
        ),
      ],
      foreignKeys: [
        _isp.ForeignKeyDefinition(
          constraintName: 'nest_media_reference_fk_0',
          columns: ['appId'],
          referenceTable: 'nest_app',
          referenceTableSchema: 'public',
          referenceColumns: ['id'],
          onUpdate: _isp.ForeignKeyAction.noAction,
          onDelete: _isp.ForeignKeyAction.noAction,
          matchType: null,
        ),
        _isp.ForeignKeyDefinition(
          constraintName: 'nest_media_reference_fk_1',
          columns: ['assetRowId'],
          referenceTable: 'nest_media_asset',
          referenceTableSchema: 'public',
          referenceColumns: ['id'],
          onUpdate: _isp.ForeignKeyAction.noAction,
          onDelete: _isp.ForeignKeyAction.noAction,
          matchType: null,
        ),
        _isp.ForeignKeyDefinition(
          constraintName: 'nest_media_reference_fk_2',
          columns: ['draftId'],
          referenceTable: 'nest_draft',
          referenceTableSchema: 'public',
          referenceColumns: ['id'],
          onUpdate: _isp.ForeignKeyAction.noAction,
          onDelete: _isp.ForeignKeyAction.noAction,
          matchType: null,
        ),
        _isp.ForeignKeyDefinition(
          constraintName: 'nest_media_reference_fk_3',
          columns: ['versionId'],
          referenceTable: 'nest_version',
          referenceTableSchema: 'public',
          referenceColumns: ['id'],
          onUpdate: _isp.ForeignKeyAction.noAction,
          onDelete: _isp.ForeignKeyAction.noAction,
          matchType: null,
        ),
        _isp.ForeignKeyDefinition(
          constraintName: 'nest_media_reference_fk_4',
          columns: ['recordId'],
          referenceTable: 'nest_record',
          referenceTableSchema: 'public',
          referenceColumns: ['id'],
          onUpdate: _isp.ForeignKeyAction.noAction,
          onDelete: _isp.ForeignKeyAction.noAction,
          matchType: null,
        ),
      ],
      indexes: [
        _isp.IndexDefinition(
          indexName: 'media_reference_asset',
          tableSpace: null,
          elements: [
            _isp.IndexElementDefinition(
              type: _isp.IndexElementDefinitionType.column,
              definition: 'assetRowId',
            ),
          ],
          type: 'btree',
          isUnique: false,
          isPrimary: false,
        ),
        _isp.IndexDefinition(
          indexName: 'media_reference_draft',
          tableSpace: null,
          elements: [
            _isp.IndexElementDefinition(
              type: _isp.IndexElementDefinitionType.column,
              definition: 'draftId',
            ),
          ],
          type: 'btree',
          isUnique: false,
          isPrimary: false,
        ),
        _isp.IndexDefinition(
          indexName: 'media_reference_version',
          tableSpace: null,
          elements: [
            _isp.IndexElementDefinition(
              type: _isp.IndexElementDefinitionType.column,
              definition: 'versionId',
            ),
          ],
          type: 'btree',
          isUnique: false,
          isPrimary: false,
        ),
        _isp.IndexDefinition(
          indexName: 'media_reference_record',
          tableSpace: null,
          elements: [
            _isp.IndexElementDefinition(
              type: _isp.IndexElementDefinitionType.column,
              definition: 'recordId',
            ),
          ],
          type: 'btree',
          isUnique: false,
          isPrimary: false,
        ),
      ],
      managed: true,
    ),
    _isp.TableDefinition(
      name: 'nest_notification',
      dartName: 'Notification',
      schema: 'public',
      module: 'appnest',
      columns: [
        _isp.ColumnDefinition(
          name: 'id',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int?',
          columnDefault: 'serial',
        ),
        _isp.ColumnDefinition(
          name: 'appId',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
        ),
        _isp.ColumnDefinition(
          name: 'workspaceId',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
        ),
        _isp.ColumnDefinition(
          name: 'actorId',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'runId',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
        ),
        _isp.ColumnDefinition(
          name: 'deliveryKey',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'title',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'body',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'readAt',
          columnType: _isp.ColumnType.timestampWithoutTimeZone,
          isNullable: true,
          dartType: 'DateTime?',
        ),
        _isp.ColumnDefinition(
          name: 'createdAt',
          columnType: _isp.ColumnType.timestampWithoutTimeZone,
          isNullable: false,
          dartType: 'DateTime',
        ),
      ],
      foreignKeys: [
        _isp.ForeignKeyDefinition(
          constraintName: 'nest_notification_fk_0',
          columns: ['appId'],
          referenceTable: 'nest_app',
          referenceTableSchema: 'public',
          referenceColumns: ['id'],
          onUpdate: _isp.ForeignKeyAction.noAction,
          onDelete: _isp.ForeignKeyAction.noAction,
          matchType: null,
        ),
        _isp.ForeignKeyDefinition(
          constraintName: 'nest_notification_fk_1',
          columns: ['workspaceId'],
          referenceTable: 'nest_workspace',
          referenceTableSchema: 'public',
          referenceColumns: ['id'],
          onUpdate: _isp.ForeignKeyAction.noAction,
          onDelete: _isp.ForeignKeyAction.noAction,
          matchType: null,
        ),
        _isp.ForeignKeyDefinition(
          constraintName: 'nest_notification_fk_2',
          columns: ['runId'],
          referenceTable: 'nest_run',
          referenceTableSchema: 'public',
          referenceColumns: ['id'],
          onUpdate: _isp.ForeignKeyAction.noAction,
          onDelete: _isp.ForeignKeyAction.noAction,
          matchType: null,
        ),
      ],
      indexes: [
        _isp.IndexDefinition(
          indexName: 'delivery_unique',
          tableSpace: null,
          elements: [
            _isp.IndexElementDefinition(
              type: _isp.IndexElementDefinitionType.column,
              definition: 'deliveryKey',
            ),
          ],
          type: 'btree',
          isUnique: true,
          isPrimary: false,
        ),
        _isp.IndexDefinition(
          indexName: 'inbox_actor',
          tableSpace: null,
          elements: [
            _isp.IndexElementDefinition(
              type: _isp.IndexElementDefinitionType.column,
              definition: 'actorId',
            ),
            _isp.IndexElementDefinition(
              type: _isp.IndexElementDefinitionType.column,
              definition: 'createdAt',
            ),
          ],
          type: 'btree',
          isUnique: false,
          isPrimary: false,
        ),
      ],
      managed: true,
    ),
    _isp.TableDefinition(
      name: 'nest_outbox',
      dartName: 'OutboxEvent',
      schema: 'public',
      module: 'appnest',
      columns: [
        _isp.ColumnDefinition(
          name: 'id',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int?',
          columnDefault: 'serial',
        ),
        _isp.ColumnDefinition(
          name: 'appId',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
        ),
        _isp.ColumnDefinition(
          name: 'recordId',
          columnType: _isp.ColumnType.bigint,
          isNullable: true,
          dartType: 'int?',
        ),
        _isp.ColumnDefinition(
          name: 'kind',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'planned',
          columnType: _isp.ColumnType.boolean,
          isNullable: false,
          dartType: 'bool',
          columnDefault: 'false',
        ),
        _isp.ColumnDefinition(
          name: 'invalidated',
          columnType: _isp.ColumnType.boolean,
          isNullable: false,
          dartType: 'bool',
          columnDefault: 'false',
        ),
        _isp.ColumnDefinition(
          name: 'attempts',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
          columnDefault: '0',
        ),
        _isp.ColumnDefinition(
          name: 'nextAttemptAt',
          columnType: _isp.ColumnType.timestampWithoutTimeZone,
          isNullable: false,
          dartType: 'DateTime',
        ),
        _isp.ColumnDefinition(
          name: 'createdAt',
          columnType: _isp.ColumnType.timestampWithoutTimeZone,
          isNullable: false,
          dartType: 'DateTime',
        ),
      ],
      foreignKeys: [
        _isp.ForeignKeyDefinition(
          constraintName: 'nest_outbox_fk_0',
          columns: ['appId'],
          referenceTable: 'nest_app',
          referenceTableSchema: 'public',
          referenceColumns: ['id'],
          onUpdate: _isp.ForeignKeyAction.noAction,
          onDelete: _isp.ForeignKeyAction.noAction,
          matchType: null,
        ),
        _isp.ForeignKeyDefinition(
          constraintName: 'nest_outbox_fk_1',
          columns: ['recordId'],
          referenceTable: 'nest_record',
          referenceTableSchema: 'public',
          referenceColumns: ['id'],
          onUpdate: _isp.ForeignKeyAction.noAction,
          onDelete: _isp.ForeignKeyAction.noAction,
          matchType: null,
        ),
      ],
      indexes: [],
      managed: true,
    ),
    _isp.TableDefinition(
      name: 'nest_pool',
      dartName: 'ResourcePool',
      schema: 'public',
      module: 'appnest',
      columns: [
        _isp.ColumnDefinition(
          name: 'id',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int?',
          columnDefault: 'serial',
        ),
        _isp.ColumnDefinition(
          name: 'appId',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
        ),
        _isp.ColumnDefinition(
          name: 'workspaceId',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
        ),
        _isp.ColumnDefinition(
          name: 'recordId',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
        ),
        _isp.ColumnDefinition(
          name: 'behaviorId',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'capacity',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
        ),
        _isp.ColumnDefinition(
          name: 'allocated',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
          columnDefault: '0',
        ),
      ],
      foreignKeys: [
        _isp.ForeignKeyDefinition(
          constraintName: 'nest_pool_fk_0',
          columns: ['appId'],
          referenceTable: 'nest_app',
          referenceTableSchema: 'public',
          referenceColumns: ['id'],
          onUpdate: _isp.ForeignKeyAction.noAction,
          onDelete: _isp.ForeignKeyAction.noAction,
          matchType: null,
        ),
        _isp.ForeignKeyDefinition(
          constraintName: 'nest_pool_fk_1',
          columns: ['workspaceId'],
          referenceTable: 'nest_workspace',
          referenceTableSchema: 'public',
          referenceColumns: ['id'],
          onUpdate: _isp.ForeignKeyAction.noAction,
          onDelete: _isp.ForeignKeyAction.noAction,
          matchType: null,
        ),
        _isp.ForeignKeyDefinition(
          constraintName: 'nest_pool_fk_2',
          columns: ['recordId'],
          referenceTable: 'nest_record',
          referenceTableSchema: 'public',
          referenceColumns: ['id'],
          onUpdate: _isp.ForeignKeyAction.noAction,
          onDelete: _isp.ForeignKeyAction.noAction,
          matchType: null,
        ),
      ],
      indexes: [
        _isp.IndexDefinition(
          indexName: 'pool_unique',
          tableSpace: null,
          elements: [
            _isp.IndexElementDefinition(
              type: _isp.IndexElementDefinitionType.column,
              definition: 'appId',
            ),
            _isp.IndexElementDefinition(
              type: _isp.IndexElementDefinitionType.column,
              definition: 'recordId',
            ),
            _isp.IndexElementDefinition(
              type: _isp.IndexElementDefinitionType.column,
              definition: 'behaviorId',
            ),
          ],
          type: 'btree',
          isUnique: true,
          isPrimary: false,
        ),
      ],
      managed: true,
    ),
    _isp.TableDefinition(
      name: 'nest_receipt',
      dartName: 'ActionReceipt',
      schema: 'public',
      module: 'appnest',
      columns: [
        _isp.ColumnDefinition(
          name: 'id',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int?',
          columnDefault: 'serial',
        ),
        _isp.ColumnDefinition(
          name: 'appId',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
        ),
        _isp.ColumnDefinition(
          name: 'actorId',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'idempotencyKey',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'requestHash',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'outcomeJson',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'createdAt',
          columnType: _isp.ColumnType.timestampWithoutTimeZone,
          isNullable: false,
          dartType: 'DateTime',
        ),
      ],
      foreignKeys: [
        _isp.ForeignKeyDefinition(
          constraintName: 'nest_receipt_fk_0',
          columns: ['appId'],
          referenceTable: 'nest_app',
          referenceTableSchema: 'public',
          referenceColumns: ['id'],
          onUpdate: _isp.ForeignKeyAction.noAction,
          onDelete: _isp.ForeignKeyAction.noAction,
          matchType: null,
        ),
      ],
      indexes: [
        _isp.IndexDefinition(
          indexName: 'receipt_unique',
          tableSpace: null,
          elements: [
            _isp.IndexElementDefinition(
              type: _isp.IndexElementDefinitionType.column,
              definition: 'appId',
            ),
            _isp.IndexElementDefinition(
              type: _isp.IndexElementDefinitionType.column,
              definition: 'actorId',
            ),
            _isp.IndexElementDefinition(
              type: _isp.IndexElementDefinitionType.column,
              definition: 'idempotencyKey',
            ),
          ],
          type: 'btree',
          isUnique: true,
          isPrimary: false,
        ),
      ],
      managed: true,
    ),
    _isp.TableDefinition(
      name: 'nest_record',
      dartName: 'EntityRecord',
      schema: 'public',
      module: 'appnest',
      columns: [
        _isp.ColumnDefinition(
          name: 'id',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int?',
          columnDefault: 'serial',
        ),
        _isp.ColumnDefinition(
          name: 'appId',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
        ),
        _isp.ColumnDefinition(
          name: 'workspaceId',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
        ),
        _isp.ColumnDefinition(
          name: 'collectionId',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'data',
          columnType: _isp.ColumnType.jsonb,
          isNullable: false,
          dartType: 'dynamic',
        ),
        _isp.ColumnDefinition(
          name: 'creatorId',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'revision',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
        ),
        _isp.ColumnDefinition(
          name: 'writtenUnderVersionId',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
        ),
        _isp.ColumnDefinition(
          name: 'createdAt',
          columnType: _isp.ColumnType.timestampWithoutTimeZone,
          isNullable: false,
          dartType: 'DateTime',
        ),
        _isp.ColumnDefinition(
          name: 'updatedAt',
          columnType: _isp.ColumnType.timestampWithoutTimeZone,
          isNullable: false,
          dartType: 'DateTime',
        ),
        _isp.ColumnDefinition(
          name: 'deleted',
          columnType: _isp.ColumnType.boolean,
          isNullable: false,
          dartType: 'bool',
          columnDefault: 'false',
        ),
      ],
      foreignKeys: [
        _isp.ForeignKeyDefinition(
          constraintName: 'nest_record_fk_0',
          columns: ['appId'],
          referenceTable: 'nest_app',
          referenceTableSchema: 'public',
          referenceColumns: ['id'],
          onUpdate: _isp.ForeignKeyAction.noAction,
          onDelete: _isp.ForeignKeyAction.noAction,
          matchType: null,
        ),
        _isp.ForeignKeyDefinition(
          constraintName: 'nest_record_fk_1',
          columns: ['workspaceId'],
          referenceTable: 'nest_workspace',
          referenceTableSchema: 'public',
          referenceColumns: ['id'],
          onUpdate: _isp.ForeignKeyAction.noAction,
          onDelete: _isp.ForeignKeyAction.noAction,
          matchType: null,
        ),
        _isp.ForeignKeyDefinition(
          constraintName: 'nest_record_fk_2',
          columns: ['writtenUnderVersionId'],
          referenceTable: 'nest_version',
          referenceTableSchema: 'public',
          referenceColumns: ['id'],
          onUpdate: _isp.ForeignKeyAction.noAction,
          onDelete: _isp.ForeignKeyAction.noAction,
          matchType: null,
        ),
      ],
      indexes: [
        _isp.IndexDefinition(
          indexName: 'record_scope_time',
          tableSpace: null,
          elements: [
            _isp.IndexElementDefinition(
              type: _isp.IndexElementDefinitionType.column,
              definition: 'appId',
            ),
            _isp.IndexElementDefinition(
              type: _isp.IndexElementDefinitionType.column,
              definition: 'collectionId',
            ),
            _isp.IndexElementDefinition(
              type: _isp.IndexElementDefinitionType.column,
              definition: 'createdAt',
            ),
          ],
          type: 'btree',
          isUnique: false,
          isPrimary: false,
        ),
      ],
      managed: true,
    ),
    _isp.TableDefinition(
      name: 'nest_run',
      dartName: 'AutomationRun',
      schema: 'public',
      module: 'appnest',
      columns: [
        _isp.ColumnDefinition(
          name: 'id',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int?',
          columnDefault: 'serial',
        ),
        _isp.ColumnDefinition(
          name: 'appId',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
        ),
        _isp.ColumnDefinition(
          name: 'automationId',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
        ),
        _isp.ColumnDefinition(
          name: 'ruleVersion',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
          columnDefault: '1',
        ),
        _isp.ColumnDefinition(
          name: 'recordId',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
        ),
        _isp.ColumnDefinition(
          name: 'occurrenceKey',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'scheduleSignature',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'dueAt',
          columnType: _isp.ColumnType.timestampWithoutTimeZone,
          isNullable: false,
          dartType: 'DateTime',
        ),
        _isp.ColumnDefinition(
          name: 'nextAttemptAt',
          columnType: _isp.ColumnType.timestampWithoutTimeZone,
          isNullable: false,
          dartType: 'DateTime',
        ),
        _isp.ColumnDefinition(
          name: 'status',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'attempts',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
          columnDefault: '0',
        ),
        _isp.ColumnDefinition(
          name: 'leaseGeneration',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
          columnDefault: '0',
        ),
        _isp.ColumnDefinition(
          name: 'leaseUntil',
          columnType: _isp.ColumnType.timestampWithoutTimeZone,
          isNullable: true,
          dartType: 'DateTime?',
        ),
        _isp.ColumnDefinition(
          name: 'errorCategory',
          columnType: _isp.ColumnType.text,
          isNullable: true,
          dartType: 'String?',
        ),
        _isp.ColumnDefinition(
          name: 'createdAt',
          columnType: _isp.ColumnType.timestampWithoutTimeZone,
          isNullable: false,
          dartType: 'DateTime',
        ),
        _isp.ColumnDefinition(
          name: 'completedAt',
          columnType: _isp.ColumnType.timestampWithoutTimeZone,
          isNullable: true,
          dartType: 'DateTime?',
        ),
      ],
      foreignKeys: [
        _isp.ForeignKeyDefinition(
          constraintName: 'nest_run_fk_0',
          columns: ['appId'],
          referenceTable: 'nest_app',
          referenceTableSchema: 'public',
          referenceColumns: ['id'],
          onUpdate: _isp.ForeignKeyAction.noAction,
          onDelete: _isp.ForeignKeyAction.noAction,
          matchType: null,
        ),
        _isp.ForeignKeyDefinition(
          constraintName: 'nest_run_fk_1',
          columns: ['automationId'],
          referenceTable: 'nest_automation',
          referenceTableSchema: 'public',
          referenceColumns: ['id'],
          onUpdate: _isp.ForeignKeyAction.noAction,
          onDelete: _isp.ForeignKeyAction.noAction,
          matchType: null,
        ),
        _isp.ForeignKeyDefinition(
          constraintName: 'nest_run_fk_2',
          columns: ['recordId'],
          referenceTable: 'nest_record',
          referenceTableSchema: 'public',
          referenceColumns: ['id'],
          onUpdate: _isp.ForeignKeyAction.noAction,
          onDelete: _isp.ForeignKeyAction.noAction,
          matchType: null,
        ),
      ],
      indexes: [
        _isp.IndexDefinition(
          indexName: 'occurrence_unique',
          tableSpace: null,
          elements: [
            _isp.IndexElementDefinition(
              type: _isp.IndexElementDefinitionType.column,
              definition: 'occurrenceKey',
            ),
          ],
          type: 'btree',
          isUnique: true,
          isPrimary: false,
        ),
        _isp.IndexDefinition(
          indexName: 'run_due',
          tableSpace: null,
          elements: [
            _isp.IndexElementDefinition(
              type: _isp.IndexElementDefinitionType.column,
              definition: 'status',
            ),
            _isp.IndexElementDefinition(
              type: _isp.IndexElementDefinitionType.column,
              definition: 'nextAttemptAt',
            ),
          ],
          type: 'btree',
          isUnique: false,
          isPrimary: false,
        ),
      ],
      managed: true,
    ),
    _isp.TableDefinition(
      name: 'nest_shortcut',
      dartName: 'AppShortcut',
      schema: 'public',
      module: 'appnest',
      columns: [
        _isp.ColumnDefinition(
          name: 'id',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int?',
          columnDefault: 'serial',
        ),
        _isp.ColumnDefinition(
          name: 'appId',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
        ),
        _isp.ColumnDefinition(
          name: 'actorId',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
      ],
      foreignKeys: [
        _isp.ForeignKeyDefinition(
          constraintName: 'nest_shortcut_fk_0',
          columns: ['appId'],
          referenceTable: 'nest_app',
          referenceTableSchema: 'public',
          referenceColumns: ['id'],
          onUpdate: _isp.ForeignKeyAction.noAction,
          onDelete: _isp.ForeignKeyAction.noAction,
          matchType: null,
        ),
      ],
      indexes: [
        _isp.IndexDefinition(
          indexName: 'shortcut_unique',
          tableSpace: null,
          elements: [
            _isp.IndexElementDefinition(
              type: _isp.IndexElementDefinitionType.column,
              definition: 'appId',
            ),
            _isp.IndexElementDefinition(
              type: _isp.IndexElementDefinitionType.column,
              definition: 'actorId',
            ),
          ],
          type: 'btree',
          isUnique: true,
          isPrimary: false,
        ),
      ],
      managed: true,
    ),
    _isp.TableDefinition(
      name: 'nest_template',
      dartName: 'Template',
      schema: 'public',
      module: 'appnest',
      columns: [
        _isp.ColumnDefinition(
          name: 'id',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int?',
          columnDefault: 'serial',
        ),
        _isp.ColumnDefinition(
          name: 'key',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'specJson',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'description',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
      ],
      foreignKeys: [],
      indexes: [
        _isp.IndexDefinition(
          indexName: 'template_key',
          tableSpace: null,
          elements: [
            _isp.IndexElementDefinition(
              type: _isp.IndexElementDefinitionType.column,
              definition: 'key',
            ),
          ],
          type: 'btree',
          isUnique: true,
          isPrimary: false,
        ),
      ],
      managed: true,
    ),
    _isp.TableDefinition(
      name: 'nest_version',
      dartName: 'AppVersion',
      schema: 'public',
      module: 'appnest',
      columns: [
        _isp.ColumnDefinition(
          name: 'id',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int?',
          columnDefault: 'serial',
        ),
        _isp.ColumnDefinition(
          name: 'appId',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
        ),
        _isp.ColumnDefinition(
          name: 'workspaceId',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
        ),
        _isp.ColumnDefinition(
          name: 'number',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
        ),
        _isp.ColumnDefinition(
          name: 'specJson',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'candidateHash',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'publisherId',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'createdAt',
          columnType: _isp.ColumnType.timestampWithoutTimeZone,
          isNullable: false,
          dartType: 'DateTime',
        ),
      ],
      foreignKeys: [
        _isp.ForeignKeyDefinition(
          constraintName: 'nest_version_fk_0',
          columns: ['appId'],
          referenceTable: 'nest_app',
          referenceTableSchema: 'public',
          referenceColumns: ['id'],
          onUpdate: _isp.ForeignKeyAction.noAction,
          onDelete: _isp.ForeignKeyAction.noAction,
          matchType: null,
        ),
        _isp.ForeignKeyDefinition(
          constraintName: 'nest_version_fk_1',
          columns: ['workspaceId'],
          referenceTable: 'nest_workspace',
          referenceTableSchema: 'public',
          referenceColumns: ['id'],
          onUpdate: _isp.ForeignKeyAction.noAction,
          onDelete: _isp.ForeignKeyAction.noAction,
          matchType: null,
        ),
      ],
      indexes: [
        _isp.IndexDefinition(
          indexName: 'version_unique',
          tableSpace: null,
          elements: [
            _isp.IndexElementDefinition(
              type: _isp.IndexElementDefinitionType.column,
              definition: 'appId',
            ),
            _isp.IndexElementDefinition(
              type: _isp.IndexElementDefinitionType.column,
              definition: 'number',
            ),
          ],
          type: 'btree',
          isUnique: true,
          isPrimary: false,
        ),
      ],
      managed: true,
    ),
    _isp.TableDefinition(
      name: 'nest_workspace',
      dartName: 'Workspace',
      schema: 'public',
      module: 'appnest',
      columns: [
        _isp.ColumnDefinition(
          name: 'id',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int?',
          columnDefault: 'serial',
        ),
        _isp.ColumnDefinition(
          name: 'name',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'ownerId',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'personal',
          columnType: _isp.ColumnType.boolean,
          isNullable: false,
          dartType: 'bool',
          columnDefault: 'false',
        ),
        _isp.ColumnDefinition(
          name: 'createdAt',
          columnType: _isp.ColumnType.timestampWithoutTimeZone,
          isNullable: false,
          dartType: 'DateTime',
        ),
      ],
      foreignKeys: [],
      indexes: [],
      managed: true,
    ),
    _isp.TableDefinition(
      name: 'nest_workspace_member',
      dartName: 'WorkspaceMember',
      schema: 'public',
      module: 'appnest',
      columns: [
        _isp.ColumnDefinition(
          name: 'id',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int?',
          columnDefault: 'serial',
        ),
        _isp.ColumnDefinition(
          name: 'workspaceId',
          columnType: _isp.ColumnType.bigint,
          isNullable: false,
          dartType: 'int',
        ),
        _isp.ColumnDefinition(
          name: 'actorId',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
        _isp.ColumnDefinition(
          name: 'role',
          columnType: _isp.ColumnType.text,
          isNullable: false,
          dartType: 'String',
        ),
      ],
      foreignKeys: [
        _isp.ForeignKeyDefinition(
          constraintName: 'nest_workspace_member_fk_0',
          columns: ['workspaceId'],
          referenceTable: 'nest_workspace',
          referenceTableSchema: 'public',
          referenceColumns: ['id'],
          onUpdate: _isp.ForeignKeyAction.noAction,
          onDelete: _isp.ForeignKeyAction.noAction,
          matchType: null,
        ),
      ],
      indexes: [
        _isp.IndexDefinition(
          indexName: 'membership_unique',
          tableSpace: null,
          elements: [
            _isp.IndexElementDefinition(
              type: _isp.IndexElementDefinitionType.column,
              definition: 'workspaceId',
            ),
            _isp.IndexElementDefinition(
              type: _isp.IndexElementDefinitionType.column,
              definition: 'actorId',
            ),
          ],
          type: 'btree',
          isUnique: true,
          isPrimary: false,
        ),
      ],
      managed: true,
    ),
    ..._iais.Protocol.targetTableDefinitions,
    ..._iacs.Protocol.targetTableDefinitions,
    ..._isp.Protocol.targetTableDefinitions,
  ];

  static String? getClassNameFromObjectJson(dynamic data) {
    if (data is! Map) return null;
    final className = data['__className__'] as String?;
    return className;
  }

  @override
  T deserialize<T>(
    dynamic data, [
    Type? t,
  ]) {
    t ??= T;

    final dataClassName = getClassNameFromObjectJson(data);
    if (dataClassName != null && dataClassName != getClassNameForType(t)) {
      try {
        return deserializeByClassName({
          'className': dataClassName,
          'data': data,
        });
      } on _is.DeserializationClassNameNotFoundException catch (_) {
        // If the className is not recognized (e.g., older client receiving
        // data with a new subtype), fall back to deserializing without the
        // className, using the expected type T.
      }
    }

    if (t == _isykbnbw.ActionOutcome) {
      return _isykbnbw.ActionOutcome.fromJson(data) as T;
    }
    if (t == _izkbb96g.ActionReceipt) {
      return _izkbb96g.ActionReceipt.fromJson(data) as T;
    }
    if (t == _ii1w3lxm.ActionRequest) {
      return _ii1w3lxm.ActionRequest.fromJson(data) as T;
    }
    if (t == _irh51hj1.ActivityItem) {
      return _irh51hj1.ActivityItem.fromJson(data) as T;
    }
    if (t == _iq0wu3gu.AppDraft) {
      return _iq0wu3gu.AppDraft.fromJson(data) as T;
    }
    if (t == _iwn9176r.AppEvent) {
      return _iwn9176r.AppEvent.fromJson(data) as T;
    }
    if (t == _i65w4jw3.AppManifest) {
      return _i65w4jw3.AppManifest.fromJson(data) as T;
    }
    if (t == _i1wu1dla.AppShortcut) {
      return _i1wu1dla.AppShortcut.fromJson(data) as T;
    }
    if (t == _izejoxi5.AppVersion) {
      return _izejoxi5.AppVersion.fromJson(data) as T;
    }
    if (t == _i1613bfs.AuditEntry) {
      return _i1613bfs.AuditEntry.fromJson(data) as T;
    }
    if (t == _ife4t62f.Automation) {
      return _ife4t62f.Automation.fromJson(data) as T;
    }
    if (t == _ixu7zng5.AutomationRun) {
      return _ixu7zng5.AutomationRun.fromJson(data) as T;
    }
    if (t == _i4n6ivgk.BuilderSnapshot) {
      return _i4n6ivgk.BuilderSnapshot.fromJson(data) as T;
    }
    if (t == _iywv5oz4.Claim) {
      return _iywv5oz4.Claim.fromJson(data) as T;
    }
    if (t == _iy0qwluf.EntityRecord) {
      return _iy0qwluf.EntityRecord.fromJson(data) as T;
    }
    if (t == _iyrqavho.FieldValue) {
      return _iyrqavho.FieldValue.fromJson(data) as T;
    }
    if (t == _i2npzse7.NestWorkerFutureCallExecuteModel) {
      return _i2npzse7.NestWorkerFutureCallExecuteModel.fromJson(data) as T;
    }
    if (t == _i7d9xtt1.NestWorkerFutureCallGenerateModel) {
      return _i7d9xtt1.NestWorkerFutureCallGenerateModel.fromJson(data) as T;
    }
    if (t == _ig17l95t.GenerationJob) {
      return _ig17l95t.GenerationJob.fromJson(data) as T;
    }
    if (t == _izw8z7ou.Greeting) {
      return _izw8z7ou.Greeting.fromJson(data) as T;
    }
    if (t == _istc82cm.GuidanceQuestion) {
      return _istc82cm.GuidanceQuestion.fromJson(data) as T;
    }
    if (t == _i3j1yq52.GuidanceRequest) {
      return _i3j1yq52.GuidanceRequest.fromJson(data) as T;
    }
    if (t == _iv6iq8qv.InboxItem) {
      return _iv6iq8qv.InboxItem.fromJson(data) as T;
    }
    if (t == _ix00wubs.Invitation) {
      return _ix00wubs.Invitation.fromJson(data) as T;
    }
    if (t == _ivzdqkik.MediaAsset) {
      return _ivzdqkik.MediaAsset.fromJson(data) as T;
    }
    if (t == _iyb2dgte.MediaInfo) {
      return _iyb2dgte.MediaInfo.fromJson(data) as T;
    }
    if (t == _il7l0uyh.MediaReference) {
      return _il7l0uyh.MediaReference.fromJson(data) as T;
    }
    if (t == _i6mex4av.MediaUploadRequest) {
      return _i6mex4av.MediaUploadRequest.fromJson(data) as T;
    }
    if (t == _iu821fma.MediaUploadTicket) {
      return _iu821fma.MediaUploadTicket.fromJson(data) as T;
    }
    if (t == _i2slp771.MemberInfo) {
      return _i2slp771.MemberInfo.fromJson(data) as T;
    }
    if (t == _ivniu53p.MiniApp) {
      return _ivniu53p.MiniApp.fromJson(data) as T;
    }
    if (t == _iurwb5gp.MiniAppGrant) {
      return _iurwb5gp.MiniAppGrant.fromJson(data) as T;
    }
    if (t == _i0tc2cek.NestError) {
      return _i0tc2cek.NestError.fromJson(data) as T;
    }
    if (t == _irt10kca.Notification) {
      return _irt10kca.Notification.fromJson(data) as T;
    }
    if (t == _i6i2iffh.OutboxEvent) {
      return _i6i2iffh.OutboxEvent.fromJson(data) as T;
    }
    if (t == _ici3to49.PlatformInfo) {
      return _ici3to49.PlatformInfo.fromJson(data) as T;
    }
    if (t == _iijemlr5.PublishRequest) {
      return _iijemlr5.PublishRequest.fromJson(data) as T;
    }
    if (t == _i4a9pphb.RecordPage) {
      return _i4a9pphb.RecordPage.fromJson(data) as T;
    }
    if (t == _ifx2sflx.RecordSummary) {
      return _ifx2sflx.RecordSummary.fromJson(data) as T;
    }
    if (t == _ipsxd53m.ReminderState) {
      return _ipsxd53m.ReminderState.fromJson(data) as T;
    }
    if (t == _i6hl3xhc.ResourcePool) {
      return _i6hl3xhc.ResourcePool.fromJson(data) as T;
    }
    if (t == _ilpx295a.RuntimeRecord) {
      return _ilpx295a.RuntimeRecord.fromJson(data) as T;
    }
    if (t == _ibutn46j.Template) {
      return _ibutn46j.Template.fromJson(data) as T;
    }
    if (t == _i1ykl0x7.TemplateInfo) {
      return _i1ykl0x7.TemplateInfo.fromJson(data) as T;
    }
    if (t == _io6eoug6.Workspace) {
      return _io6eoug6.Workspace.fromJson(data) as T;
    }
    if (t == _ixz9batj.WorkspaceInfo) {
      return _ixz9batj.WorkspaceInfo.fromJson(data) as T;
    }
    if (t == _iidcmvkk.WorkspaceMember) {
      return _iidcmvkk.WorkspaceMember.fromJson(data) as T;
    }
    if (t == _is.getType<_isykbnbw.ActionOutcome?>()) {
      return (data != null ? _isykbnbw.ActionOutcome.fromJson(data) : null)
          as T;
    }
    if (t == _is.getType<_izkbb96g.ActionReceipt?>()) {
      return (data != null ? _izkbb96g.ActionReceipt.fromJson(data) : null)
          as T;
    }
    if (t == _is.getType<_ii1w3lxm.ActionRequest?>()) {
      return (data != null ? _ii1w3lxm.ActionRequest.fromJson(data) : null)
          as T;
    }
    if (t == _is.getType<_irh51hj1.ActivityItem?>()) {
      return (data != null ? _irh51hj1.ActivityItem.fromJson(data) : null) as T;
    }
    if (t == _is.getType<_iq0wu3gu.AppDraft?>()) {
      return (data != null ? _iq0wu3gu.AppDraft.fromJson(data) : null) as T;
    }
    if (t == _is.getType<_iwn9176r.AppEvent?>()) {
      return (data != null ? _iwn9176r.AppEvent.fromJson(data) : null) as T;
    }
    if (t == _is.getType<_i65w4jw3.AppManifest?>()) {
      return (data != null ? _i65w4jw3.AppManifest.fromJson(data) : null) as T;
    }
    if (t == _is.getType<_i1wu1dla.AppShortcut?>()) {
      return (data != null ? _i1wu1dla.AppShortcut.fromJson(data) : null) as T;
    }
    if (t == _is.getType<_izejoxi5.AppVersion?>()) {
      return (data != null ? _izejoxi5.AppVersion.fromJson(data) : null) as T;
    }
    if (t == _is.getType<_i1613bfs.AuditEntry?>()) {
      return (data != null ? _i1613bfs.AuditEntry.fromJson(data) : null) as T;
    }
    if (t == _is.getType<_ife4t62f.Automation?>()) {
      return (data != null ? _ife4t62f.Automation.fromJson(data) : null) as T;
    }
    if (t == _is.getType<_ixu7zng5.AutomationRun?>()) {
      return (data != null ? _ixu7zng5.AutomationRun.fromJson(data) : null)
          as T;
    }
    if (t == _is.getType<_i4n6ivgk.BuilderSnapshot?>()) {
      return (data != null ? _i4n6ivgk.BuilderSnapshot.fromJson(data) : null)
          as T;
    }
    if (t == _is.getType<_iywv5oz4.Claim?>()) {
      return (data != null ? _iywv5oz4.Claim.fromJson(data) : null) as T;
    }
    if (t == _is.getType<_iy0qwluf.EntityRecord?>()) {
      return (data != null ? _iy0qwluf.EntityRecord.fromJson(data) : null) as T;
    }
    if (t == _is.getType<_iyrqavho.FieldValue?>()) {
      return (data != null ? _iyrqavho.FieldValue.fromJson(data) : null) as T;
    }
    if (t == _is.getType<_i2npzse7.NestWorkerFutureCallExecuteModel?>()) {
      return (data != null
              ? _i2npzse7.NestWorkerFutureCallExecuteModel.fromJson(data)
              : null)
          as T;
    }
    if (t == _is.getType<_i7d9xtt1.NestWorkerFutureCallGenerateModel?>()) {
      return (data != null
              ? _i7d9xtt1.NestWorkerFutureCallGenerateModel.fromJson(data)
              : null)
          as T;
    }
    if (t == _is.getType<_ig17l95t.GenerationJob?>()) {
      return (data != null ? _ig17l95t.GenerationJob.fromJson(data) : null)
          as T;
    }
    if (t == _is.getType<_izw8z7ou.Greeting?>()) {
      return (data != null ? _izw8z7ou.Greeting.fromJson(data) : null) as T;
    }
    if (t == _is.getType<_istc82cm.GuidanceQuestion?>()) {
      return (data != null ? _istc82cm.GuidanceQuestion.fromJson(data) : null)
          as T;
    }
    if (t == _is.getType<_i3j1yq52.GuidanceRequest?>()) {
      return (data != null ? _i3j1yq52.GuidanceRequest.fromJson(data) : null)
          as T;
    }
    if (t == _is.getType<_iv6iq8qv.InboxItem?>()) {
      return (data != null ? _iv6iq8qv.InboxItem.fromJson(data) : null) as T;
    }
    if (t == _is.getType<_ix00wubs.Invitation?>()) {
      return (data != null ? _ix00wubs.Invitation.fromJson(data) : null) as T;
    }
    if (t == _is.getType<_ivzdqkik.MediaAsset?>()) {
      return (data != null ? _ivzdqkik.MediaAsset.fromJson(data) : null) as T;
    }
    if (t == _is.getType<_iyb2dgte.MediaInfo?>()) {
      return (data != null ? _iyb2dgte.MediaInfo.fromJson(data) : null) as T;
    }
    if (t == _is.getType<_il7l0uyh.MediaReference?>()) {
      return (data != null ? _il7l0uyh.MediaReference.fromJson(data) : null)
          as T;
    }
    if (t == _is.getType<_i6mex4av.MediaUploadRequest?>()) {
      return (data != null ? _i6mex4av.MediaUploadRequest.fromJson(data) : null)
          as T;
    }
    if (t == _is.getType<_iu821fma.MediaUploadTicket?>()) {
      return (data != null ? _iu821fma.MediaUploadTicket.fromJson(data) : null)
          as T;
    }
    if (t == _is.getType<_i2slp771.MemberInfo?>()) {
      return (data != null ? _i2slp771.MemberInfo.fromJson(data) : null) as T;
    }
    if (t == _is.getType<_ivniu53p.MiniApp?>()) {
      return (data != null ? _ivniu53p.MiniApp.fromJson(data) : null) as T;
    }
    if (t == _is.getType<_iurwb5gp.MiniAppGrant?>()) {
      return (data != null ? _iurwb5gp.MiniAppGrant.fromJson(data) : null) as T;
    }
    if (t == _is.getType<_i0tc2cek.NestError?>()) {
      return (data != null ? _i0tc2cek.NestError.fromJson(data) : null) as T;
    }
    if (t == _is.getType<_irt10kca.Notification?>()) {
      return (data != null ? _irt10kca.Notification.fromJson(data) : null) as T;
    }
    if (t == _is.getType<_i6i2iffh.OutboxEvent?>()) {
      return (data != null ? _i6i2iffh.OutboxEvent.fromJson(data) : null) as T;
    }
    if (t == _is.getType<_ici3to49.PlatformInfo?>()) {
      return (data != null ? _ici3to49.PlatformInfo.fromJson(data) : null) as T;
    }
    if (t == _is.getType<_iijemlr5.PublishRequest?>()) {
      return (data != null ? _iijemlr5.PublishRequest.fromJson(data) : null)
          as T;
    }
    if (t == _is.getType<_i4a9pphb.RecordPage?>()) {
      return (data != null ? _i4a9pphb.RecordPage.fromJson(data) : null) as T;
    }
    if (t == _is.getType<_ifx2sflx.RecordSummary?>()) {
      return (data != null ? _ifx2sflx.RecordSummary.fromJson(data) : null)
          as T;
    }
    if (t == _is.getType<_ipsxd53m.ReminderState?>()) {
      return (data != null ? _ipsxd53m.ReminderState.fromJson(data) : null)
          as T;
    }
    if (t == _is.getType<_i6hl3xhc.ResourcePool?>()) {
      return (data != null ? _i6hl3xhc.ResourcePool.fromJson(data) : null) as T;
    }
    if (t == _is.getType<_ilpx295a.RuntimeRecord?>()) {
      return (data != null ? _ilpx295a.RuntimeRecord.fromJson(data) : null)
          as T;
    }
    if (t == _is.getType<_ibutn46j.Template?>()) {
      return (data != null ? _ibutn46j.Template.fromJson(data) : null) as T;
    }
    if (t == _is.getType<_i1ykl0x7.TemplateInfo?>()) {
      return (data != null ? _i1ykl0x7.TemplateInfo.fromJson(data) : null) as T;
    }
    if (t == _is.getType<_io6eoug6.Workspace?>()) {
      return (data != null ? _io6eoug6.Workspace.fromJson(data) : null) as T;
    }
    if (t == _is.getType<_ixz9batj.WorkspaceInfo?>()) {
      return (data != null ? _ixz9batj.WorkspaceInfo.fromJson(data) : null)
          as T;
    }
    if (t == _is.getType<_iidcmvkk.WorkspaceMember?>()) {
      return (data != null ? _iidcmvkk.WorkspaceMember.fromJson(data) : null)
          as T;
    }
    if (t == dynamic) {
      return deserializeDynamicFieldValue(data) as T;
    }
    if (t == List<String>) {
      return (data as List).map((e) => deserialize<String>(e)).toList() as T;
    }
    if (t == _is.getType<List<String>?>()) {
      return (data != null
              ? (data as List).map((e) => deserialize<String>(e)).toList()
              : null)
          as T;
    }
    if (t == List<int>) {
      return (data as List).map((e) => deserialize<int>(e)).toList() as T;
    }
    if (t == List<_ilpx295a.RuntimeRecord>) {
      return (data as List)
              .map((e) => deserialize<_ilpx295a.RuntimeRecord>(e))
              .toList()
          as T;
    }
    if (t == Map<String, int>) {
      return (data as Map).map(
            (k, v) => MapEntry(deserialize<String>(k), deserialize<int>(v)),
          )
          as T;
    }
    if (t == List<_i829frra.WorkspaceInfo>) {
      return (data as List)
              .map((e) => deserialize<_i829frra.WorkspaceInfo>(e))
              .toList()
          as T;
    }
    if (t == List<_i5x0vch8.AppManifest>) {
      return (data as List)
              .map((e) => deserialize<_i5x0vch8.AppManifest>(e))
              .toList()
          as T;
    }
    if (t == List<_iacdzrq5.TemplateInfo>) {
      return (data as List)
              .map((e) => deserialize<_iacdzrq5.TemplateInfo>(e))
              .toList()
          as T;
    }
    if (t == List<_ii9ccrrn.MemberInfo>) {
      return (data as List)
              .map((e) => deserialize<_ii9ccrrn.MemberInfo>(e))
              .toList()
          as T;
    }
    if (t == List<_irfbx1ex.ActivityItem>) {
      return (data as List)
              .map((e) => deserialize<_irfbx1ex.ActivityItem>(e))
              .toList()
          as T;
    }
    if (t == List<_i42yij2w.GuidanceQuestion>) {
      return (data as List)
              .map((e) => deserialize<_i42yij2w.GuidanceQuestion>(e))
              .toList()
          as T;
    }
    if (t == List<_ihdyt6mq.ReminderState>) {
      return (data as List)
              .map((e) => deserialize<_ihdyt6mq.ReminderState>(e))
              .toList()
          as T;
    }
    if (t == List<_iofnszjt.InboxItem>) {
      return (data as List)
              .map((e) => deserialize<_iofnszjt.InboxItem>(e))
              .toList()
          as T;
    }
    try {
      return _iais.Protocol().deserialize<T>(data, t);
    } on _is.DeserializationTypeNotFoundException catch (_) {}
    try {
      return _iacs.Protocol().deserialize<T>(data, t);
    } on _is.DeserializationTypeNotFoundException catch (_) {}
    try {
      return _isp.Protocol().deserialize<T>(data, t);
    } on _is.DeserializationTypeNotFoundException catch (_) {}
    return super.deserialize<T>(data, t);
  }

  static String? getClassNameForType(Type type) {
    return switch (type) {
      _isykbnbw.ActionOutcome => 'ActionOutcome',
      _izkbb96g.ActionReceipt => 'ActionReceipt',
      _ii1w3lxm.ActionRequest => 'ActionRequest',
      _irh51hj1.ActivityItem => 'ActivityItem',
      _iq0wu3gu.AppDraft => 'AppDraft',
      _iwn9176r.AppEvent => 'AppEvent',
      _i65w4jw3.AppManifest => 'AppManifest',
      _i1wu1dla.AppShortcut => 'AppShortcut',
      _izejoxi5.AppVersion => 'AppVersion',
      _i1613bfs.AuditEntry => 'AuditEntry',
      _ife4t62f.Automation => 'Automation',
      _ixu7zng5.AutomationRun => 'AutomationRun',
      _i4n6ivgk.BuilderSnapshot => 'BuilderSnapshot',
      _iywv5oz4.Claim => 'Claim',
      _iy0qwluf.EntityRecord => 'EntityRecord',
      _iyrqavho.FieldValue => 'FieldValue',
      _i2npzse7.NestWorkerFutureCallExecuteModel =>
        'NestWorkerFutureCallExecuteModel',
      _i7d9xtt1.NestWorkerFutureCallGenerateModel =>
        'NestWorkerFutureCallGenerateModel',
      _ig17l95t.GenerationJob => 'GenerationJob',
      _izw8z7ou.Greeting => 'Greeting',
      _istc82cm.GuidanceQuestion => 'GuidanceQuestion',
      _i3j1yq52.GuidanceRequest => 'GuidanceRequest',
      _iv6iq8qv.InboxItem => 'InboxItem',
      _ix00wubs.Invitation => 'Invitation',
      _ivzdqkik.MediaAsset => 'MediaAsset',
      _iyb2dgte.MediaInfo => 'MediaInfo',
      _il7l0uyh.MediaReference => 'MediaReference',
      _i6mex4av.MediaUploadRequest => 'MediaUploadRequest',
      _iu821fma.MediaUploadTicket => 'MediaUploadTicket',
      _i2slp771.MemberInfo => 'MemberInfo',
      _ivniu53p.MiniApp => 'MiniApp',
      _iurwb5gp.MiniAppGrant => 'MiniAppGrant',
      _i0tc2cek.NestError => 'NestError',
      _irt10kca.Notification => 'Notification',
      _i6i2iffh.OutboxEvent => 'OutboxEvent',
      _ici3to49.PlatformInfo => 'PlatformInfo',
      _iijemlr5.PublishRequest => 'PublishRequest',
      _i4a9pphb.RecordPage => 'RecordPage',
      _ifx2sflx.RecordSummary => 'RecordSummary',
      _ipsxd53m.ReminderState => 'ReminderState',
      _i6hl3xhc.ResourcePool => 'ResourcePool',
      _ilpx295a.RuntimeRecord => 'RuntimeRecord',
      _ibutn46j.Template => 'Template',
      _i1ykl0x7.TemplateInfo => 'TemplateInfo',
      _io6eoug6.Workspace => 'Workspace',
      _ixz9batj.WorkspaceInfo => 'WorkspaceInfo',
      _iidcmvkk.WorkspaceMember => 'WorkspaceMember',
      _ => null,
    };
  }

  @override
  String? getClassNameForObject(Object? data) {
    String? className = super.getClassNameForObject(data);
    if (className != null) return className;

    if (data is Map<String, dynamic> && data['__className__'] is String) {
      return (data['__className__'] as String).replaceFirst('appnest.', '');
    }

    switch (data) {
      case _isykbnbw.ActionOutcome():
        return 'ActionOutcome';
      case _izkbb96g.ActionReceipt():
        return 'ActionReceipt';
      case _ii1w3lxm.ActionRequest():
        return 'ActionRequest';
      case _irh51hj1.ActivityItem():
        return 'ActivityItem';
      case _iq0wu3gu.AppDraft():
        return 'AppDraft';
      case _iwn9176r.AppEvent():
        return 'AppEvent';
      case _i65w4jw3.AppManifest():
        return 'AppManifest';
      case _i1wu1dla.AppShortcut():
        return 'AppShortcut';
      case _izejoxi5.AppVersion():
        return 'AppVersion';
      case _i1613bfs.AuditEntry():
        return 'AuditEntry';
      case _ife4t62f.Automation():
        return 'Automation';
      case _ixu7zng5.AutomationRun():
        return 'AutomationRun';
      case _i4n6ivgk.BuilderSnapshot():
        return 'BuilderSnapshot';
      case _iywv5oz4.Claim():
        return 'Claim';
      case _iy0qwluf.EntityRecord():
        return 'EntityRecord';
      case _iyrqavho.FieldValue():
        return 'FieldValue';
      case _i2npzse7.NestWorkerFutureCallExecuteModel():
        return 'NestWorkerFutureCallExecuteModel';
      case _i7d9xtt1.NestWorkerFutureCallGenerateModel():
        return 'NestWorkerFutureCallGenerateModel';
      case _ig17l95t.GenerationJob():
        return 'GenerationJob';
      case _izw8z7ou.Greeting():
        return 'Greeting';
      case _istc82cm.GuidanceQuestion():
        return 'GuidanceQuestion';
      case _i3j1yq52.GuidanceRequest():
        return 'GuidanceRequest';
      case _iv6iq8qv.InboxItem():
        return 'InboxItem';
      case _ix00wubs.Invitation():
        return 'Invitation';
      case _ivzdqkik.MediaAsset():
        return 'MediaAsset';
      case _iyb2dgte.MediaInfo():
        return 'MediaInfo';
      case _il7l0uyh.MediaReference():
        return 'MediaReference';
      case _i6mex4av.MediaUploadRequest():
        return 'MediaUploadRequest';
      case _iu821fma.MediaUploadTicket():
        return 'MediaUploadTicket';
      case _i2slp771.MemberInfo():
        return 'MemberInfo';
      case _ivniu53p.MiniApp():
        return 'MiniApp';
      case _iurwb5gp.MiniAppGrant():
        return 'MiniAppGrant';
      case _i0tc2cek.NestError():
        return 'NestError';
      case _irt10kca.Notification():
        return 'Notification';
      case _i6i2iffh.OutboxEvent():
        return 'OutboxEvent';
      case _ici3to49.PlatformInfo():
        return 'PlatformInfo';
      case _iijemlr5.PublishRequest():
        return 'PublishRequest';
      case _i4a9pphb.RecordPage():
        return 'RecordPage';
      case _ifx2sflx.RecordSummary():
        return 'RecordSummary';
      case _ipsxd53m.ReminderState():
        return 'ReminderState';
      case _i6hl3xhc.ResourcePool():
        return 'ResourcePool';
      case _ilpx295a.RuntimeRecord():
        return 'RuntimeRecord';
      case _ibutn46j.Template():
        return 'Template';
      case _i1ykl0x7.TemplateInfo():
        return 'TemplateInfo';
      case _io6eoug6.Workspace():
        return 'Workspace';
      case _ixz9batj.WorkspaceInfo():
        return 'WorkspaceInfo';
      case _iidcmvkk.WorkspaceMember():
        return 'WorkspaceMember';
    }
    className = _iais.Protocol().getClassNameForObject(data);
    if (className != null) {
      return className.contains('.')
          ? className
          : 'serverpod_auth_idp.$className';
    }
    className = _iacs.Protocol().getClassNameForObject(data);
    if (className != null) {
      return className.contains('.')
          ? className
          : 'serverpod_auth_core.$className';
    }
    className = _isp.Protocol().getClassNameForObject(data);
    if (className != null) {
      return className.contains('.') ? className : 'serverpod.$className';
    }
    return null;
  }

  @override
  dynamic deserializeByClassName(Map<String, dynamic> data) {
    var dataClassName = data['className'];
    if (dataClassName is! String) {
      return super.deserializeByClassName(data);
    }
    if (dataClassName == 'ActionOutcome') {
      return deserialize<_isykbnbw.ActionOutcome>(data['data']);
    }
    if (dataClassName == 'ActionReceipt') {
      return deserialize<_izkbb96g.ActionReceipt>(data['data']);
    }
    if (dataClassName == 'ActionRequest') {
      return deserialize<_ii1w3lxm.ActionRequest>(data['data']);
    }
    if (dataClassName == 'ActivityItem') {
      return deserialize<_irh51hj1.ActivityItem>(data['data']);
    }
    if (dataClassName == 'AppDraft') {
      return deserialize<_iq0wu3gu.AppDraft>(data['data']);
    }
    if (dataClassName == 'AppEvent') {
      return deserialize<_iwn9176r.AppEvent>(data['data']);
    }
    if (dataClassName == 'AppManifest') {
      return deserialize<_i65w4jw3.AppManifest>(data['data']);
    }
    if (dataClassName == 'AppShortcut') {
      return deserialize<_i1wu1dla.AppShortcut>(data['data']);
    }
    if (dataClassName == 'AppVersion') {
      return deserialize<_izejoxi5.AppVersion>(data['data']);
    }
    if (dataClassName == 'AuditEntry') {
      return deserialize<_i1613bfs.AuditEntry>(data['data']);
    }
    if (dataClassName == 'Automation') {
      return deserialize<_ife4t62f.Automation>(data['data']);
    }
    if (dataClassName == 'AutomationRun') {
      return deserialize<_ixu7zng5.AutomationRun>(data['data']);
    }
    if (dataClassName == 'BuilderSnapshot') {
      return deserialize<_i4n6ivgk.BuilderSnapshot>(data['data']);
    }
    if (dataClassName == 'Claim') {
      return deserialize<_iywv5oz4.Claim>(data['data']);
    }
    if (dataClassName == 'EntityRecord') {
      return deserialize<_iy0qwluf.EntityRecord>(data['data']);
    }
    if (dataClassName == 'FieldValue') {
      return deserialize<_iyrqavho.FieldValue>(data['data']);
    }
    if (dataClassName == 'NestWorkerFutureCallExecuteModel') {
      return deserialize<_i2npzse7.NestWorkerFutureCallExecuteModel>(
        data['data'],
      );
    }
    if (dataClassName == 'NestWorkerFutureCallGenerateModel') {
      return deserialize<_i7d9xtt1.NestWorkerFutureCallGenerateModel>(
        data['data'],
      );
    }
    if (dataClassName == 'GenerationJob') {
      return deserialize<_ig17l95t.GenerationJob>(data['data']);
    }
    if (dataClassName == 'Greeting') {
      return deserialize<_izw8z7ou.Greeting>(data['data']);
    }
    if (dataClassName == 'GuidanceQuestion') {
      return deserialize<_istc82cm.GuidanceQuestion>(data['data']);
    }
    if (dataClassName == 'GuidanceRequest') {
      return deserialize<_i3j1yq52.GuidanceRequest>(data['data']);
    }
    if (dataClassName == 'InboxItem') {
      return deserialize<_iv6iq8qv.InboxItem>(data['data']);
    }
    if (dataClassName == 'Invitation') {
      return deserialize<_ix00wubs.Invitation>(data['data']);
    }
    if (dataClassName == 'MediaAsset') {
      return deserialize<_ivzdqkik.MediaAsset>(data['data']);
    }
    if (dataClassName == 'MediaInfo') {
      return deserialize<_iyb2dgte.MediaInfo>(data['data']);
    }
    if (dataClassName == 'MediaReference') {
      return deserialize<_il7l0uyh.MediaReference>(data['data']);
    }
    if (dataClassName == 'MediaUploadRequest') {
      return deserialize<_i6mex4av.MediaUploadRequest>(data['data']);
    }
    if (dataClassName == 'MediaUploadTicket') {
      return deserialize<_iu821fma.MediaUploadTicket>(data['data']);
    }
    if (dataClassName == 'MemberInfo') {
      return deserialize<_i2slp771.MemberInfo>(data['data']);
    }
    if (dataClassName == 'MiniApp') {
      return deserialize<_ivniu53p.MiniApp>(data['data']);
    }
    if (dataClassName == 'MiniAppGrant') {
      return deserialize<_iurwb5gp.MiniAppGrant>(data['data']);
    }
    if (dataClassName == 'NestError') {
      return deserialize<_i0tc2cek.NestError>(data['data']);
    }
    if (dataClassName == 'Notification') {
      return deserialize<_irt10kca.Notification>(data['data']);
    }
    if (dataClassName == 'OutboxEvent') {
      return deserialize<_i6i2iffh.OutboxEvent>(data['data']);
    }
    if (dataClassName == 'PlatformInfo') {
      return deserialize<_ici3to49.PlatformInfo>(data['data']);
    }
    if (dataClassName == 'PublishRequest') {
      return deserialize<_iijemlr5.PublishRequest>(data['data']);
    }
    if (dataClassName == 'RecordPage') {
      return deserialize<_i4a9pphb.RecordPage>(data['data']);
    }
    if (dataClassName == 'RecordSummary') {
      return deserialize<_ifx2sflx.RecordSummary>(data['data']);
    }
    if (dataClassName == 'ReminderState') {
      return deserialize<_ipsxd53m.ReminderState>(data['data']);
    }
    if (dataClassName == 'ResourcePool') {
      return deserialize<_i6hl3xhc.ResourcePool>(data['data']);
    }
    if (dataClassName == 'RuntimeRecord') {
      return deserialize<_ilpx295a.RuntimeRecord>(data['data']);
    }
    if (dataClassName == 'Template') {
      return deserialize<_ibutn46j.Template>(data['data']);
    }
    if (dataClassName == 'TemplateInfo') {
      return deserialize<_i1ykl0x7.TemplateInfo>(data['data']);
    }
    if (dataClassName == 'Workspace') {
      return deserialize<_io6eoug6.Workspace>(data['data']);
    }
    if (dataClassName == 'WorkspaceInfo') {
      return deserialize<_ixz9batj.WorkspaceInfo>(data['data']);
    }
    if (dataClassName == 'WorkspaceMember') {
      return deserialize<_iidcmvkk.WorkspaceMember>(data['data']);
    }
    if (dataClassName.startsWith('serverpod_auth_idp.')) {
      data['className'] = dataClassName.substring(19);
      return _iais.Protocol().deserializeByClassName(data);
    }
    if (dataClassName.startsWith('serverpod_auth_core.')) {
      data['className'] = dataClassName.substring(20);
      return _iacs.Protocol().deserializeByClassName(data);
    }
    if (dataClassName.startsWith('serverpod.')) {
      data['className'] = dataClassName.substring(10);
      return _isp.Protocol().deserializeByClassName(data);
    }
    return super.deserializeByClassName(data);
  }

  void _registerHostProtocols() {
    _iais.Protocol().registerHostProtocol('appnest', this);
    _iacs.Protocol().registerHostProtocol('appnest', this);
  }

  @override
  _is.Table? getTableForType(Type t) {
    {
      var table = _iais.Protocol().getTableForType(t);
      if (table != null) {
        return table;
      }
    }
    {
      var table = _iacs.Protocol().getTableForType(t);
      if (table != null) {
        return table;
      }
    }
    {
      var table = _isp.Protocol().getTableForType(t);
      if (table != null) {
        return table;
      }
    }
    switch (t) {
      case _izkbb96g.ActionReceipt:
        return _izkbb96g.ActionReceipt.t;
      case _iq0wu3gu.AppDraft:
        return _iq0wu3gu.AppDraft.t;
      case _i1wu1dla.AppShortcut:
        return _i1wu1dla.AppShortcut.t;
      case _izejoxi5.AppVersion:
        return _izejoxi5.AppVersion.t;
      case _i1613bfs.AuditEntry:
        return _i1613bfs.AuditEntry.t;
      case _ife4t62f.Automation:
        return _ife4t62f.Automation.t;
      case _ixu7zng5.AutomationRun:
        return _ixu7zng5.AutomationRun.t;
      case _iywv5oz4.Claim:
        return _iywv5oz4.Claim.t;
      case _iy0qwluf.EntityRecord:
        return _iy0qwluf.EntityRecord.t;
      case _iyrqavho.FieldValue:
        return _iyrqavho.FieldValue.t;
      case _ig17l95t.GenerationJob:
        return _ig17l95t.GenerationJob.t;
      case _i3j1yq52.GuidanceRequest:
        return _i3j1yq52.GuidanceRequest.t;
      case _ix00wubs.Invitation:
        return _ix00wubs.Invitation.t;
      case _ivzdqkik.MediaAsset:
        return _ivzdqkik.MediaAsset.t;
      case _il7l0uyh.MediaReference:
        return _il7l0uyh.MediaReference.t;
      case _ivniu53p.MiniApp:
        return _ivniu53p.MiniApp.t;
      case _iurwb5gp.MiniAppGrant:
        return _iurwb5gp.MiniAppGrant.t;
      case _irt10kca.Notification:
        return _irt10kca.Notification.t;
      case _i6i2iffh.OutboxEvent:
        return _i6i2iffh.OutboxEvent.t;
      case _i6hl3xhc.ResourcePool:
        return _i6hl3xhc.ResourcePool.t;
      case _ibutn46j.Template:
        return _ibutn46j.Template.t;
      case _io6eoug6.Workspace:
        return _io6eoug6.Workspace.t;
      case _iidcmvkk.WorkspaceMember:
        return _iidcmvkk.WorkspaceMember.t;
    }
    return null;
  }

  @override
  List<_isp.TableDefinition> getTargetTableDefinitions() =>
      targetTableDefinitions;

  @override
  String getModuleName() => 'appnest';

  /// Maps any `Record`s known to this [Protocol] to their JSON representation
  ///
  /// Throws in case the record type is not known.
  ///
  /// This method will return `null` (only) for `null` inputs.
  Map<String, dynamic>? mapRecordToJson(Record? record) {
    if (record == null) {
      return null;
    }
    try {
      return _iais.Protocol().mapRecordToJson(record);
    } catch (_) {}
    try {
      return _iacs.Protocol().mapRecordToJson(record);
    } catch (_) {}
    throw Exception('Unsupported record type ${record.runtimeType}');
  }
}

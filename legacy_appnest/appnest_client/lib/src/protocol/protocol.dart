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
import 'package:appnest_client/src/protocol/activity_item.dart' as _ihdhb6mh;
import 'package:appnest_client/src/protocol/app_manifest.dart' as _igbv6cp9;
import 'package:appnest_client/src/protocol/guidance_question.dart'
    as _ir7xtg43;
import 'package:appnest_client/src/protocol/inbox_item.dart' as _ic0zicoc;
import 'package:appnest_client/src/protocol/member_info.dart' as _iqjsfrnp;
import 'package:appnest_client/src/protocol/reminder_state.dart' as _i1a6ysmx;
import 'package:appnest_client/src/protocol/template_info.dart' as _ik25ew2o;
import 'package:appnest_client/src/protocol/workspace_info.dart' as _i1i173ve;
import 'package:serverpod_auth_core_client/serverpod_auth_core_client.dart'
    as _iacc;
import 'package:serverpod_auth_idp_client/serverpod_auth_idp_client.dart'
    as _iaic;
import 'package:serverpod_client/serverpod_client.dart' as _isc;
import 'action_outcome.dart' as _isykbnbw;
import 'action_request.dart' as _ii1w3lxm;
import 'activity_item.dart' as _irh51hj1;
import 'app_event.dart' as _iwn9176r;
import 'app_manifest.dart' as _i65w4jw3;
import 'builder_snapshot.dart' as _i4n6ivgk;
import 'greetings/greeting.dart' as _izw8z7ou;
import 'guidance_question.dart' as _istc82cm;
import 'inbox_item.dart' as _iv6iq8qv;
import 'media_info.dart' as _iyb2dgte;
import 'media_upload_request.dart' as _i6mex4av;
import 'media_upload_ticket.dart' as _iu821fma;
import 'member_info.dart' as _i2slp771;
import 'nest_error.dart' as _i0tc2cek;
import 'platform_info.dart' as _ici3to49;
import 'publish_request.dart' as _iijemlr5;
import 'record_page.dart' as _i4a9pphb;
import 'record_summary.dart' as _ifx2sflx;
import 'reminder_state.dart' as _ipsxd53m;
import 'runtime_record.dart' as _ilpx295a;
import 'template_info.dart' as _i1ykl0x7;
import 'workspace_info.dart' as _ixz9batj;
export 'action_outcome.dart';
export 'action_request.dart';
export 'activity_item.dart';
export 'app_event.dart';
export 'app_manifest.dart';
export 'builder_snapshot.dart';
export 'greetings/greeting.dart';
export 'guidance_question.dart';
export 'inbox_item.dart';
export 'media_info.dart';
export 'media_upload_request.dart';
export 'media_upload_ticket.dart';
export 'member_info.dart';
export 'nest_error.dart';
export 'platform_info.dart';
export 'publish_request.dart';
export 'record_page.dart';
export 'record_summary.dart';
export 'reminder_state.dart';
export 'runtime_record.dart';
export 'template_info.dart';
export 'workspace_info.dart';
export 'client.dart';

class Protocol extends _isc.SerializationManager {
  Protocol._();

  factory Protocol() => _instance;

  static final Protocol _instance = Protocol._().._registerHostProtocols();

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
      } on _isc.DeserializationClassNameNotFoundException catch (_) {
        // If the className is not recognized (e.g., older client receiving
        // data with a new subtype), fall back to deserializing without the
        // className, using the expected type T.
      }
    }

    if (t == _isykbnbw.ActionOutcome) {
      return _isykbnbw.ActionOutcome.fromJson(data) as T;
    }
    if (t == _ii1w3lxm.ActionRequest) {
      return _ii1w3lxm.ActionRequest.fromJson(data) as T;
    }
    if (t == _irh51hj1.ActivityItem) {
      return _irh51hj1.ActivityItem.fromJson(data) as T;
    }
    if (t == _iwn9176r.AppEvent) {
      return _iwn9176r.AppEvent.fromJson(data) as T;
    }
    if (t == _i65w4jw3.AppManifest) {
      return _i65w4jw3.AppManifest.fromJson(data) as T;
    }
    if (t == _i4n6ivgk.BuilderSnapshot) {
      return _i4n6ivgk.BuilderSnapshot.fromJson(data) as T;
    }
    if (t == _izw8z7ou.Greeting) {
      return _izw8z7ou.Greeting.fromJson(data) as T;
    }
    if (t == _istc82cm.GuidanceQuestion) {
      return _istc82cm.GuidanceQuestion.fromJson(data) as T;
    }
    if (t == _iv6iq8qv.InboxItem) {
      return _iv6iq8qv.InboxItem.fromJson(data) as T;
    }
    if (t == _iyb2dgte.MediaInfo) {
      return _iyb2dgte.MediaInfo.fromJson(data) as T;
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
    if (t == _i0tc2cek.NestError) {
      return _i0tc2cek.NestError.fromJson(data) as T;
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
    if (t == _ilpx295a.RuntimeRecord) {
      return _ilpx295a.RuntimeRecord.fromJson(data) as T;
    }
    if (t == _i1ykl0x7.TemplateInfo) {
      return _i1ykl0x7.TemplateInfo.fromJson(data) as T;
    }
    if (t == _ixz9batj.WorkspaceInfo) {
      return _ixz9batj.WorkspaceInfo.fromJson(data) as T;
    }
    if (t == _isc.getType<_isykbnbw.ActionOutcome?>()) {
      return (data != null ? _isykbnbw.ActionOutcome.fromJson(data) : null)
          as T;
    }
    if (t == _isc.getType<_ii1w3lxm.ActionRequest?>()) {
      return (data != null ? _ii1w3lxm.ActionRequest.fromJson(data) : null)
          as T;
    }
    if (t == _isc.getType<_irh51hj1.ActivityItem?>()) {
      return (data != null ? _irh51hj1.ActivityItem.fromJson(data) : null) as T;
    }
    if (t == _isc.getType<_iwn9176r.AppEvent?>()) {
      return (data != null ? _iwn9176r.AppEvent.fromJson(data) : null) as T;
    }
    if (t == _isc.getType<_i65w4jw3.AppManifest?>()) {
      return (data != null ? _i65w4jw3.AppManifest.fromJson(data) : null) as T;
    }
    if (t == _isc.getType<_i4n6ivgk.BuilderSnapshot?>()) {
      return (data != null ? _i4n6ivgk.BuilderSnapshot.fromJson(data) : null)
          as T;
    }
    if (t == _isc.getType<_izw8z7ou.Greeting?>()) {
      return (data != null ? _izw8z7ou.Greeting.fromJson(data) : null) as T;
    }
    if (t == _isc.getType<_istc82cm.GuidanceQuestion?>()) {
      return (data != null ? _istc82cm.GuidanceQuestion.fromJson(data) : null)
          as T;
    }
    if (t == _isc.getType<_iv6iq8qv.InboxItem?>()) {
      return (data != null ? _iv6iq8qv.InboxItem.fromJson(data) : null) as T;
    }
    if (t == _isc.getType<_iyb2dgte.MediaInfo?>()) {
      return (data != null ? _iyb2dgte.MediaInfo.fromJson(data) : null) as T;
    }
    if (t == _isc.getType<_i6mex4av.MediaUploadRequest?>()) {
      return (data != null ? _i6mex4av.MediaUploadRequest.fromJson(data) : null)
          as T;
    }
    if (t == _isc.getType<_iu821fma.MediaUploadTicket?>()) {
      return (data != null ? _iu821fma.MediaUploadTicket.fromJson(data) : null)
          as T;
    }
    if (t == _isc.getType<_i2slp771.MemberInfo?>()) {
      return (data != null ? _i2slp771.MemberInfo.fromJson(data) : null) as T;
    }
    if (t == _isc.getType<_i0tc2cek.NestError?>()) {
      return (data != null ? _i0tc2cek.NestError.fromJson(data) : null) as T;
    }
    if (t == _isc.getType<_ici3to49.PlatformInfo?>()) {
      return (data != null ? _ici3to49.PlatformInfo.fromJson(data) : null) as T;
    }
    if (t == _isc.getType<_iijemlr5.PublishRequest?>()) {
      return (data != null ? _iijemlr5.PublishRequest.fromJson(data) : null)
          as T;
    }
    if (t == _isc.getType<_i4a9pphb.RecordPage?>()) {
      return (data != null ? _i4a9pphb.RecordPage.fromJson(data) : null) as T;
    }
    if (t == _isc.getType<_ifx2sflx.RecordSummary?>()) {
      return (data != null ? _ifx2sflx.RecordSummary.fromJson(data) : null)
          as T;
    }
    if (t == _isc.getType<_ipsxd53m.ReminderState?>()) {
      return (data != null ? _ipsxd53m.ReminderState.fromJson(data) : null)
          as T;
    }
    if (t == _isc.getType<_ilpx295a.RuntimeRecord?>()) {
      return (data != null ? _ilpx295a.RuntimeRecord.fromJson(data) : null)
          as T;
    }
    if (t == _isc.getType<_i1ykl0x7.TemplateInfo?>()) {
      return (data != null ? _i1ykl0x7.TemplateInfo.fromJson(data) : null) as T;
    }
    if (t == _isc.getType<_ixz9batj.WorkspaceInfo?>()) {
      return (data != null ? _ixz9batj.WorkspaceInfo.fromJson(data) : null)
          as T;
    }
    if (t == dynamic) {
      return deserializeDynamicFieldValue(data) as T;
    }
    if (t == List<String>) {
      return (data as List).map((e) => deserialize<String>(e)).toList() as T;
    }
    if (t == _isc.getType<List<String>?>()) {
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
    if (t == List<_i1i173ve.WorkspaceInfo>) {
      return (data as List)
              .map((e) => deserialize<_i1i173ve.WorkspaceInfo>(e))
              .toList()
          as T;
    }
    if (t == List<_igbv6cp9.AppManifest>) {
      return (data as List)
              .map((e) => deserialize<_igbv6cp9.AppManifest>(e))
              .toList()
          as T;
    }
    if (t == List<_ik25ew2o.TemplateInfo>) {
      return (data as List)
              .map((e) => deserialize<_ik25ew2o.TemplateInfo>(e))
              .toList()
          as T;
    }
    if (t == List<_iqjsfrnp.MemberInfo>) {
      return (data as List)
              .map((e) => deserialize<_iqjsfrnp.MemberInfo>(e))
              .toList()
          as T;
    }
    if (t == List<_ihdhb6mh.ActivityItem>) {
      return (data as List)
              .map((e) => deserialize<_ihdhb6mh.ActivityItem>(e))
              .toList()
          as T;
    }
    if (t == List<_ir7xtg43.GuidanceQuestion>) {
      return (data as List)
              .map((e) => deserialize<_ir7xtg43.GuidanceQuestion>(e))
              .toList()
          as T;
    }
    if (t == List<_i1a6ysmx.ReminderState>) {
      return (data as List)
              .map((e) => deserialize<_i1a6ysmx.ReminderState>(e))
              .toList()
          as T;
    }
    if (t == List<_ic0zicoc.InboxItem>) {
      return (data as List)
              .map((e) => deserialize<_ic0zicoc.InboxItem>(e))
              .toList()
          as T;
    }
    try {
      return _iaic.Protocol().deserialize<T>(data, t);
    } on _isc.DeserializationTypeNotFoundException catch (_) {}
    try {
      return _iacc.Protocol().deserialize<T>(data, t);
    } on _isc.DeserializationTypeNotFoundException catch (_) {}
    return super.deserialize<T>(data, t);
  }

  static String? getClassNameForType(Type type) {
    return switch (type) {
      _isykbnbw.ActionOutcome => 'ActionOutcome',
      _ii1w3lxm.ActionRequest => 'ActionRequest',
      _irh51hj1.ActivityItem => 'ActivityItem',
      _iwn9176r.AppEvent => 'AppEvent',
      _i65w4jw3.AppManifest => 'AppManifest',
      _i4n6ivgk.BuilderSnapshot => 'BuilderSnapshot',
      _izw8z7ou.Greeting => 'Greeting',
      _istc82cm.GuidanceQuestion => 'GuidanceQuestion',
      _iv6iq8qv.InboxItem => 'InboxItem',
      _iyb2dgte.MediaInfo => 'MediaInfo',
      _i6mex4av.MediaUploadRequest => 'MediaUploadRequest',
      _iu821fma.MediaUploadTicket => 'MediaUploadTicket',
      _i2slp771.MemberInfo => 'MemberInfo',
      _i0tc2cek.NestError => 'NestError',
      _ici3to49.PlatformInfo => 'PlatformInfo',
      _iijemlr5.PublishRequest => 'PublishRequest',
      _i4a9pphb.RecordPage => 'RecordPage',
      _ifx2sflx.RecordSummary => 'RecordSummary',
      _ipsxd53m.ReminderState => 'ReminderState',
      _ilpx295a.RuntimeRecord => 'RuntimeRecord',
      _i1ykl0x7.TemplateInfo => 'TemplateInfo',
      _ixz9batj.WorkspaceInfo => 'WorkspaceInfo',
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
      case _ii1w3lxm.ActionRequest():
        return 'ActionRequest';
      case _irh51hj1.ActivityItem():
        return 'ActivityItem';
      case _iwn9176r.AppEvent():
        return 'AppEvent';
      case _i65w4jw3.AppManifest():
        return 'AppManifest';
      case _i4n6ivgk.BuilderSnapshot():
        return 'BuilderSnapshot';
      case _izw8z7ou.Greeting():
        return 'Greeting';
      case _istc82cm.GuidanceQuestion():
        return 'GuidanceQuestion';
      case _iv6iq8qv.InboxItem():
        return 'InboxItem';
      case _iyb2dgte.MediaInfo():
        return 'MediaInfo';
      case _i6mex4av.MediaUploadRequest():
        return 'MediaUploadRequest';
      case _iu821fma.MediaUploadTicket():
        return 'MediaUploadTicket';
      case _i2slp771.MemberInfo():
        return 'MemberInfo';
      case _i0tc2cek.NestError():
        return 'NestError';
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
      case _ilpx295a.RuntimeRecord():
        return 'RuntimeRecord';
      case _i1ykl0x7.TemplateInfo():
        return 'TemplateInfo';
      case _ixz9batj.WorkspaceInfo():
        return 'WorkspaceInfo';
    }
    className = _iaic.Protocol().getClassNameForObject(data);
    if (className != null) {
      return className.contains('.')
          ? className
          : 'serverpod_auth_idp.$className';
    }
    className = _iacc.Protocol().getClassNameForObject(data);
    if (className != null) {
      return className.contains('.')
          ? className
          : 'serverpod_auth_core.$className';
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
    if (dataClassName == 'ActionRequest') {
      return deserialize<_ii1w3lxm.ActionRequest>(data['data']);
    }
    if (dataClassName == 'ActivityItem') {
      return deserialize<_irh51hj1.ActivityItem>(data['data']);
    }
    if (dataClassName == 'AppEvent') {
      return deserialize<_iwn9176r.AppEvent>(data['data']);
    }
    if (dataClassName == 'AppManifest') {
      return deserialize<_i65w4jw3.AppManifest>(data['data']);
    }
    if (dataClassName == 'BuilderSnapshot') {
      return deserialize<_i4n6ivgk.BuilderSnapshot>(data['data']);
    }
    if (dataClassName == 'Greeting') {
      return deserialize<_izw8z7ou.Greeting>(data['data']);
    }
    if (dataClassName == 'GuidanceQuestion') {
      return deserialize<_istc82cm.GuidanceQuestion>(data['data']);
    }
    if (dataClassName == 'InboxItem') {
      return deserialize<_iv6iq8qv.InboxItem>(data['data']);
    }
    if (dataClassName == 'MediaInfo') {
      return deserialize<_iyb2dgte.MediaInfo>(data['data']);
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
    if (dataClassName == 'NestError') {
      return deserialize<_i0tc2cek.NestError>(data['data']);
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
    if (dataClassName == 'RuntimeRecord') {
      return deserialize<_ilpx295a.RuntimeRecord>(data['data']);
    }
    if (dataClassName == 'TemplateInfo') {
      return deserialize<_i1ykl0x7.TemplateInfo>(data['data']);
    }
    if (dataClassName == 'WorkspaceInfo') {
      return deserialize<_ixz9batj.WorkspaceInfo>(data['data']);
    }
    if (dataClassName.startsWith('serverpod_auth_idp.')) {
      data['className'] = dataClassName.substring(19);
      return _iaic.Protocol().deserializeByClassName(data);
    }
    if (dataClassName.startsWith('serverpod_auth_core.')) {
      data['className'] = dataClassName.substring(20);
      return _iacc.Protocol().deserializeByClassName(data);
    }
    return super.deserializeByClassName(data);
  }

  void _registerHostProtocols() {
    _iaic.Protocol().registerHostProtocol('appnest', this);
    _iacc.Protocol().registerHostProtocol('appnest', this);
  }

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
      return _iaic.Protocol().mapRecordToJson(record);
    } catch (_) {}
    try {
      return _iacc.Protocol().mapRecordToJson(record);
    } catch (_) {}
    throw Exception('Unsupported record type ${record.runtimeType}');
  }
}

part of 'service.dart';

/// An authenticated semantic state snapshot for negotiated foreground polling.
/// Guard nonces serialize reads but are deliberately absent from this DTO.
extension _SpecWatch on PlatformService {
  Future<Row> _specWatch(String actor, Row input) async {
    _inputKeys(input, {'op', 'appId'});
    final appId = _validId(input['appId']);
    return _specRead(actor, appId, (access, tx) async {
      _publishedOrOwner(access);
      return {
        'appId': access.app[r'$id'],
        'versionId': access.app['specVersionId'],
        'controlRevision': _storedRevision(access.app, 'controlRevision'),
        'role': access.role,
        'archived': access.archived,
      };
    });
  }
}

import 'package:flutter/foundation.dart';

/// Invitations open the authenticated web launcher, including on a phone.
/// Production native builds must provide APP_WEB_URL; the fixed development
/// API port can use the backend's web port on the same reachable host.
Uri invitationWebOrigin({
  required String backendUrl,
  required Uri currentPage,
  bool web = kIsWeb,
  bool? phone,
  String publicWebUrl = const String.fromEnvironment('APP_WEB_URL'),
}) {
  final isPhone =
      phone ??
      (!web &&
          (defaultTargetPlatform == TargetPlatform.iOS ||
              defaultTargetPlatform == TargetPlatform.android));
  Uri origin;
  if (publicWebUrl.isNotEmpty) {
    origin = _webAddress(publicWebUrl);
  } else if (web) {
    // Browser deployments retain their existing origin, never an API origin.
    if (!const {'http', 'https'}.contains(currentPage.scheme)) {
      throw const InvitationLinkConfigurationError();
    }
    origin = _webAddress(currentPage.origin);
  } else {
    final backend = _webAddress(backendUrl);
    if (backend.port != 8180) throw const InvitationLinkConfigurationError();
    origin = backend.replace(port: 8182);
  }
  if (isPhone &&
      const {'localhost', '127.0.0.1', '::1', '0.0.0.0', '::'}.contains(
        origin.host.toLowerCase(),
      )) {
    throw const InvitationLinkConfigurationError();
  }
  return origin;
}

Uri _webAddress(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      !const {'http', 'https'}.contains(uri.scheme) ||
      !uri.hasAuthority ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      (uri.path.isNotEmpty && uri.path != '/') ||
      uri.hasQuery ||
      uri.hasFragment) {
    throw const InvitationLinkConfigurationError();
  }
  return uri.replace(path: '/');
}

class InvitationLinkConfigurationError implements Exception {
  const InvitationLinkConfigurationError();
  String get message =>
      'Sharing links are unavailable for this connection. Ask your AppNest administrator to configure the web address.';
}

class ServiceException implements Exception {
  const ServiceException(this.code, this.status);
  final String code;
  final int status;
}

class RestException implements Exception {
  const RestException(this.status, {this.authFailure = false});
  final int status;
  final bool authFailure;
}

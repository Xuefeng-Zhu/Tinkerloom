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

/// The commit endpoint rejected this attempt and its transaction is terminal.
/// Never use this for a status-only conflict or an unconfirmed commit response.
class ConfirmedTransactionAbort extends RestException {
  const ConfirmedTransactionAbort() : super(409);
}

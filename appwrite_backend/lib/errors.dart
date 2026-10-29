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

/// Fixed private logging categories; never serialize raw upstream values.
enum TransactionDiagnostic {
  stagingConflict,
  commitBodyAccepted,
  commitBodyRejected,
  commitResponseOther,
  terminalLookupDenied,
  terminalLookupUnavailable,
  terminalIdentityMismatch,
  terminalNotConfirmed,
  abortConfirmed,
  retryStarted,
  retryExhausted,
  retryNotEnabled,
  cleanupUnconfirmed,
}

/// Per-execution opt-in logger. Logging failures never alter database work.
class TransactionDiagnosticLog {
  TransactionDiagnosticLog(this.write, {this.enabled = false});
  final void Function(TransactionDiagnostic) write;
  final bool enabled;
  int _sent = 0;
  void emit(TransactionDiagnostic event) {
    if (!enabled || _sent >= 12) return;
    _sent++;
    try {
      write(event);
    } catch (_) {}
  }
}

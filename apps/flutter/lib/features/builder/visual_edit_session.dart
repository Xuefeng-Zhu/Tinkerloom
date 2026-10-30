import 'dart:async';
import 'dart:convert';

import 'package:tinkerloom_client/tinkerloom_client.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:flutter/foundation.dart';

typedef VisualPatch = Map<String, dynamic> Function(AppSpec spec);

/// One revision-aware queue for all inspector controls. Factories build full
/// page/view payloads against the last acknowledgement, never a stale form.
class VisualEditSession extends ChangeNotifier {
  BuilderSnapshot snapshot;
  final Future<BuilderSnapshot> Function() read;
  final Future<BuilderSnapshot> Function() readForRecovery;
  final int Function() sessionEpoch;
  final Future<BuilderSnapshot> Function(int mutation, String patch) write;
  final Future<RetainedCommandStatus> Function(
    int mutation,
    String candidateHash,
  )
  confirmSave;
  final void Function(BuilderSnapshot, Map<String, dynamic>) onSaved;
  final _pending = <String, VisualPatch>{};
  Timer? _debounce;
  Future<bool>? _flight;
  bool _disposed = false;
  bool conflict = false;
  bool _uncertain = false;
  bool _confirmed = false;
  int? _confirmationEpoch;
  ({
    MapEntry<String, VisualPatch> entry,
    Map<String, dynamic> patch,
    AppSpec expected,
    int epoch,
  })?
  _attempt;
  String? error;
  String? validationError;
  VisualEditSession({
    required this.snapshot,
    required this.read,
    required this.readForRecovery,
    required this.sessionEpoch,
    required this.write,
    required this.confirmSave,
    required this.onSaved,
  });

  bool get pending => _pending.isNotEmpty;
  bool get saving => _flight != null;
  bool get uncertain => _uncertain;
  String get status =>
      validationError ?? error ?? (pending || saving ? 'Saving…' : 'Saved');
  AppSpec get spec => AppSpec.parse(snapshot.candidateJson);
  AppSpec get projected {
    var value = spec;
    for (final intent in _pending.values) {
      value = value.patch(
        intent(value),
        () => throw StateError('Unexpected new ID'),
      );
    }
    return value;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void enqueue(String key, VisualPatch patch, {bool immediate = false}) {
    if (conflict || _disposed) return;
    _pending[key] = patch;
    validationError = null;
    try {
      projected;
    } catch (e) {
      validationError = e.toString();
    }
    _debounce?.cancel();
    _notify();
    if (validationError == null && error == null) {
      if (immediate) {
        unawaited(flush());
      } else {
        _debounce = Timer(const Duration(milliseconds: 600), flush);
      }
    }
  }

  Future<bool> flush({bool retry = false}) async {
    _debounce?.cancel();
    if (_flight != null) return _flight!;
    if (_disposed ||
        conflict ||
        validationError != null ||
        (error != null && !retry)) {
      return false;
    }
    error = null;
    final completer = Completer<bool>();
    _flight = completer.future;
    _notify();
    try {
      completer.complete(await _drain());
    } catch (issue) {
      error = issue is BackendUnauthorized
          ? issue.message
          : _uncertain
          ? 'The save outcome is unknown. Check save status before continuing.'
          : 'Couldn’t save. Your changes are kept here.';
      completer.complete(false);
    } finally {
      _flight = null;
      _notify();
    }
    return completer.future;
  }

  Future<bool> _drain() async {
    while (_pending.isNotEmpty && !_disposed) {
      if (validationError != null) return false;
      if (_uncertain) {
        final pendingAttempt = _attempt;
        if (pendingAttempt == null) throw StateError('Missing pending save.');
        if (pendingAttempt.epoch != sessionEpoch()) {
          throw BackendUnauthorized('Your session changed. Reopen the app.');
        }
        if (!_confirmed) {
          final attempt = pendingAttempt;
          final epoch = sessionEpoch();
          final result = await confirmSave(
            snapshot.mutation,
            attempt.expected.hash,
          );
          if (epoch != sessionEpoch()) {
            throw BackendUnauthorized('Your session changed. Reopen the app.');
          }
          if (result != RetainedCommandStatus.confirmed) {
            error = 'The save outcome is unknown. Check save status before continuing.';
            return false;
          }
          _confirmed = true;
          _confirmationEpoch = epoch;
        }
        if (_confirmationEpoch != sessionEpoch()) {
          throw BackendUnauthorized('Your session changed. Reopen the app.');
        }
        final latest = await readForRecovery();
        if (_confirmationEpoch != sessionEpoch()) {
          throw BackendUnauthorized('Your session changed. Reopen the app.');
        }
        final attempt = _attempt;
        if (attempt != null &&
            latest.mutation == snapshot.mutation + 1 &&
            latest.candidateHash == attempt.expected.hash) {
          snapshot = latest;
          if (identical(_pending[attempt.entry.key], attempt.entry.value)) {
            _pending.remove(attempt.entry.key);
          }
          _uncertain = false;
          _confirmed = false;
          _confirmationEpoch = null;
          _attempt = null;
          onSaved(latest, attempt.patch);
          _notify();
          continue;
        }
        // The receipt confirms the command, but the current draft no longer
        // matches its result. Do not claim the latest state is this save.
        _uncertain = false;
        _confirmed = false;
        _confirmationEpoch = null;
        conflict = true;
        error = 'The save completed, but the draft has changed. Reload the latest draft to continue.';
        return false;
      }
      final entry = _pending.entries.first;
      final base = snapshot;
      final patch = entry.value(spec);
      final expected = spec.patch(
        patch,
        () => throw StateError('Unexpected new ID'),
      );
      if (expected.hash == base.candidateHash) {
        if (identical(_pending[entry.key], entry.value)) {
          _pending.remove(entry.key);
        }
        continue;
      }
      BuilderSnapshot next;
      final attemptEpoch = sessionEpoch();
      _attempt = (
        entry: entry,
        patch: patch,
        expected: expected,
        epoch: attemptEpoch,
      );
      try {
        next = await write(base.mutation, jsonEncode(patch));
        if (attemptEpoch != sessionEpoch()) {
          throw BackendUnauthorized('Your session changed. Reopen the app.');
        }
      } catch (issue) {
        if (attemptEpoch != sessionEpoch()) {
          _uncertain = true;
          error = 'Your session changed. Reopen the app.';
        } else if (issue is NestError && !issue.uncertain) {
          if (issue.category == 'revision_conflict' ||
              issue.category == 'definition_conflict') {
            conflict = true;
            error = 'The draft changed. Reload the latest draft to continue.';
          } else {
            error = 'Couldn’t save. Your changes are kept here.';
          }
        } else {
          _uncertain = true;
          error = 'The save outcome is unknown. Check save status before continuing.';
        }
        return false;
      }
      if (_disposed) return false;
      if (next.mutation != base.mutation + 1 ||
          next.candidateHash != expected.hash) {
        conflict = true;
        error = 'The draft changed. Reload the latest draft to continue.';
        return false;
      }
      _uncertain = false;
      _attempt = null;
      snapshot = next;
      if (identical(_pending[entry.key], entry.value)) {
        _pending.remove(entry.key);
      }
      onSaved(next, patch);
      _notify();
    }
    return !_disposed;
  }

  /// Reload/discard is an explicit user decision after an error or conflict.
  Future<BuilderSnapshot> reload() async {
    if (_flight != null) await _flight;
    if (_uncertain) {
      throw StateError('The save outcome is still unknown.');
    }
    final latest = await read();
    _pending.clear();
    _debounce?.cancel();
    snapshot = latest;
    conflict = false;
    _uncertain = false;
    _attempt = null;
    error = validationError = null;
    _notify();
    return latest;
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    super.dispose();
  }
}

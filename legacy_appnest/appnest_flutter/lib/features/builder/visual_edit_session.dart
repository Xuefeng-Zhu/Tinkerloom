import 'dart:async';
import 'dart:convert';

import 'package:appnest_client/appnest_client.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:flutter/foundation.dart';

typedef VisualPatch = Map<String, dynamic> Function(AppSpec spec);

/// One revision-aware queue for all inspector controls. Factories build full
/// page/view payloads against the last acknowledgement, never a stale form.
class VisualEditSession extends ChangeNotifier {
  BuilderSnapshot snapshot;
  final Future<BuilderSnapshot> Function() read;
  final Future<BuilderSnapshot> Function(int mutation, String patch) write;
  final void Function(BuilderSnapshot, Map<String, dynamic>) onSaved;
  final _pending = <String, VisualPatch>{};
  Timer? _debounce;
  Future<bool>? _flight;
  bool _disposed = false;
  bool conflict = false;
  bool _uncertain = false;
  ({
    MapEntry<String, VisualPatch> entry,
    Map<String, dynamic> patch,
    AppSpec expected,
  })?
  _attempt;
  String? error;
  String? validationError;
  VisualEditSession({
    required this.snapshot,
    required this.read,
    required this.write,
    required this.onSaved,
  });

  bool get pending => _pending.isNotEmpty;
  bool get saving => _flight != null;
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
    } catch (_) {
      error = 'Couldn’t save. Retry to check your draft.';
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
        // A failed read must never lead directly to a second mutation.
        final latest = await read();
        final attempt = _attempt;
        if (attempt != null &&
            latest.mutation == snapshot.mutation + 1 &&
            latest.candidateHash == attempt.expected.hash) {
          snapshot = latest;
          if (identical(_pending[attempt.entry.key], attempt.entry.value)) {
            _pending.remove(attempt.entry.key);
          }
          _uncertain = false;
          _attempt = null;
          onSaved(latest, attempt.patch);
          _notify();
          continue;
        }
        if (latest.mutation != snapshot.mutation ||
            latest.candidateHash != snapshot.candidateHash) {
          conflict = true;
          error = 'The draft changed. Reload the latest draft to continue.';
          return false;
        }
        _uncertain = false;
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
      _attempt = (entry: entry, patch: patch, expected: expected);
      try {
        next = await write(base.mutation, jsonEncode(patch));
      } catch (_) {
        _uncertain = true;
        try {
          final latest = await read();
          if (latest.mutation == base.mutation + 1 &&
              latest.candidateHash == expected.hash) {
            next = latest;
          } else {
            if (latest.mutation != base.mutation ||
                latest.candidateHash != base.candidateHash) {
              conflict = true;
              error = 'The draft changed. Reload the latest draft to continue.';
            } else {
              error = 'Couldn’t save. Your changes are kept here. Retry or reload the draft.';
            }
            return false;
          }
        } catch (_) {
          error = 'Couldn’t confirm the save. Retry to check your draft.';
          return false;
        }
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

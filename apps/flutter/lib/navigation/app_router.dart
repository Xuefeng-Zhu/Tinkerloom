import 'dart:async';

import 'package:appnest_renderer/appnest_renderer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../features/home/home_screen.dart';
import '../features/builder/draft_loader.dart';
import '../features/mini_app/mini_app_screen.dart';
import '../screens/sign_in_screen.dart';
import 'browser_history.dart';

/// Locations contain identifiers only. The authenticated runtime resolves them.
class TinkerloomLocation {
  final String? appId, recordId, draftAppId;
  final String? pageId;
  final bool editing;
  final String? historySession;
  final int? historyIndex;
  const TinkerloomLocation({
    this.appId,
    this.draftAppId,
    this.pageId,
    this.recordId,
    this.editing = false,
    this.historySession,
    this.historyIndex,
  });

  static String? _opaqueId(String value) =>
      RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,35}$').hasMatch(value)
      ? value
      : null;

  factory TinkerloomLocation.fromUri(Uri uri) {
    final parts = uri.pathSegments;
    if (parts.length == 2 && parts[0] == 'drafts') {
      final id = _opaqueId(parts[1]);
      return id != null
          ? TinkerloomLocation(draftAppId: id)
          : const TinkerloomLocation();
    }
    if (parts.length != 2 && parts.length != 4) {
      return const TinkerloomLocation();
    }
    final id = _opaqueId(parts[1]);
    if (parts[0] != 'apps' || id == null) {
      return const TinkerloomLocation();
    }
    String? page;
    if (parts.length == 4) {
      if (parts[2] != 'pages' ||
          !RegExp(r'^[a-zA-Z][a-zA-Z0-9_]{0,63}$').hasMatch(parts[3])) {
        return const TinkerloomLocation();
      }
      page = parts[3];
    }
    final record = _opaqueId(uri.queryParameters['record'] ?? '');
    return TinkerloomLocation(
      appId: id,
      pageId: page,
      recordId: record,
      editing: uri.queryParameters['edit'] == 'true',
    );
  }

  TinkerloomLocation withHistory(String session, int index) =>
      TinkerloomLocation(
        appId: appId,
        draftAppId: draftAppId,
        pageId: pageId,
        recordId: recordId,
        editing: editing,
        historySession: session,
        historyIndex: index,
      );

  MiniAppLocation? get miniAppLocation => pageId == null
      ? null
      : MiniAppLocation(pageId!, recordId: recordId, editing: editing);

  Uri get uri => draftAppId != null
      ? Uri(path: '/drafts/$draftAppId')
      : appId == null
      ? Uri(path: '/')
      : Uri(
          path: '/apps/$appId${pageId == null ? '' : '/pages/$pageId'}',
          queryParameters:
              {
                if (recordId != null) 'record': '$recordId',
                if (editing) 'edit': 'true',
              }.isEmpty
              ? null
              : {
                  if (recordId != null) 'record': '$recordId',
                  if (editing) 'edit': 'true',
                },
        );
}

class TinkerloomRouteParser extends RouteInformationParser<TinkerloomLocation> {
  const TinkerloomRouteParser();
  @override
  Future<TinkerloomLocation> parseRouteInformation(
    RouteInformation routeInformation,
  ) {
    var location = TinkerloomLocation.fromUri(routeInformation.uri);
    final state = routeInformation.state;
    if (state is Map &&
        state['appnestSession'] is String &&
        (state['appnestSession'] as String).length <= 128 &&
        state['appnestIndex'] is int &&
        state['appnestIndex'] >= 0) {
      location = location.withHistory(
        state['appnestSession'],
        state['appnestIndex'],
      );
    }
    return SynchronousFuture(location);
  }

  @override
  RouteInformation restoreRouteInformation(TinkerloomLocation configuration) =>
      RouteInformation(
        uri: configuration.uri,
        state: configuration.historySession == null
            ? null
            : {
                'appnestSession': configuration.historySession,
                'appnestIndex': configuration.historyIndex,
              },
      );
}

class TinkerloomRouterDelegate extends RouterDelegate<TinkerloomLocation>
    with ChangeNotifier, PopNavigatorRouterDelegateMixin<TinkerloomLocation> {
  TinkerloomRouterDelegate({Future<bool> Function(int)? browserGo})
    : _browserGo = browserGo ?? goBrowserHistory;

  final Future<bool> Function(int) _browserGo;
  @override
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  var _appKey = GlobalKey<MiniAppScreenState>();
  var _draftKey = GlobalKey<DraftLoaderState>();
  TinkerloomLocation _location = const TinkerloomLocation();
  final _entries = <TinkerloomLocation>[];
  static int _sessionSequence = 0;
  String _session = '';
  int _index = 0;
  int _routeGeneration = 0;
  int? _externalGeneration;
  int _launcherRevision = 0;
  @override
  TinkerloomLocation get currentConfiguration => _location;

  void _report({required bool replace}) {
    final context = navigatorKey.currentContext;
    if (replace && context != null && context.mounted) {
      Router.neglect(context, notifyListeners);
    } else {
      notifyListeners();
    }
  }

  void _resetHistory(TinkerloomLocation location) {
    _session = '${DateTime.now().microsecondsSinceEpoch}-${_sessionSequence++}';
    _index = 0;
    _entries.clear();
    _entries.add(location.withHistory(_session, 0));
    _location = _entries.single;
  }

  void _replace(TinkerloomLocation location) {
    if (_entries.isEmpty) {
      _resetHistory(location);
    } else {
      _location = location.withHistory(_session, _index);
      _entries[_index] = _location;
    }
    _report(replace: true);
  }

  void _push(TinkerloomLocation location) {
    _routeGeneration++;
    if (_entries.isEmpty || location.uri == _location.uri) {
      _replace(location);
      return;
    }
    _entries.removeRange(_index + 1, _entries.length);
    _index++;
    _location = location.withHistory(_session, _index);
    _entries.add(_location);
    _report(replace: false);
  }

  int? _ownedIndex(TinkerloomLocation location) {
    final index = location.historyIndex;
    return location.historySession == _session &&
            index != null &&
            index >= 0 &&
            index < _entries.length &&
            _entries[index].uri == location.uri
        ? index
        : null;
  }

  Future<void> _popTo(TinkerloomLocation target) async {
    final destination = _entries
        .take(_index)
        .toList()
        .lastIndexWhere((entry) => entry.uri == target.uri);
    if (destination >= 0 && await _browserGo(destination - _index)) {
      // The ensuing route-information event commits the owned history index.
      return;
    }
    // A direct link has no known in-app browser parent; never leave the site.
    _replace(target);
  }

  Future<void> openApp(String appId, {String? recordId}) async {
    if (!await _canLeave()) return;
    _appKey = GlobalKey<MiniAppScreenState>();
    _push(TinkerloomLocation(appId: appId, recordId: recordId));
  }

  Future<void> openDraft(String appId) async {
    if (!await _canLeave()) return;
    _draftKey = GlobalKey<DraftLoaderState>();
    _push(TinkerloomLocation(draftAppId: appId));
  }

  Future<void> _publishedDraft(String appId) async {
    _appKey = GlobalKey<MiniAppScreenState>();
    _launcherRevision++;
    _replace(TinkerloomLocation(appId: appId));
  }

  Future<bool> _canLeave() async => _location.draftAppId != null
      ? await _draftKey.currentState?.canLeave() ?? true
      : await _appKey.currentState?.canLeave() ?? true;

  Future<void> closeApp() async {
    if (!await _canLeave()) return;
    _launcherRevision++;
    await _popTo(const TinkerloomLocation());
  }

  void _changed(MiniAppLocation location) {
    if (_location.appId == null) return;
    final kind =
        _appKey.currentState?.controller.navigationKind ??
        MiniAppNavigationKind.external;
    final next = TinkerloomLocation(
      appId: _location.appId,
      pageId: location.pageId,
      recordId: location.recordId,
      editing: location.editing,
    );
    if (next.uri == _location.uri) {
      if (_externalGeneration == null) _replace(next);
      return;
    }
    switch (kind) {
      case MiniAppNavigationKind.push:
        _push(next);
      case MiniAppNavigationKind.pop:
        unawaited(_popTo(next));
      case MiniAppNavigationKind.external:
        if (_externalGeneration == null) _replace(next);
    }
  }

  @override
  Future<void> setNewRoutePath(TinkerloomLocation configuration) async {
    if (_entries.isEmpty) {
      // Resolve the initial identifiers synchronously so Router never reports
      // a temporary launcher URL before the authenticated app is mounted.
      _resetHistory(configuration);
      _report(replace: true);
      return;
    }
    final generation = ++_routeGeneration;
    _externalGeneration = generation;
    final incomingIndex = _ownedIndex(configuration);
    TinkerloomLocation acceptedConfiguration = configuration;
    try {
      var accepted = true;
      if (configuration.appId != _location.appId ||
          configuration.draftAppId != _location.draftAppId) {
        accepted = await _canLeave();
      } else if (configuration.appId != null && _appKey.currentState != null) {
        final screen = _appKey.currentState!;
        accepted = await screen.navigateTo(
          configuration.miniAppLocation,
          recordId: configuration.recordId,
        );
        if (generation != _routeGeneration ||
            !screen.mounted ||
            _appKey.currentState != screen) {
          return;
        }
        final actual = screen.controller.location;
        if (accepted && actual != null) {
          acceptedConfiguration = TinkerloomLocation(
            appId: configuration.appId,
            pageId: actual.pageId,
            recordId: actual.recordId,
            editing: actual.editing,
          );
        }
      }
      if (generation != _routeGeneration) return;
      if (!accepted) {
        if (incomingIndex != null &&
            incomingIndex != _index &&
            await _browserGo(_index - incomingIndex)) {
          return;
        }
        _replace(_location);
        return;
      }
      if ((_location.appId != null || _location.draftAppId != null) &&
          acceptedConfiguration.appId == null &&
          acceptedConfiguration.draftAppId == null) {
        _launcherRevision++;
      }
      if (incomingIndex != null) {
        _index = incomingIndex;
      } else {
        _resetHistory(acceptedConfiguration);
      }
      if (_appKey.currentState?.widget.appId != configuration.appId) {
        _appKey = GlobalKey<MiniAppScreenState>();
      }
      if (_draftKey.currentState?.widget.appId != configuration.draftAppId) {
        _draftKey = GlobalKey<DraftLoaderState>();
      }
      _replace(acceptedConfiguration);
    } finally {
      if (_externalGeneration == generation) _externalGeneration = null;
    }
  }

  @override
  Future<bool> popRoute() async {
    // Dialogs and the builder are imperative routes above these pages.
    final navigator = navigatorKey.currentState;
    if (navigator != null && await navigator.maybePop()) {
      return true;
    }
    if (_location.draftAppId != null) {
      await closeApp();
      return true;
    }
    if (_location.appId == null) return false;
    if (await _appKey.currentState?.back() ?? false) return true;
    await closeApp();
    return true;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SignInScreen(
      child: Navigator(
        key: navigatorKey,
        pages: [
          MaterialPage<void>(
            key: const ValueKey('launcher'),
            child: HomeScreen(
              onOpenApp: openApp,
              onResumeDraft: openDraft,
              refreshToken: _launcherRevision,
            ),
          ),
          if (_location.draftAppId != null)
            MaterialPage<void>(
              key: ValueKey('draft-${_location.draftAppId}'),
              canPop: false,
              onPopInvoked: (didPop, result) async {
                if (!didPop) await closeApp();
              },
              child: DraftLoader(
                key: _draftKey,
                appId: _location.draftAppId!,
                onClose: closeApp,
                onPublished: _publishedDraft,
              ),
            ),
          if (_location.appId != null)
            MaterialPage<void>(
              key: ValueKey('mini-app-${_location.appId}'),
              canPop: false,
              onPopInvoked: (didPop, result) async {
                if (!didPop) {
                  if (!(await _appKey.currentState?.back() ?? false)) {
                    await closeApp();
                  }
                }
              },
              child: MiniAppScreen(
                key: _appKey,
                appId: _location.appId!,
                initialLocation: _location.miniAppLocation,
                initialRecordId: _location.recordId,
                onLocationChanged: _changed,
                onClose: closeApp,
                onOpenApp: openApp,
              ),
            ),
        ],
        onDidRemovePage: (_) {},
      ),
    ),
  );
}

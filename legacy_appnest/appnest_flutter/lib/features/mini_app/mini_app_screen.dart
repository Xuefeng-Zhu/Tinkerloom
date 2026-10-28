import 'package:appnest_client/appnest_client.dart';
import 'package:appnest_renderer/appnest_renderer.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:serverpod_auth_idp_flutter/serverpod_auth_idp_flutter.dart';

import '../../client.dart';
import '../builder/builder_screen.dart';
import 'live_adapter.dart';
import 'device_timer_store.dart';
import 'device_capabilities.dart';
import 'invitation_link.dart';

class MiniAppScreen extends StatefulWidget {
  final int appId;
  final MiniAppLocation? initialLocation;
  final int? initialRecordId;
  final ValueChanged<MiniAppLocation>? onLocationChanged;
  final Future<void> Function()? onClose;
  final Future<void> Function(int appId, {int? recordId})? onOpenApp;
  const MiniAppScreen({
    super.key,
    required this.appId,
    this.initialLocation,
    this.initialRecordId,
    this.onLocationChanged,
    this.onClose,
    this.onOpenApp,
  });
  @override
  State<MiniAppScreen> createState() => MiniAppScreenState();
}

class MiniAppScreenState extends State<MiniAppScreen> {
  AppManifest? manifest;
  Object? error;
  LiveRuntimeAdapter? adapter;
  (String, String, int)? _timerScope;
  final controller = MiniAppController();
  MiniAppLocation? initialLocation;
  int _loadGeneration = 0;
  bool _customizing = false;

  String requestError(Object value) =>
      adapter?.errorMessage(value) ??
      (value is NestError
          ? value.message
          : 'Could not complete the request. Try again.');
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    _loadGeneration++;
    adapter?.deviceCapabilities.dispose();
    adapter?.timerController.dispose();
    controller.dispose();
    super.dispose();
  }

  Future<bool> canLeave() => controller.canLeave();
  Future<bool> back() async {
    final location = controller.location;
    final entry = adapter?.spec.navigation?.entryPageId;
    if (location == null ||
        (location.pageId == entry &&
            location.recordId == null &&
            !location.editing)) {
      return false;
    }
    await controller.back();
    // A declined discard confirmation still consumes the back action.
    return true;
  }

  Future<MiniAppLocation?> _resolveLocation(
    MiniAppLocation? requested,
    int? recordId, {
    LiveRuntimeAdapter? runtime,
  }) async {
    final a = runtime ?? adapter;
    final nav = a?.spec.navigation;
    if (a == null || nav == null) return null;
    if (requested != null) {
      return nav.pages.any((p) => p.id == requested.pageId)
          ? requested
          : MiniAppLocation(nav.entryPageId);
    }
    if (recordId != null) {
      final record = await a.get(recordId);
      final detail = a.spec.views
          .where(
            (v) => v.collectionId == record.collectionId && v.type == 'details',
          )
          .firstOrNull;
      final page = nav.pages
          .where((p) => p.viewIds.contains(detail?.id))
          .firstOrNull;
      if (page != null) return MiniAppLocation(page.id, recordId: recordId);
    }
    return MiniAppLocation(nav.entryPageId);
  }

  Future<bool> navigateTo(MiniAppLocation? location, {int? recordId}) async {
    if (adapter == null) return true;
    try {
      final next = await _resolveLocation(location, recordId);
      if (next != null) return await controller.navigate(next);
      return true;
    } catch (_) {
      if (mounted) {
        setState(() {
          error = const SpecException('This item is no longer available.');
        });
      }
      return true;
    }
  }

  Future<void> close() async {
    if (widget.onClose != null) {
      await widget.onClose!();
    } else if (await canLeave() && mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> customize() async {
    if (_customizing) return;
    final app = manifest;
    if (app == null) return;
    setState(() => _customizing = true);
    try {
      if (!await canLeave() || !mounted) return;
      final draft = await client.builder.begin(
        app.workspaceId,
        'reading',
        app.appId,
      );
      if (!mounted) return;
      await _pauseDevice(true);
      if (!mounted) return;
      await Navigator.push<int>(
        context,
        MaterialPageRoute<int>(builder: (_) => BuilderScreen(initial: draft)),
      );
      if (mounted) await load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Couldn’t open customization. Try again.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        await _pauseDevice(false);
        if (mounted) setState(() => _customizing = false);
      }
    }
  }

  Future<void> _pauseDevice(bool paused) async {
    final device = adapter?.deviceCapabilities;
    if (device is PhoneDeviceCapabilities) await device.setPaused(paused);
  }

  Future<void> deviceAccess() async {
    final device = adapter?.deviceCapabilities;
    if (device == null) return;
    device.attach();
    try {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Device access'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: DeviceAccessPanel(adapter: device),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } finally {
      device.detach();
    }
  }

  Future<void> load() async {
    final generation = ++_loadGeneration;
    LiveRuntimeAdapter? pending;
    var ownsPendingController = true;
    try {
      final m = await client.apps.manifest(widget.appId);
      if (!mounted || generation != _loadGeneration) return;
      if (m.versionId == null) {
        throw NestError(
          category: 'notFound',
          message:
              'This app is not published yet. Open its draft from your apps.',
        );
      }
      UtilityTimerController? timer;
      (String, String, int)? timerScope;
      if (AppSpec.parse(m.specJson!).views
          .any((view) => view.type == 'timer')) {
        final account = client.auth.authInfo?.authUserId.toString();
        if (account == null) {
          throw StateError('Sign in again to open this app.');
        }
        timerScope = (client.host, account, m.appId);
        if (_timerScope == timerScope && adapter != null) {
          timer = adapter!.timerController;
          ownsPendingController = false;
        } else {
          timer = UtilityTimerController(
            store: DeviceTimerStore(
              server: client.host,
              actorId: account,
              appId: m.appId,
            ),
          );
        }
      }
      final mobileSpec = AppSpec.parse(m.specJson!);
      DeviceCapabilitiesAdapter? device;
      if (!m.archived && requestedDeviceCapabilities(mobileSpec).isNotEmpty) {
        final account = client.auth.authInfo?.authUserId.toString();
        if (account == null) {
          throw StateError('Sign in again to open device features.');
        }
        device = PhoneDeviceCapabilities(
          server: client.host,
          actorId: account,
          appId: m.appId,
          spec: mobileSpec,
        );
      }
      final next = LiveRuntimeAdapter(
        client,
        m,
        timerController: timer,
        deviceCapabilities: device,
      );
      pending = next;
      final location = await _resolveLocation(
        controller.location ?? widget.initialLocation,
        widget.initialRecordId,
        runtime: next,
      );
      if (!mounted || generation != _loadGeneration) {
        next.deviceCapabilities.dispose();
        if (ownsPendingController) next.timerController.dispose();
        return;
      }
      if (mounted) {
        final previous = adapter;
        setState(() {
          manifest = m;
          adapter = next;
          _timerScope = timerScope;
          initialLocation = location;
          error = null;
        });
        pending = null;
        previous?.deviceCapabilities.dispose();
        if (!identical(previous?.timerController, next.timerController)) {
          previous?.timerController.dispose();
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && generation == _loadGeneration && location != null) {
            widget.onLocationChanged?.call(controller.location ?? location);
          }
        });
      }
    } catch (e) {
      pending?.deviceCapabilities.dispose();
      if (ownsPendingController) pending?.timerController.dispose();
      if (mounted && generation == _loadGeneration) {
        adapter?.deviceCapabilities.dispose();
        adapter?.timerController.dispose();
        setState(() {
          error = e;
          adapter = null;
          _timerScope = null;
          manifest = null;
        });
      }
    }
  }

  Future<void> share() async {
    String role = 'member';
    final recipient = TextEditingController();
    String? token;
    Uri? invitationLink;
    bool creatingInvitation = false;
    Object? failure;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Invite to this app'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'They join this same app and its shared records. The link expires in 7 days and can be accepted by one person.',
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: role,
                    decoration: const InputDecoration(
                      labelText: 'Access level',
                    ),
                    items: const [
                      DropdownMenuItem(value: 'member', child: Text('Member')),
                      DropdownMenuItem(value: 'viewer', child: Text('Viewer')),
                      DropdownMenuItem(
                        value: 'builder',
                        child: Text('Builder'),
                      ),
                    ],
                    onChanged: token == null && !creatingInvitation
                        ? (value) => update(() => role = value!)
                        : null,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    switch (role) {
                      'viewer' => 'Can view shared records. Cannot change records, app structure or sharing.',
                      'builder' => 'Can customize and publish the app, manage sharing, and use its allowed actions.',
                      _ => 'Can use the app’s allowed actions. Cannot change app structure or sharing.',
                    },
                    key: const ValueKey('invitation-role-description'),
                  ),
                  const SizedBox(height: 12),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('Invite a specific account (optional)'),
                    subtitle: const Text(
                      'Leave blank to share a single-use link.',
                    ),
                    maintainState: true,
                    children: [
                      TextField(
                        controller: recipient,
                        enabled: token == null && !creatingInvitation,
                        decoration: const InputDecoration(
                          labelText: 'Recipient account ID',
                          helperText: 'They can copy this from Your account.',
                          helperMaxLines: 2,
                        ),
                      ),
                    ],
                  ),
                  if (token != null) SelectableText(invitationLink.toString()),
                  if (failure != null)
                    Text(
                      failure is InvitationLinkConfigurationError
                          ? (failure as InvitationLinkConfigurationError)
                                .message
                          : requestError(failure!),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            if (token == null)
              FilledButton(
                onPressed: creatingInvitation
                    ? null
                    : () async {
                        update(() {
                          creatingInvitation = true;
                          failure = null;
                        });
                        try {
                          // Resolve before creating a token: invalid configuration
                          // must not mint an invitation with an unusable link.
                          final origin = invitationWebOrigin(
                            backendUrl: client.host,
                            currentPage: Uri.base,
                          );
                          final t = await client.apps.invite(
                            widget.appId,
                            role,
                            recipient.text.trim().isEmpty
                                ? null
                                : recipient.text.trim(),
                          );
                          if (context.mounted) {
                            update(() {
                              token = t;
                              invitationLink = origin.replace(
                                queryParameters: {'invite': t},
                              );
                            });
                          }
                        } catch (e) {
                          if (context.mounted) update(() => failure = e);
                        } finally {
                          if (context.mounted) {
                            update(() => creatingInvitation = false);
                          }
                        }
                      },
                child: const Text('Create invitation'),
              ),
            if (token != null)
              TextButton(
                onPressed: () async {
                  await client.apps.revokeInvitation(widget.appId, token!);
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text('Revoke link'),
              ),
            if (token != null)
              FilledButton(
                onPressed: () => Clipboard.setData(
                  ClipboardData(text: invitationLink.toString()),
                ),
                child: const Text('Copy link'),
              ),
          ],
        ),
      ),
    );
    recipient.dispose();
  }

  Future<void> activity() async {
    try {
      final items = await client.apps.activity(widget.appId),
          runs = (manifest!.role == 'owner' || manifest!.role == 'builder')
              ? await client.builder.runs(widget.appId)
              : <ActivityItem>[];
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Activity & reminders'),
          content: SizedBox(
            width: 520,
            child: ListView(
              shrinkWrap: true,
              children: [...runs, ...items]
                  .map(
                    (i) => ListTile(
                      title: Text(i.action),
                      subtitle: Text('${i.status} · ${i.createdAt.toLocal()}'),
                    ),
                  )
                  .toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(requestError(e))));
      }
    }
  }

  Future<void> manage() async {
    final members = await client.apps.members(widget.appId);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('App members'),
        content: SizedBox(
          width: 480,
          child: ListView(
            shrinkWrap: true,
            children: members
                .map(
                  (m) => ListTile(
                    title: SelectableText(m.actorId),
                    subtitle: Text(m.role),
                    trailing: m.role == 'owner'
                        ? null
                        : TextButton(
                            onPressed: () async {
                              await client.apps.setGrant(
                                widget.appId,
                                m.actorId,
                                null,
                              );
                              if (context.mounted) Navigator.pop(context);
                            },
                            child: const Text('Revoke'),
                          ),
                  ),
                )
                .toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = manifest;
    final builder = m?.role == 'owner' || m?.role == 'builder';
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        toolbarHeight: 54,
        title: Row(
          children: [
            Icon(switch (adapter?.spec.icon) {
              'book' => Icons.menu_book_outlined,
              'board' => Icons.view_kanban_outlined,
              'people' => Icons.people_outline,
              'check' => Icons.check_circle_outline,
              _ => Icons.auto_awesome_outlined,
            }, size: 22),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                m?.name ?? 'Opening app…',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        actions: [
          if (m != null && builder && !m.archived)
            IconButton(
              onPressed: _customizing ? null : customize,
              tooltip: 'Customize app',
              icon: const Icon(Icons.tune),
            ),
          if (m != null)
            PopupMenuButton<String>(
              tooltip: 'Mini-app menu',
              icon: const Icon(Icons.more_horiz),
              onSelected: (value) async {
                try {
                  if (value == 'device') await deviceAccess();
                  if (value == 'activity') await activity();
                  if (value == 'share') await share();
                  if (value == 'edit') {
                    await customize();
                  }
                  if (value == 'members') await manage();
                  if (value == 'unpin') {
                    await client.apps.pin(m.appId, false);
                    if (context.mounted) await close();
                  }
                  if (value == 'remix') {
                    if (!await canLeave()) return;
                    final id = await client.apps.remix(m.appId, m.workspaceId);
                    if (context.mounted) {
                      if (widget.onOpenApp != null) {
                        await widget.onOpenApp!(id);
                      } else {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => MiniAppScreen(appId: id),
                          ),
                        );
                      }
                    }
                  }
                  if (value == 'archive') {
                    if (!await canLeave()) return;
                    if (!context.mounted) return;
                    final yes = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Archive this app?'),
                        content: const Text(
                          'Records remain available read-only. Future reminders will be suppressed.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Archive'),
                          ),
                        ],
                      ),
                    );
                    if (yes == true) {
                      await client.apps.archive(m.appId);
                      load();
                    }
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(requestError(e))));
                  }
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'activity',
                  child: Text('Activity & reminders'),
                ),
                if (builder && !m.archived)
                  const PopupMenuItem(
                    value: 'share',
                    child: Text('Invite to app'),
                  ),
                if (requestedDeviceCapabilities(adapter!.spec).isNotEmpty)
                  const PopupMenuItem(
                    value: 'device',
                    child: Text('Device access'),
                  ),
                if (builder && !m.archived)
                  const PopupMenuItem(
                    value: 'edit',
                    child: Text('Customize app'),
                  ),
                if (builder)
                  const PopupMenuItem(
                    value: 'members',
                    child: Text('Manage members'),
                  ),
                const PopupMenuItem(
                  value: 'remix',
                  child: Text('Remix structure only'),
                ),
                const PopupMenuItem(
                  value: 'unpin',
                  child: Text('Remove shortcut'),
                ),
                if (m.role == 'owner' && !m.archived)
                  const PopupMenuItem(
                    value: 'archive',
                    child: Text('Archive app'),
                  ),
              ],
            ),
          Container(height: 20, width: 1, color: const Color(0xffd7ddd7)),
          IconButton(
            onPressed: close,
            tooltip: 'Close mini-app',
            icon: const Icon(Icons.close, size: 20),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off_outlined, size: 36),
                    const SizedBox(height: 16),
                    const Text(
                      'This app or item is unavailable. Try again to check your access.',
                    ),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: load, child: const Text('Retry')),
                  ],
                ),
              ),
            )
          : adapter == null
          ? const Center(child: CircularProgressIndicator())
          : MiniAppRuntime(
              key: ValueKey('${m!.versionId}-${m.archived}'),
              adapter: adapter!,
              controller: controller,
              initialLocation: initialLocation,
              onLocationChanged: widget.onLocationChanged,
            ),
    );
  }
}

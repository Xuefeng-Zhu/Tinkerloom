import 'package:flutter/material.dart';

import 'backend.dart';

const _endpoint = String.fromEnvironment('APPWRITE_ENDPOINT');
const _project = String.fromEnvironment('APPWRITE_PROJECT_ID');
const _function = String.fromEnvironment(
  'APPWRITE_FUNCTION_ID',
  defaultValue: 'appnest-core',
);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BootstrapApp());
}

class BootstrapApp extends StatelessWidget {
  const BootstrapApp({super.key});

  @override
  Widget build(BuildContext context) {
    final configured = _endpoint.isNotEmpty && _project.isNotEmpty;
    return MaterialApp(
      title: 'App builder',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff536653)),
      ),
      home: configured
          ? Home(
              backend: AppwriteBackend(
                endpoint: _endpoint,
                projectId: _project,
                functionId: _function,
              ),
            )
          : const Scaffold(
              body: Center(
                child: Text(
                  'Set APPWRITE_ENDPOINT and APPWRITE_PROJECT_ID to connect.',
                ),
              ),
            ),
    );
  }
}

class Home extends StatefulWidget {
  const Home({required this.backend, super.key});
  final AppBackend backend;

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  String? email;
  String? error;
  bool busy = true;

  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.backend.currentEmail();
      if (mounted) {
        setState(() {
          email = result;
          busy = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          error = 'Could not check your session. Check the connection and try again.';
          busy = false;
        });
      }
    }
  }

  Future<void> _signOut() async {
    try {
      await widget.backend.signOut();
      if (mounted) setState(() => email = null);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not sign out. Please retry.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (busy) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (error != null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(error!),
              TextButton(onPressed: _checkSession, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    if (email == null) {
      return SignIn(backend: widget.backend, onSignedIn: _checkSession);
    }
    return WorkspacePage(
      backend: widget.backend,
      email: email!,
      onSignOut: _signOut,
    );
  }
}

class SignIn extends StatefulWidget {
  const SignIn({required this.backend, required this.onSignedIn, super.key});
  final AppBackend backend;
  final VoidCallback onSignedIn;
  @override
  State<SignIn> createState() => _SignInState();
}

class _SignInState extends State<SignIn> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool busy = false;
  String? error;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> _submit(bool create) async {
    if (email.text.trim().isEmpty || password.text.isEmpty) {
      setState(() => error = 'Enter your email and password.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (create) {
        await widget.backend.signUp(email.text.trim(), password.text);
      } else {
        await widget.backend.signIn(email.text.trim(), password.text);
      }
      if (mounted) widget.onSignedIn();
    } catch (_) {
      if (mounted) {
        setState(
          () => error = create
              ? 'Could not complete sign-up. If the account was created, try signing in.'
              : 'Could not sign in. Check your credentials and connection.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Welcome',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: email,
                  enabled: !busy,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                TextField(
                  controller: password,
                  enabled: !busy,
                  obscureText: true,
                  autofillHints: const [AutofillHints.password],
                  decoration: const InputDecoration(labelText: 'Password'),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: busy ? null : () => _submit(false),
                  child: const Text('Sign in'),
                ),
                TextButton(
                  onPressed: busy ? null : () => _submit(true),
                  child: const Text('Create account'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class WorkspacePage extends StatefulWidget {
  const WorkspacePage({
    required this.backend,
    required this.email,
    required this.onSignOut,
    super.key,
  });
  final AppBackend backend;
  final String email;
  final VoidCallback onSignOut;
  @override
  State<WorkspacePage> createState() => _WorkspacePageState();
}

class _WorkspacePageState extends State<WorkspacePage> {
  List<Workspace> workspaces = [];
  List<MiniApp> apps = [];
  Workspace? selected;
  String? error;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({String? selectId}) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final loaded = await widget.backend.listWorkspaces();
      final desiredId = selectId ?? selected?.id;
      final workspace =
          loaded.where((w) => w.id == desiredId).firstOrNull ??
          (loaded.isEmpty ? null : loaded.first);
      final loadedApps = workspace == null
          ? <MiniApp>[]
          : await widget.backend.listApps(workspace.id);
      if (mounted) {
        setState(() {
          workspaces = loaded;
          selected = workspace;
          apps = loadedApps;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Could not load your workspaces. Please retry.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _create({required bool workspace}) async {
    final id = widget.backend.newId();
    final selectedId = selected?.id;
    final created = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CreateDialog(
        label: workspace ? 'workspace' : 'app',
        save: (name) => workspace
            ? widget.backend.createWorkspace(id, name)
            : widget.backend.createApp(id, selectedId!, name),
      ),
    );
    if (created == true && mounted) {
      await _load(selectId: workspace ? id : selectedId);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Your workspace'),
      actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: busy ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
        TextButton(
          onPressed: busy ? null : widget.onSignOut,
          child: const Text('Sign out'),
        ),
      ],
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.email),
              const SizedBox(height: 16),
              const Text(
                'This early Appwrite build can create and list empty app shells. The builder and shared runtime are still being migrated.',
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: selected?.id,
                      hint: const Text('Choose a workspace'),
                      items: [
                        for (final w in workspaces)
                          DropdownMenuItem(value: w.id, child: Text(w.name)),
                      ],
                      onChanged: busy
                          ? null
                          : (id) {
                              if (id != null) _load(selectId: id);
                            },
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed: busy ? null : () => _create(workspace: true),
                    child: const Text('New workspace'),
                  ),
                ],
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (busy) const LinearProgressIndicator(),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Apps', style: Theme.of(context).textTheme.titleLarge),
                  FilledButton(
                    onPressed: busy || selected == null
                        ? null
                        : () => _create(workspace: false),
                    child: const Text('New app'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: apps.isEmpty
                    ? const Center(
                        child: Text('No apps in this workspace yet.'),
                      )
                    : ListView(
                        children: [
                          for (final app in apps)
                            ListTile(
                              leading: const Icon(Icons.widgets_outlined),
                              title: Text(app.name),
                              subtitle: const Text('Empty app shell'),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class CreateDialog extends StatefulWidget {
  const CreateDialog({required this.label, required this.save, super.key});
  final String label;
  final Future<void> Function(String) save;
  @override
  State<CreateDialog> createState() => _CreateDialogState();
}

class _CreateDialogState extends State<CreateDialog> {
  final name = TextEditingController();
  bool busy = false;
  bool attempted = false;
  String? error;
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (name.text.trim().isEmpty) {
      setState(() => error = 'Enter a name.');
      return;
    }
    setState(() {
      attempted = true;
      busy = true;
      error = null;
    });
    try {
      await widget.save(name.text.trim());
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'The result could not be confirmed. Retry this same request, or close and refresh the list before creating another.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('New ${widget.label}'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: name,
          enabled: !busy && !attempted,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        if (error != null)
          Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!)),
      ],
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context, false),
        child: const Text('Close'),
      ),
      FilledButton(
        onPressed: busy ? null : _save,
        child: Text(attempted ? 'Retry' : 'Create'),
      ),
    ],
  );
}

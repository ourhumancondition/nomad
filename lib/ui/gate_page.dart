import 'package:flutter/material.dart';

import '../state/app_controller.dart';
import 'theme.dart';

enum _AccountMode { create, signIn }

class GatePage extends StatefulWidget {
  const GatePage({super.key, required this.controller});

  final AppController controller;

  @override
  State<GatePage> createState() => _GatePageState();
}

class _GatePageState extends State<GatePage> {
  final _url = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  late _AccountMode _mode;
  bool _editingUrl = true;

  @override
  void initState() {
    super.initState();
    final saved = widget.controller.gateway.savedOrigin();
    if (saved != null) _url.text = saved;
    _mode = widget.controller.preferSignIn
        ? _AccountMode.signIn
        : _AccountMode.create;
    _editingUrl = widget.controller.pendingEndpoint == null;
  }

  @override
  void dispose() {
    _url.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    await widget.controller.checkHealth(_url.text);
    if (!mounted) return;
    final endpoint = widget.controller.pendingEndpoint;
    if (endpoint != null) {
      setState(() {
        _url.text = endpoint.origin.toString();
        _editingUrl = false;
      });
    }
  }

  void _setMode(_AccountMode mode) {
    widget.controller.clearAuthProblems();
    setState(() => _mode = mode);
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final wide = MediaQuery.sizeOf(context).width >= 960;
    final connected = controller.pendingEndpoint;
    final creating = _mode == _AccountMode.create;
    final form = Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your database',
              key: const Key('gate-title'),
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'Each traveler uses their own PocketBase database. Connect that database, then create an account or sign in.',
            ),
            const SizedBox(height: 18),
            Text(
              '1. Connect',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (connected != null && !_editingUrl) ...[
              Container(
                key: const Key('connected-host'),
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFE7F2EE),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFB7D7CC)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.link, color: accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        connected.displayHost,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    TextButton(
                      key: const Key('change-database'),
                      onPressed: controller.busy
                          ? null
                          : () => setState(() => _editingUrl = true),
                      child: const Text('Change'),
                    ),
                  ],
                ),
              ),
            ] else ...[
              TextField(
                key: const Key('instance-url'),
                controller: _url,
                decoration: const InputDecoration(
                  labelText: 'Database address',
                  hintText: 'nomad.pockethost.io',
                ),
                keyboardType: TextInputType.url,
                autocorrect: false,
                textInputAction: TextInputAction.go,
                onSubmitted: controller.busy
                    ? null
                    : (_) {
                        _connect();
                      },
              ),
              const SizedBox(height: 8),
              const Text(
                'A name like nomad.pockethost.io is enough. It is opened as https.',
                style: TextStyle(color: Color(0xFF5C564E)),
              ),
              const SizedBox(height: 12),
              FilledButton(
                key: const Key('connect-database'),
                onPressed: controller.busy ? null : _connect,
                child: Text(controller.busy ? 'Connecting…' : 'Connect'),
              ),
            ],
            if (connected != null) ...[
              const SizedBox(height: 22),
              Text(
                '2. Account',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                'Use the email and password for your account on this database.',
              ),
              const SizedBox(height: 12),
              SegmentedButton<_AccountMode>(
                segments: const [
                  ButtonSegment(
                    value: _AccountMode.create,
                    label: Text('I am new'),
                  ),
                  ButtonSegment(
                    value: _AccountMode.signIn,
                    label: Text('I have an account'),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: controller.busy
                    ? null
                    : (selection) => _setMode(selection.first),
              ),
              const SizedBox(height: 16),
              Text(
                creating ? 'Create your account' : 'Sign in',
                key: Key(creating ? 'account-create-mode' : 'account-signin-mode'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('auth-email'),
                controller: _email,
                decoration: InputDecoration(
                  labelText: 'Email',
                  errorText: controller.fieldErrors['email'],
                ),
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                autofillHints: const [AutofillHints.email],
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('auth-password'),
                controller: _password,
                decoration: InputDecoration(
                  labelText: 'Password',
                  helperText: creating ? 'At least 8 characters.' : null,
                  errorText: controller.fieldErrors['password'],
                ),
                obscureText: true,
                autofillHints: [
                  creating ? AutofillHints.newPassword : AutofillHints.password,
                ],
              ),
              if (creating) ...[
                const SizedBox(height: 12),
                TextField(
                  key: const Key('auth-confirm'),
                  controller: _confirm,
                  decoration: InputDecoration(
                    labelText: 'Confirm password',
                    errorText: controller.fieldErrors['passwordConfirm'],
                  ),
                  obscureText: true,
                  autofillHints: const [AutofillHints.newPassword],
                ),
              ],
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('auth-submit'),
                onPressed: controller.busy
                    ? null
                    : () async {
                        if (creating) {
                          await controller.signUp(
                            _email.text,
                            _password.text,
                            _confirm.text,
                          );
                          if (!mounted || controller.isConnected) return;
                          if (controller.preferSignIn) {
                            setState(() => _mode = _AccountMode.signIn);
                          }
                        } else {
                          await controller.signIn(_email.text, _password.text);
                        }
                      },
                child: Text(
                  controller.busy
                      ? 'Working…'
                      : creating
                      ? 'Create account'
                      : 'Sign in',
                ),
              ),
            ],
            if (controller.errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                controller.errorMessage!,
                key: const Key('auth-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
    final example = Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Fictional example',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'A made-up year, kept in this browser tab. It is not an account and it is not written to a database.',
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              key: const Key('open-example'),
              onPressed: controller.busy ? null : controller.openExample,
              child: const Text('Review the example dataset'),
            ),
          ],
        ),
      ),
    );
    final intro = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Nomadic Residence',
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
            color: ink,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.8,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Count the countries you wake up in. Layovers and nights in the air stay in their own totals.',
          style: TextStyle(fontSize: 18, height: 1.4, color: ink),
        ),
      ],
    );
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        intro,
        const SizedBox(height: 20),
        form,
        const SizedBox(height: 16),
        example,
      ],
    );
    return Scaffold(
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: wide ? 720 : 560),
              child: column,
            ),
          ),
        ),
      ),
    );
  }
}

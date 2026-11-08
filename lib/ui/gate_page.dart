import 'package:flutter/material.dart';

import '../state/app_controller.dart';
import 'theme.dart';

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
  String? _formError;

  @override
  void initState() {
    super.initState();
    final saved = widget.controller.gateway.savedOrigin();
    if (saved != null) _url.text = saved;
  }

  @override
  void dispose() {
    _url.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _health() async {
    final failure = await widget.controller.checkHealth(_url.text);
    if (!mounted) return;
    setState(() => _formError = failure);
  }

  Future<void> _auth(Future<String?> Function() action) async {
    final failure = await action();
    if (!mounted) return;
    setState(() => _formError = failure);
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final wide = MediaQuery.sizeOf(context).width >= 960;
    final ready = controller.pendingEndpoint != null;
    final body = Column(
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
          'A calendar of the countries you wake up in, with layovers and nights in the air kept beside that count.',
          style: TextStyle(fontSize: 18, height: 1.4, color: ink),
        ),
        const SizedBox(height: 20),
        const _Point(
          title: 'One database per traveler',
          body: 'Travel rows go to the PocketBase instance you register. There is no shared travel collection behind this screen.',
        ),
        const _Point(
          title: 'Unknown days stay empty',
          body: 'Gaps, overlaps, bookings, and inferences stay visible and out of the actual total until you say otherwise.',
        ),
        const _Point(
          title: 'Counts are arithmetic',
          body: 'The year total is a day count under your rules. It is not tax, immigration, or legal advice.',
        ),
        const SizedBox(height: 8),
        FilledButton(
          key: const Key('open-example'),
          onPressed: controller.busy ? null : controller.openExample,
          child: const Text('Review the example dataset'),
        ),
        const SizedBox(height: 8),
        const Text(
          'The example is fictional, stays in this browser tab, and is not written to PocketBase.',
          style: TextStyle(color: Color(0xFF5C564E)),
        ),
      ],
    );
    final form = Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Register a database',
              key: const Key('gate-title'),
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'No travel database is open. Enter the https origin of a PocketBase instance that stores only this traveler, then sign in there.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _url,
              decoration: const InputDecoration(
                labelText: 'Instance URL',
                hintText: 'https://your-instance.pockethost.io',
              ),
              keyboardType: TextInputType.url,
              autocorrect: false,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: controller.busy ? null : _health,
              child: Text(controller.busy ? 'Checking…' : 'Check health'),
            ),
            if (ready) ...[
              const SizedBox(height: 16),
              Text(
                'Signing in to ${controller.pendingEndpoint!.displayHost}.',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _email,
                decoration: const InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                decoration: const InputDecoration(labelText: 'Password'),
                obscureText: true,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton(
                    onPressed: controller.busy
                        ? null
                        : () => _auth(
                            () =>
                                controller.signIn(_email.text, _password.text),
                          ),
                    child: const Text('Sign in'),
                  ),
                  OutlinedButton(
                    onPressed: controller.busy
                        ? null
                        : () => _auth(
                            () =>
                                controller.signUp(_email.text, _password.text),
                          ),
                    child: const Text('Create account on this instance'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Account creation uses this instance’s users collection. If sign-up is closed, create the user in that PocketBase dashboard and then sign in here.',
                style: TextStyle(color: Color(0xFF5C564E)),
              ),
            ],
            if (_formError != null) ...[
              const SizedBox(height: 12),
              Text(
                _formError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (controller.errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(controller.errorMessage!),
            ],
            if (controller.statusMessage != null && _formError == null) ...[
              const SizedBox(height: 12),
              Text(controller.statusMessage!),
            ],
          ],
        ),
      ),
    );
    return Scaffold(
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1080),
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: body),
                        const SizedBox(width: 28),
                        Expanded(child: form),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [body, const SizedBox(height: 24), form],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(
            body,
            style: const TextStyle(height: 1.35, color: Color(0xFF3F3A34)),
          ),
        ],
      ),
    );
  }
}

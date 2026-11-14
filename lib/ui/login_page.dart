import 'package:flutter/material.dart';

import '../data/instance_endpoint.dart';
import '../state/app_controller.dart';
import 'auth_chrome.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.controller,
    required this.onSignUp,
  });

  final AppController controller;
  final VoidCallback onSignUp;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  late final TextEditingController _email;
  final _password = TextEditingController();

  @override
  void initState() {
    super.initState();
    _email = TextEditingController(
      text: widget.controller.gateway.savedEmail() ?? '',
    );
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final controller = widget.controller;
    if (controller.pendingEndpoint == null) {
      final saved = controller.gateway.savedOrigin() ?? defaultInstanceUrl;
      if (controller.useServer(saved) != null) return;
    }
    final failure = await controller.signIn(_email.text, _password.text);
    if (failure == null) savePasswordToBrowser();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return AuthScaffold(
      example: OutlinedButton(
        key: const Key('open-example'),
        onPressed: controller.busy ? null : controller.openExample,
        child: const Text('Look at a made-up example'),
      ),
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sign in',
              key: const Key('gate-title'),
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            EmailField(controller: _email, errors: controller.fieldErrors),
            const SizedBox(height: 12),
            PasswordField(
              controller: _password,
              errors: controller.fieldErrors,
              newPassword: false,
              onSubmitted: controller.busy ? null : (_) => _submit(),
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('auth-submit'),
              onPressed: controller.busy ? null : _submit,
              child: Text(controller.busy ? 'Signing in…' : 'Sign in'),
            ),
            AuthErrorText(message: controller.errorMessage),
            const SizedBox(height: 8),
            TextButton(
              key: const Key('go-to-signup'),
              onPressed: controller.busy ? null : widget.onSignUp,
              child: const Text("Don't have an account? Sign up"),
            ),
            ServerEditor(controller: controller),
          ],
        ),
      ),
    );
  }
}

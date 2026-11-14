import 'package:flutter/material.dart';

import '../data/instance_endpoint.dart';
import '../state/app_controller.dart';
import 'auth_chrome.dart';

class SignupPage extends StatefulWidget {
  const SignupPage({
    super.key,
    required this.controller,
    required this.onSignIn,
  });

  final AppController controller;
  final VoidCallback onSignIn;

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  late final TextEditingController _email;
  final _password = TextEditingController();
  final _confirm = TextEditingController();

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
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final controller = widget.controller;
    if (controller.pendingEndpoint == null) {
      final saved = controller.gateway.savedOrigin() ?? defaultInstanceUrl;
      if (controller.useServer(saved) != null) return;
    }
    final failure = await controller.signUp(
      _email.text,
      _password.text,
      _confirm.text,
    );
    if (failure == null) savePasswordToBrowser();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return AuthScaffold(
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Create an account',
              key: const Key('signup-title'),
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            EmailField(controller: _email, errors: controller.fieldErrors),
            const SizedBox(height: 12),
            PasswordField(
              controller: _password,
              errors: controller.fieldErrors,
              newPassword: true,
              helper: 'At least 8 characters.',
            ),
            const SizedBox(height: 12),
            PasswordField(
              controller: _confirm,
              errors: controller.fieldErrors,
              newPassword: true,
              label: 'Confirm password',
              fieldKey: const Key('auth-confirm'),
              errorKey: 'passwordConfirm',
              onSubmitted: controller.busy ? null : (_) => _submit(),
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('auth-submit'),
              onPressed: controller.busy ? null : _submit,
              child: Text(
                controller.busy ? 'Creating account…' : 'Create account',
              ),
            ),
            AuthErrorText(message: controller.errorMessage),
            const SizedBox(height: 8),
            TextButton(
              key: const Key('go-to-login'),
              onPressed: controller.busy
                  ? null
                  : () {
                      controller.clearAuthProblems();
                      widget.onSignIn();
                    },
              child: const Text('Already have an account? Sign in'),
            ),
            ServerEditor(controller: controller),
          ],
        ),
      ),
    );
  }
}

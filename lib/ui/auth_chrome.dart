import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/instance_endpoint.dart';
import '../state/app_controller.dart';

class AuthScaffold extends StatelessWidget {
  const AuthScaffold({super.key, required this.child, this.example});

  final Widget child;
  final Widget? example;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 960;
    return Scaffold(
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: wide ? 480 : 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Nomadic Residence',
                    style: Theme.of(context).textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'See how many days you stayed in each country.',
                    style: TextStyle(fontSize: 16, height: 1.4),
                  ),
                  const SizedBox(height: 20),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(22),
                      child: child,
                    ),
                  ),
                  if (example != null) ...[
                    const SizedBox(height: 16),
                    example!,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AuthErrorText extends StatelessWidget {
  const AuthErrorText({super.key, required this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final text = message;
    if (text == null || text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(
        text,
        key: const Key('auth-error'),
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    );
  }
}

class ServerEditor extends StatefulWidget {
  const ServerEditor({super.key, required this.controller});

  final AppController controller;

  @override
  State<ServerEditor> createState() => _ServerEditorState();
}

class _ServerEditorState extends State<ServerEditor> {
  late final TextEditingController _url;
  bool _open = false;
  String? _problem;

  @override
  void initState() {
    super.initState();
    _url = TextEditingController(text: _current());
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  String _current() {
    return widget.controller.gateway.savedOrigin() ??
        widget.controller.pendingEndpoint?.origin.toString() ??
        defaultInstanceUrl;
  }

  void _save() {
    final failure = widget.controller.useServer(_url.text);
    setState(() {
      _problem = failure;
      if (failure == null) {
        _url.text =
            widget.controller.pendingEndpoint?.origin.toString() ?? _url.text;
        _open = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_open) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          key: const Key('change-server'),
          onPressed: widget.controller.busy
              ? null
              : () => setState(() {
                  _url.text = _current();
                  _problem = null;
                  _open = true;
                }),
          child: const Text('Change server'),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const Key('instance-url'),
          controller: _url,
          decoration: const InputDecoration(
            labelText: 'Server',
            hintText: defaultInstanceUrl,
          ),
          keyboardType: TextInputType.url,
          autocorrect: false,
          enableSuggestions: false,
          autofillHints: const [AutofillHints.url],
          textInputAction: TextInputAction.done,
          onSubmitted: widget.controller.busy ? null : (_) => _save(),
        ),
        if (_problem != null) ...[
          const SizedBox(height: 8),
          Text(
            _problem!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 8),
        TextButton(
          key: const Key('save-server'),
          onPressed: widget.controller.busy ? null : _save,
          child: const Text('Save server'),
        ),
      ],
    );
  }
}

class EmailField extends StatelessWidget {
  const EmailField({super.key, required this.controller, required this.errors});

  final TextEditingController controller;
  final Map<String, String> errors;

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: const Key('auth-email'),
      controller: controller,
      decoration: InputDecoration(
        labelText: 'Email',
        errorText: errors['email'],
      ),
      keyboardType: TextInputType.emailAddress,
      textCapitalization: TextCapitalization.none,
      autocorrect: false,
      enableSuggestions: false,
      autofillHints: const [AutofillHints.username, AutofillHints.email],
      textInputAction: TextInputAction.next,
    );
  }
}

class PasswordField extends StatelessWidget {
  const PasswordField({
    super.key,
    required this.controller,
    required this.errors,
    required this.newPassword,
    this.label = 'Password',
    this.helper,
    this.fieldKey = const Key('auth-password'),
    this.errorKey = 'password',
    this.onSubmitted,
  });

  final TextEditingController controller;
  final Map<String, String> errors;
  final bool newPassword;
  final String label;
  final String? helper;
  final Key fieldKey;
  final String errorKey;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: fieldKey,
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        errorText: errors[errorKey],
      ),
      obscureText: true,
      enableSuggestions: false,
      autocorrect: false,
      autofillHints: [
        newPassword ? AutofillHints.newPassword : AutofillHints.password,
      ],
      textInputAction: onSubmitted == null
          ? TextInputAction.next
          : TextInputAction.done,
      onSubmitted: onSubmitted,
    );
  }
}

void savePasswordToBrowser() {
  TextInput.finishAutofillContext(shouldSave: true);
}

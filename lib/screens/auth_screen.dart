import 'package:flutter/material.dart';

import '../app_state.dart';
import '../config.dart';
import '../models.dart';
import '../reviews_api.dart';
import 'ui.dart';

/// Log in or register, or try the shared demo account. Users belong to the key, so
/// anyone can register freely; there is no email check unless you register the email
/// address your key belongs to (then a code is emailed, see the README).
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.state});

  final AppState state;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _register = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() => _run(() {
        final api = widget.state.api;
        // POST /api/users/register  or  POST /api/users/login
        return _register
            ? api.register(name: _name.text.trim(), email: _email.text.trim(), password: _password.text)
            : api.login(email: _email.text.trim(), password: _password.text);
      });

  /// One click: log in as the shared demo user (POST /api/users/login).
  Future<void> _demo() => _run(() => widget.state.api.login(email: demoEmail, password: demoPassword));

  Future<void> _run(Future<AuthResult> Function() call) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await call();
      if (result.token == null) {
        if (mounted) setState(() => _error = result.message);
        return;
      }
      widget.state.loggedInAs(result.name.isEmpty ? 'you' : result.name);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      // The demo key holds only 25 users, so on a busy demo registering answers 403.
      final demoFull = _register && e is ApiException && e.statusCode == 403;
      if (mounted) setState(() => _error = demoFull ? demoFullMessage : describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_register ? 'Register' : 'Log in')),
      body: Centered(
        child: ListView(padding: const EdgeInsets.all(24), children: [
          const DemoNotice(),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: _busy ? null : _demo,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Try the demo account'),
            ),
          ),
          const SizedBox(height: 16),
          if (_register) ...[
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder())),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: true,
            decoration: InputDecoration(
              labelText: 'Password',
              border: const OutlineInputBorder(),
              helperText: _register ? 'At least 8 characters' : null,
            ),
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          const SizedBox(height: 16),
          Wrap(spacing: 12, children: [
            FilledButton(onPressed: _busy ? null : _submit, child: Text(_register ? 'Register' : 'Log in')),
            TextButton(
              onPressed: () => setState(() => _register = !_register),
              child: Text(_register ? 'I already have an account' : 'Create an account'),
            ),
          ]),
        ]),
      ),
    );
  }
}

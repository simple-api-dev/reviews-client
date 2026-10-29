import 'package:flutter/material.dart';

import '../app_state.dart';
import 'ui.dart';

/// Screen 3: log in or register. Users belong to your key, so you can
/// register freely; there is no email check unless you register the email
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

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = widget.state.api;
      // POST /api/users/register  or  POST /api/users/login
      final result = _register
          ? await api.register(name: _name.text.trim(), email: _email.text.trim(), password: _password.text)
          : await api.login(email: _email.text.trim(), password: _password.text);
      if (result.token == null) {
        if (mounted) setState(() => _error = result.message);
        return;
      }
      widget.state.loggedInAs(result.name.isEmpty ? 'you' : result.name);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
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
            decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          const SizedBox(height: 16),
          Row(children: [
            FilledButton(onPressed: _busy ? null : _submit, child: Text(_register ? 'Register' : 'Log in')),
            const SizedBox(width: 12),
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

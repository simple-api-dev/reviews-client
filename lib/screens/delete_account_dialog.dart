import 'package:flutter/material.dart';

import '../app_state.dart';
import 'ui.dart';

/// "Delete my account": DELETE /api/users/me with the current password in the
/// body. The checkbox adds `purge=true`, which also deletes your reviews,
/// your comments, comments on your reviews and your votes. Pops `true` once
/// the account is gone.
class DeleteAccountDialog extends StatefulWidget {
  const DeleteAccountDialog({super.key, required this.state});

  final AppState state;

  @override
  State<DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<DeleteAccountDialog> {
  final _password = TextEditingController();
  bool _purge = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.state.deleteAccount(password: _password.text, purge: _purge);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      // 403 "Wrong password.", 422 missing password, or a 401 if the session ended
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Delete my account'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('This cannot be undone. Enter your password to confirm.'),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
            onSubmitted: (_) => _busy ? null : _delete(),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _purge,
            onChanged: _busy ? null : (v) => setState(() => _purge = v ?? false),
            title: const Text('Also delete my reviews and comments'),
            subtitle: const Text('Otherwise they stay on the site under your name.'),
          ),
          if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ]),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: _busy ? null : _delete, child: const Text('Delete account')),
      ],
    );
  }
}

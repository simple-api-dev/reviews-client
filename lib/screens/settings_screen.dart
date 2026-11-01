import 'package:flutter/material.dart';

import '../app_state.dart';
import '../config.dart';
import '../open_url.dart';
import '../reviews_api.dart' show apiHost;
import 'ui.dart';

/// Settings: use your own SimpleAPI key instead of the demo's. It is checked
/// with one real call (GET /api/subjects) and then kept only in this
/// browser's localStorage.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.state, required this.openUrl});

  final AppState state;
  final UrlOpener openUrl;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final key = _controller.text.trim();
    if (key.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.state.useOwnKey(key);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final current = state.usingOwnKey
        ? 'You are using your own key.'
        : state.hasBuildKey
        ? 'You are using the shared demo key.'
        : 'No key is configured.';
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Centered(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'Use your own key',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              '$current Your key is stored only in this browser (localStorage) and sent only to $apiHost.',
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => widget.openUrl(getKeyUrl),
              child: const Text('Get a free key'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              decoration: InputDecoration(
                labelText: 'API key',
                border: const OutlineInputBorder(),
                errorText: _error,
              ),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: Text(_busy ? 'Checking...' : 'Save key'),
                ),
                const SizedBox(width: 12),
                if (state.usingOwnKey)
                  TextButton(
                    onPressed: () {
                      state.useBuildKey();
                      Navigator.of(context).pop();
                    },
                    child: const Text('Remove my key'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

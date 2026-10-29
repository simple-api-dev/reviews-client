import 'package:flutter/material.dart';

import '../app_state.dart';
import 'ui.dart';

/// Screen 1: paste your SimpleApi key. It is checked with one real call
/// (GET /api/subjects) and then kept only in this browser's localStorage.
class KeyScreen extends StatefulWidget {
  const KeyScreen({super.key, required this.state});

  final AppState state;

  @override
  State<KeyScreen> createState() => _KeyScreenState();
}

class _KeyScreenState extends State<KeyScreen> {
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
      // GET /api/subjects - a cheap call that proves the key is valid.
      await widget.state.checkAndSaveKey(key);
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reviews API sample')),
      body: Centered(
        child: ListView(padding: const EdgeInsets.all(24), children: [
          const Text('Paste your SimpleApi key', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text(
            'Get a free key at keys.simpleapi.dev (use the product URL https://reviews.simpleapi.dev). '
            'The key is stored only in this browser (localStorage) and sent only to reviews.simpleapi.dev.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            decoration: InputDecoration(labelText: 'API key', border: const OutlineInputBorder(), errorText: _error),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(onPressed: _busy ? null : _save, child: Text(_busy ? 'Checking...' : 'Save key')),
          ),
        ]),
      ),
    );
  }
}

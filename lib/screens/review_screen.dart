import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import 'reviews_screen.dart' show ensureLoggedIn;
import 'ui.dart';

/// One review and its comments, with a box to add a comment.
class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key, required this.state, required this.review});

  final AppState state;
  final Review review;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  final _text = TextEditingController();
  late Future<List<Comment>> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  // GET /api/reviews/{id}/comments
  Future<List<Comment>> _load() => widget.state.api.listComments(widget.review.id);

  void _reload() => setState(() {
        _future = _load();
      });

  Future<void> _send() async {
    final body = _text.text.trim();
    if (body.isEmpty) return;
    if (!await ensureLoggedIn(context, widget.state)) return;
    setState(() => _busy = true);
    try {
      // POST /api/reviews/{id}/comments
      await widget.state.api.addComment(widget.review.id, body);
      _text.clear();
      _reload();
    } catch (e) {
      if (mounted) showSnack(context, describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.review;
    return Scaffold(
      appBar: AppBar(title: Text(r.subject)),
      body: Centered(
        child: Column(children: [
          Expanded(
            child: FutureBuilder<List<Comment>>(
              future: _future,
              builder: (context, snap) {
                final header = Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Stars(r.rating),
                    Text(r.title, style: Theme.of(context).textTheme.titleLarge),
                    Text('by ${r.author}', style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 8),
                    Text(r.body),
                    const Divider(height: 32),
                    const Text('Comments', style: TextStyle(fontWeight: FontWeight.w600)),
                  ]),
                );
                if (snap.hasError) return ListView(children: [header, ErrorView(error: snap.error!, onRetry: _reload)]);
                if (!snap.hasData) return ListView(children: [header, const Center(child: CircularProgressIndicator())]);
                final comments = snap.data!;
                return ListView(children: [
                  header,
                  if (comments.isEmpty) const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('No comments yet.')),
                  for (final c in comments) ListTile(title: Text(c.body), subtitle: Text(c.author)),
                ]);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _text,
                  decoration: const InputDecoration(labelText: 'Add a comment', border: OutlineInputBorder()),
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: _busy ? null : _send, child: const Text('Send')),
            ]),
          ),
        ]),
      ),
    );
  }
}

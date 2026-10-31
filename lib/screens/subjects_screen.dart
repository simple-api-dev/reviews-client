import 'package:flutter/material.dart';

import '../app_state.dart';
import '../config.dart';
import '../models.dart';
import '../open_url.dart';
import 'auth_screen.dart';
import 'reviews_screen.dart';
import 'settings_screen.dart';
import 'ui.dart';

/// Screen 2: browse subjects (things that have reviews).
class SubjectsScreen extends StatefulWidget {
  const SubjectsScreen({super.key, required this.state, required this.openUrl});

  final AppState state;
  final UrlOpener openUrl;

  @override
  State<SubjectsScreen> createState() => _SubjectsScreenState();
}

class _SubjectsScreenState extends State<SubjectsScreen> {
  final _search = TextEditingController();
  late Future<List<Subject>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.state.hasKey ? _load() : Future.value(const []);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  // GET /api/subjects?q=...
  Future<List<Subject>> _load() => widget.state.api.listSubjects(q: _search.text.trim());

  void _reload() => setState(() {
        _future = _load();
      });

  void _open(String subject) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ReviewsScreen(state: widget.state, subject: subject),
    ));
    if (mounted) _reload(); // counts may have changed
  }

  Future<void> _newSubject() async {
    final c = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Review something new'),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Subject id or slug, e.g. blue-bike'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, c.text.trim()), child: const Text('Open')),
        ],
      ),
    );
    c.dispose();
    if (name != null && name.isNotEmpty && mounted) _open(name);
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: const Text('Subjects'),
          actions: [
            if (!state.hasKey)
              const SizedBox.shrink()
            else if (state.loggedIn) ...[
              Center(child: Text('Hi, ${state.userName ?? 'you'}')),
              TextButton(onPressed: state.logout, child: const Text('Log out')),
            ] else
              TextButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AuthScreen(state: state))),
                child: const Text('Log in / Register'),
              ),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => SettingsScreen(state: state, openUrl: widget.openUrl)),
              ),
              child: const Text('Settings'),
            ),
          ],
        ),
        floatingActionButton: state.hasKey
            ? FloatingActionButton.extended(
                onPressed: _newSubject,
                icon: const Icon(Icons.add),
                label: const Text('Review something new'),
              )
            : null,
        body: !state.hasKey
            ? _NoKey(openUrl: widget.openUrl)
            : Centered(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _search,
                decoration: const InputDecoration(
                  labelText: 'Search subjects (starts with)',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _reload(),
              ),
            ),
            Expanded(
              child: FutureBuilder<List<Subject>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.hasError) return ErrorView(error: snap.error!, onRetry: _reload);
                  if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                  final subjects = snap.data!;
                  if (subjects.isEmpty) {
                    return const Center(child: Text('No subjects yet. Use "Review something new" to add the first review.'));
                  }
                  return ListView.separated(
                    itemCount: subjects.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final s = subjects[i];
                      return ListTile(
                        title: Text(s.name),
                        subtitle: Text('${s.count} review${s.count == 1 ? '' : 's'}'),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          Stars(s.average),
                          const SizedBox(width: 6),
                          Text(s.average.toStringAsFixed(1)),
                        ]),
                        onTap: () => _open(s.name),
                      );
                    },
                  );
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Shown when the site was built without a demo key and the visitor has not
/// saved their own.
class _NoKey extends StatelessWidget {
  const _NoKey({required this.openUrl});

  final UrlOpener openUrl;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('This demo has no key configured', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text('Get a free SimpleApi key, then paste it under Settings to try the app.', textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(onPressed: () => openUrl(getKeyUrl), child: const Text('Get a free key')),
        ]),
      ),
    );
  }
}

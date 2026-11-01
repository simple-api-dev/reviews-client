import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../open_url.dart';
import 'auth_screen.dart';
import 'delete_account_dialog.dart';
import 'reviews_screen.dart';
import 'ui.dart';

/// Browse subjects (things that have reviews).
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
    _future = _load();
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

  Future<void> _deleteAccount() async {
    final deleted = await showDialog<bool>(
      context: context,
      builder: (_) => DeleteAccountDialog(state: widget.state),
    );
    if (deleted == true && mounted) {
      showSnack(context, 'Your account was deleted.');
      _reload(); // with purge the counts changed
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          leading: backToSimpleApi(widget.openUrl),
          title: const Text('SimpleAPI Reviews'),
          actions: [
            if (state.loggedIn)
              PopupMenuButton<VoidCallback>(
                icon: const Icon(Icons.account_circle),
                tooltip: 'Hi, ${state.userName ?? 'you'}',
                onSelected: (action) => action(),
                itemBuilder: (_) => [
                  PopupMenuItem(enabled: false, child: Text('Hi, ${state.userName ?? 'you'}')),
                  PopupMenuItem(value: state.logout, child: const Text('Log out')),
                  if (!state.isDemoUser) PopupMenuItem(value: _deleteAccount, child: const Text('Delete my account')),
                ],
              )
            else
              TextButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AuthScreen(state: state))),
                child: const Text('Log in'),
              ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _newSubject,
          icon: const Icon(Icons.add),
          label: const Text('Review something new'),
        ),
        body: Centered(
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
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('No subjects yet. Use "Review something new" to add the first review.', textAlign: TextAlign.center),
                      ),
                    );
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

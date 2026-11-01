import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import 'auth_screen.dart';
import 'review_screen.dart';
import 'ui.dart';

/// Writing and voting need a logged-in user: send them to the login screen
/// first and report whether they ended up logged in.
Future<bool> ensureLoggedIn(BuildContext context, AppState state) async {
  if (state.loggedIn) return true;
  await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => AuthScreen(state: state)));
  return state.loggedIn;
}

/// The reviews of one subject, with the average, star breakdown,
/// voting and a form to write your own review.
class ReviewsScreen extends StatefulWidget {
  const ReviewsScreen({super.key, required this.state, required this.subject});

  final AppState state;
  final String subject;

  @override
  State<ReviewsScreen> createState() => _ReviewsScreenState();
}

class _ReviewsScreenState extends State<ReviewsScreen> {
  late Future<ReviewPage> _future;
  String _sort = 'newest';

  /// Latest vote counters / vote per review id, applied over the loaded list.
  final _votes = <int, VoteResult>{};

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  // GET /api/reviews?subject=...&sort=...
  Future<ReviewPage> _load() => widget.state.api.listReviews(subject: widget.subject, sort: _sort);

  void _reload() => setState(() {
        _votes.clear();
        _future = _load();
      });

  Future<void> _vote(Review r, {required bool helpful}) async {
    if (!await ensureLoggedIn(context, widget.state)) return;
    try {
      final current = _votes[r.id];
      final want = helpful ? 'helpful' : 'unhelpful';
      // Clicking your current vote again takes it back.
      if (current != null && current.yourVote == want) {
        await widget.state.api.removeVote(r.id); // DELETE /api/reviews/{id}/vote
        setState(() => _votes[r.id] = current.withoutVote());
        return;
      }
      final result = await widget.state.api.vote(r.id, helpful: helpful); // POST /api/reviews/{id}/helpful|unhelpful
      setState(() => _votes[r.id] = result);
    } catch (e) {
      if (mounted) showSnack(context, describeError(e));
    }
  }

  Future<void> _write() async {
    if (!await ensureLoggedIn(context, widget.state)) return;
    if (!mounted) return;
    final posted = await showDialog<bool>(
      context: context,
      builder: (_) => _WriteReviewDialog(state: widget.state, subject: widget.subject),
    );
    if (posted == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.subject)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _write,
        icon: const Icon(Icons.rate_review),
        label: const Text('Write a review'),
      ),
      body: Centered(
        child: FutureBuilder<ReviewPage>(
          future: _future,
          builder: (context, snap) {
            if (snap.hasError) return ErrorView(error: snap.error!, onRetry: _reload);
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final page = snap.data!;
            return ListView(padding: const EdgeInsets.only(bottom: 88), children: [
              _SummaryCard(summary: page.summary),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(children: [
                  const Text('Sort: '),
                  DropdownButton<String>(
                    value: _sort,
                    items: const [
                      DropdownMenuItem(value: 'newest', child: Text('Newest')),
                      DropdownMenuItem(value: 'oldest', child: Text('Oldest')),
                      DropdownMenuItem(value: 'rating_desc', child: Text('Highest rated')),
                      DropdownMenuItem(value: 'rating_asc', child: Text('Lowest rated')),
                      DropdownMenuItem(value: 'helpful', child: Text('Most helpful')),
                    ],
                    onChanged: (v) {
                      _sort = v ?? 'newest';
                      _reload();
                    },
                  ),
                ]),
              ),
              if (page.reviews.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('No reviews yet. Be the first!')),
              for (final r in page.reviews) _ReviewTile(
                review: r,
                vote: _votes[r.id],
                onHelpful: () => _vote(r, helpful: true),
                onUnhelpful: () => _vote(r, helpful: false),
                onOpen: () async {
                  await Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => ReviewScreen(state: widget.state, review: r),
                  ));
                  if (mounted) _reload(); // comment count may have changed
                },
              ),
            ]);
          },
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});

  final ReviewSummary summary;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Column(children: [
            Text(summary.average.toStringAsFixed(1), style: Theme.of(context).textTheme.displaySmall),
            Stars(summary.average),
            Text('${summary.count} review${summary.count == 1 ? '' : 's'}'),
          ]),
          const SizedBox(width: 24),
          Expanded(
            child: Column(children: [
              for (var stars = 5; stars >= 1; stars--)
                Row(children: [
                  SizedBox(width: 24, child: Text('$stars★')),
                  Expanded(
                    child: LinearProgressIndicator(
                      value: summary.count == 0 ? 0 : (summary.distribution[stars] ?? 0) / summary.count,
                    ),
                  ),
                  SizedBox(width: 32, child: Text('${summary.distribution[stars] ?? 0}', textAlign: TextAlign.end)),
                ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({
    required this.review,
    required this.vote,
    required this.onHelpful,
    required this.onUnhelpful,
    required this.onOpen,
  });

  final Review review;
  final VoteResult? vote;
  final VoidCallback onHelpful;
  final VoidCallback onUnhelpful;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final helpful = vote?.helpful ?? review.helpful;
    final unhelpful = vote?.unhelpful ?? review.unhelpful;
    final mine = vote?.yourVote;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Stars(review.rating), const SizedBox(width: 8), Expanded(child: Text(review.title, style: const TextStyle(fontWeight: FontWeight.w600)))]),
            Text('by ${review.author}', style: Theme.of(context).textTheme.bodySmall),
            if (review.body.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(review.body)),
            Row(children: [
              TextButton.icon(
                onPressed: onHelpful,
                icon: Icon(mine == 'helpful' ? Icons.thumb_up : Icons.thumb_up_outlined, size: 18),
                label: Text('Helpful $helpful'),
              ),
              TextButton.icon(
                onPressed: onUnhelpful,
                icon: Icon(mine == 'unhelpful' ? Icons.thumb_down : Icons.thumb_down_outlined, size: 18),
                label: Text('Not helpful $unhelpful'),
              ),
              const Spacer(),
              Text('${review.commentCount} comment${review.commentCount == 1 ? '' : 's'}'),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _WriteReviewDialog extends StatefulWidget {
  const _WriteReviewDialog({required this.state, required this.subject});

  final AppState state;
  final String subject;

  @override
  State<_WriteReviewDialog> createState() => _WriteReviewDialogState();
}

class _WriteReviewDialogState extends State<_WriteReviewDialog> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  int _rating = 5;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // POST /api/reviews
      await widget.state.api.createReview(subject: widget.subject, rating: _rating, title: _title.text.trim(), body: _body.text.trim());
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Review ${widget.subject}'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            const Text('Stars: '),
            DropdownButton<int>(
              value: _rating,
              items: [for (var i = 5; i >= 1; i--) DropdownMenuItem(value: i, child: Text('$i'))],
              onChanged: (v) => setState(() => _rating = v ?? 5),
            ),
          ]),
          TextField(controller: _title, decoration: const InputDecoration(labelText: 'Title')),
          TextField(controller: _body, decoration: const InputDecoration(labelText: 'Review'), maxLines: 4),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _busy ? null : _post, child: const Text('Post')),
      ],
    );
  }
}

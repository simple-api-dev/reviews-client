/// Plain data classes for the Reviews API responses.
///
/// Parsing is deliberately forgiving (missing fields fall back to defaults) so
/// a small change in the API does not crash the sample.
library;

int _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
double _double(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
String _str(Object? v) => v == null ? '' : '$v';

/// An item that has reviews (an id or slug chosen by whoever posted the first
/// review), with its review count and average rating.
class Subject {
  const Subject({required this.name, required this.count, required this.average});

  factory Subject.fromJson(Map<String, dynamic> j) => Subject(
        name: _str(j['subject']),
        count: _int(j['count']),
        average: _double(j['average']),
      );

  final String name;
  final int count;
  final double average;
}

class Review {
  const Review({
    required this.id,
    required this.subject,
    required this.author,
    required this.rating,
    required this.title,
    required this.body,
    required this.helpful,
    required this.unhelpful,
    required this.commentCount,
    required this.reviewedAt,
  });

  factory Review.fromJson(Map<String, dynamic> j) => Review(
        id: _int(j['id']),
        subject: _str(j['subject']),
        author: _str(j['author']),
        rating: _int(j['rating']),
        title: _str(j['title']),
        body: _str(j['body']),
        helpful: _int(j['helpful_counter']),
        unhelpful: _int(j['unhelpful_counter']),
        commentCount: _int(j['comment_count']),
        reviewedAt: _str(j['reviewed_at']),
      );

  final int id;
  final String subject;
  final String author;
  final int rating;
  final String title;
  final String body;
  final int helpful;
  final int unhelpful;
  final int commentCount;
  final String reviewedAt;

  Review withCounters(int helpful, int unhelpful) => Review(
        id: id,
        subject: subject,
        author: author,
        rating: rating,
        title: title,
        body: body,
        helpful: helpful,
        unhelpful: unhelpful,
        commentCount: commentCount,
        reviewedAt: reviewedAt,
      );
}

class Comment {
  const Comment({required this.id, required this.author, required this.body, required this.commentedAt});

  factory Comment.fromJson(Map<String, dynamic> j) => Comment(
        id: _int(j['id']),
        author: _str(j['author']),
        body: _str(j['body']),
        commentedAt: _str(j['commented_at']),
      );

  final int id;
  final String author;
  final String body;
  final String commentedAt;
}

/// Average rating plus how many reviews gave 1..5 stars.
class ReviewSummary {
  const ReviewSummary({required this.count, required this.average, required this.distribution});

  factory ReviewSummary.fromJson(Map<String, dynamic>? j) {
    final dist = <int, int>{};
    final raw = j?['distribution'];
    if (raw is Map) {
      raw.forEach((k, v) => dist[_int(k)] = _int(v));
    }
    return ReviewSummary(count: _int(j?['count']), average: _double(j?['average']), distribution: dist);
  }

  final int count;
  final double average;

  /// Stars (1-5) -> number of reviews.
  final Map<int, int> distribution;
}

class ReviewPage {
  const ReviewPage({required this.summary, required this.reviews, required this.total});

  factory ReviewPage.fromJson(Map<String, dynamic> j) => ReviewPage(
        summary: ReviewSummary.fromJson(j['summary'] as Map<String, dynamic>?),
        reviews: [for (final r in (j['data'] as List? ?? const [])) Review.fromJson(r as Map<String, dynamic>)],
        total: _int(j['total']),
      );

  final ReviewSummary summary;
  final List<Review> reviews;
  final int total;
}

/// Result of register / login: `{token, expires_at, user}`. [token] is null
/// when the server answered 202 ("a confirmation code was emailed"); [message]
/// then explains why.
class AuthResult {
  const AuthResult({this.token, this.expiresAt = '', this.name = '', this.message = ''});

  factory AuthResult.fromJson(Map<String, dynamic> j) {
    final token = j['token'];
    if (token is! String || token.isEmpty) {
      return AuthResult(message: j['message'] is String ? j['message'] as String : 'Confirmation required.');
    }
    final user = j['user'];
    return AuthResult(
      token: token,
      expiresAt: _str(j['expires_at']),
      name: user is Map ? _str(user['name']) : '',
    );
  }

  final String? token;
  final String expiresAt;
  final String name;
  final String message;
}

/// The counters returned by voting.
class VoteResult {
  const VoteResult({required this.helpful, required this.unhelpful, this.yourVote});

  factory VoteResult.fromJson(Map<String, dynamic> j) => VoteResult(
        helpful: _int(j['helpful_counter']),
        unhelpful: _int(j['unhelpful_counter']),
        yourVote: j['your_vote'] as String?,
      );

  final int helpful;
  final int unhelpful;

  /// "helpful", "unhelpful" or null.
  final String? yourVote;

  /// The counters once your vote is taken back. The API answers that call with
  /// a message only.
  VoteResult withoutVote() => VoteResult(
        helpful: helpful - (yourVote == 'helpful' ? 1 : 0),
        unhelpful: unhelpful - (yourVote == 'unhelpful' ? 1 : 0),
      );
}

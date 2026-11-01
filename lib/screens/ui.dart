import 'package:flutter/material.dart';

import '../config.dart';
import '../open_url.dart';
import '../reviews_api.dart';

/// Turns any error into a sentence the user can read. The wording is shared by
/// all the SimpleAPI sample apps.
String describeError(Object e) {
  if (e is! ApiException) return 'Something went wrong. Please try again.';
  if (e.statusCode == 0) return e.message; // "Could not reach <host>. Check your connection and try again."
  if (e.sessionEnded) return 'Your session has ended. Please log in again.';
  if (e.keyRejected) return 'The API key was not accepted.';
  return switch (e.statusCode) {
    404 => 'Not found. It may already have been deleted.',
    429 => 'Too many requests. Wait a few seconds and try again.',
    503 => 'The service is busy. Please try again shortly.',
    _ => e.message, // 401 login, 403, 409, 422 and the rest: the API's own message
  };
}

/// The leading item of a top-level app bar: back to the SimpleAPI home page, in the same tab.
Widget backToSimpleApi(UrlOpener openUrl) => IconButton(
      icon: const Icon(Icons.arrow_back),
      tooltip: 'Back to SimpleAPI',
      onPressed: () => openUrl(homeUrl),
    );

void showSnack(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

/// Shown when a request fails, with a retry button.
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(describeError(error), textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
        ]),
      ),
    );
  }
}

class Stars extends StatelessWidget {
  const Stars(this.rating, {super.key});

  final num rating;

  @override
  Widget build(BuildContext context) {
    final full = rating.round().clamp(0, 5);
    return Text('${'★' * full}${'☆' * (5 - full)}', style: const TextStyle(color: Colors.amber, fontSize: 16));
  }
}

/// Centers page content in a readable column on wide screens.
class Centered extends StatelessWidget {
  const Centered({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720), child: child));
}

/// Said on the login and register screens. Same wording in all the SimpleAPI demos.
const demoNoticeText = 'This is a shared demo. Data resets every night. Do not use a real password or any private details.';

/// Shown instead of the API's message when the demo has no room for another user.
const demoFullMessage = 'The demo is full. It resets every night.';

class DemoNotice extends StatelessWidget {
  const DemoNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: scheme.secondaryContainer, borderRadius: BorderRadius.circular(8)),
      child: Text(demoNoticeText, style: TextStyle(color: scheme.onSecondaryContainer)),
    );
  }
}

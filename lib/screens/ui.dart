import 'package:flutter/material.dart';

import '../reviews_api.dart';

/// Turns any error into a sentence the user can read.
String describeError(Object e) => e is ApiException ? e.message : 'Something went wrong: $e';

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

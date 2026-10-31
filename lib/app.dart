import 'package:flutter/material.dart';

import 'app_state.dart';
import 'open_url.dart';
import 'screens/subjects_screen.dart';

class ReviewsApp extends StatelessWidget {
  const ReviewsApp({super.key, required this.state, required this.openUrl});

  final AppState state;
  final UrlOpener openUrl;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SimpleApi Reviews sample',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      // The app opens straight on content. A new keyVersion rebuilds the list
      // so it reloads when the key changes.
      home: ListenableBuilder(
        listenable: state,
        builder: (context, _) => SubjectsScreen(
          key: ValueKey(state.keyVersion),
          state: state,
          openUrl: openUrl,
        ),
      ),
    );
  }
}

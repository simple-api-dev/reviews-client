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
      title: 'Reviews API sample | SimpleAPI',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF0066CC),
        useMaterial3: true,
      ),
      // The app opens straight on content.
      home: SubjectsScreen(state: state, openUrl: openUrl),
    );
  }
}

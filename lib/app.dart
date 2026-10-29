import 'package:flutter/material.dart';

import 'app_state.dart';
import 'screens/key_screen.dart';
import 'screens/subjects_screen.dart';

class ReviewsApp extends StatelessWidget {
  const ReviewsApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SimpleApi Reviews sample',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: ListenableBuilder(
        listenable: state,
        builder: (context, _) => state.hasKey ? SubjectsScreen(state: state) : KeyScreen(state: state),
      ),
    );
  }
}

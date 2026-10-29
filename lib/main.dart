import 'package:flutter/material.dart';

import 'app.dart';
import 'app_state.dart';
import 'key_store_web.dart';

void main() {
  runApp(ReviewsApp(state: AppState(store: LocalStorageKeyStore())));
}

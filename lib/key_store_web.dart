import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'key_store.dart';

/// Keeps the key in the browser's localStorage. It never leaves the browser
/// except as the `apikey` query parameter sent to reviews.simpleapi.dev.
class LocalStorageKeyStore implements KeyStore {
  static const _name = 'simpleapi_reviews_key';

  JSObject get _storage => globalContext['localStorage'] as JSObject;

  @override
  String? read() {
    try {
      return (_storage.callMethod('getItem'.toJS, _name.toJS) as JSString?)?.toDart;
    } catch (_) {
      return null; // storage blocked (private mode etc.)
    }
  }

  @override
  void write(String key) {
    try {
      _storage.callMethod('setItem'.toJS, _name.toJS, key.toJS);
    } catch (_) {}
  }

  @override
  void clear() {
    try {
      _storage.callMethod('removeItem'.toJS, _name.toJS);
    } catch (_) {}
  }
}

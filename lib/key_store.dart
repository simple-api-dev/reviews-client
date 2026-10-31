/// Where the developer's SimpleAPI key is remembered between visits.
///
/// The app only ever talks to this small interface. In the browser it is
/// backed by localStorage (key_store_web.dart); tests use [MemoryKeyStore].
abstract class KeyStore {
  String? read();
  void write(String key);
  void clear();
}

class MemoryKeyStore implements KeyStore {
  MemoryKeyStore([this._key]);

  String? _key;

  @override
  String? read() => _key;

  @override
  void write(String key) => _key = key;

  @override
  void clear() => _key = null;
}

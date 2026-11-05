/// Serializes camera open/close operations and discards a startup completed
/// after suspension. Native camera handles must be released before reopening.
class ScannerCameraSession<T> {
  ScannerCameraSession({required this.open, required this.close});

  final Future<T> Function() open;
  final Future<void> Function(T) close;
  Future<void> _operations = Future.value();
  T? current;
  int generation = 0;

  bool isCurrent(int token) => token == generation;

  Future<void> start() {
    final token = ++generation;
    return _enqueue(() async {
      if (!isCurrent(token)) return;
      final old = current;
      current = null;
      if (old != null) await close(old);
      final camera = await open();
      if (!isCurrent(token)) {
        await close(camera);
        return;
      }
      current = camera;
    });
  }

  Future<void> stop() {
    generation++;
    final camera = current;
    current = null;
    return _enqueue(() async {
      if (camera != null) await close(camera);
    });
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final result = _operations.then((_) => operation());
    // Preserve the error for this caller without poisoning future retries.
    _operations = result.catchError((Object _) {});
    return result;
  }
}

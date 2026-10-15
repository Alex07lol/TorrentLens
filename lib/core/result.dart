/// A small, explicit success/failure type used across the domain layer.
///
/// The project deliberately avoids throwing for *expected* failures (bad
/// magnet links, malformed manifests, rejected signatures). Those are values,
/// not exceptions, so callers must handle them.
sealed class Result<T> {
  const Result();

  bool get isOk => this is Ok<T>;
  bool get isErr => this is Err<T>;

  T? get valueOrNull => this is Ok<T> ? (this as Ok<T>).value : null;
  Object? errorOrNull() => this is Err<T> ? (this as Err<T>).error : null;

  R fold<R>(R Function(T value) onOk, R Function(Object error) onErr) {
    final self = this;
    return self is Ok<T> ? onOk(self.value) : onErr((self as Err<T>).error);
  }
}

final class Ok<T> extends Result<T> {
  final T value;
  const Ok(this.value);
}

final class Err<T> extends Result<T> {
  final Object error;
  const Err(this.error);
}

extension ResultFuture<T> on Future<T> {
  Future<Result<T>> asResult() async {
    try {
      return Ok(await this);
    } catch (e) {
      return Err(e);
    }
  }
}

/// Retry-After is a minimum, including when the server's delay is shorter
/// than the normal result settle time. Jitter only adds time.
Duration scanRetryDelay({Duration? retryAfter, required double jitter}) {
  const settle = Duration(milliseconds: 900);
  final base = retryAfter != null && retryAfter > settle ? retryAfter : settle;
  return base +
      Duration(
        milliseconds: (base.inMilliseconds * 0.4 * jitter.clamp(0.0, 1.0))
            .round(),
      );
}

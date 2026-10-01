/// Replace the no-op sink with a consent-appropriate, non-blocking adapter later.
/// Events contain catalog IDs only; never customer information or free text.
abstract class Analytics {
  void event(String name, {String? catalogId});
}

class NoopAnalytics implements Analytics {
  @override
  void event(String name, {String? catalogId}) {}
}

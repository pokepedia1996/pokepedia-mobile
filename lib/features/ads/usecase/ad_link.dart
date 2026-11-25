import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;

import '../../../core/config/app_config.dart';
import '../../../shared/widgets/app_bottom_nav.dart';

/// Where an ad's `href` leads.
sealed class AdLinkTarget {
  const AdLinkTarget();

  /// Reads `ads.href`:
  ///
  /// - `/seller`, `/scan`, `/market/toko-ash`: an app path, opened in place.
  /// - `https://pokepedia.id/...` (www, the apex, or the site this build
  ///   talks to): the same, by its path — a booking written for the website
  ///   still lands inside the app rather than in a browser.
  /// - Any other `https://` (or `http://`) URL: the advertiser's site, in the
  ///   browser.
  /// - Empty or unreadable: nothing happens.
  static AdLinkTarget? parse(String href) {
    final value = href.trim();
    if (value.isEmpty) return null;
    if (value.startsWith('/') && !value.startsWith('//')) {
      return AdInAppLink(value);
    }
    final uri = Uri.tryParse(value);
    if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http')) {
      return null;
    }
    if (uri.host.isEmpty) return null;
    if (_ownHosts.contains(uri.host.toLowerCase())) {
      final path = uri.path.isEmpty ? '/' : uri.path;
      return AdInAppLink(uri.hasQuery ? '$path?${uri.query}' : path);
    }
    return AdExternalLink(uri);
  }

  static Set<String> get _ownHosts {
    final hosts = {'pokepedia.id', 'www.pokepedia.id'};
    try {
      final own = Uri.parse(AppConfig.appUrl).host;
      if (own.isNotEmpty) hosts.add(own.toLowerCase());
    } catch (_) {}
    return hosts;
  }
}

/// An app path, with its query if it has one.
class AdInAppLink extends AdLinkTarget {
  const AdInAppLink(this.location);

  final String location;

  /// A bottom-nav tab (`/`, `/seller`, `/market`, …) is switched to, not
  /// pushed on top of Beranda: a second copy of a tab under the first is
  /// a back button that leads nowhere new.
  bool get isTab => AppBottomNav.tabPaths.contains(Uri.parse(location).path);
}

class AdExternalLink extends AdLinkTarget {
  const AdExternalLink(this.uri);

  final Uri uri;
}

/// Follows an ad's `href` (see [AdLinkTarget.parse]). A path the app has no
/// page for lands on its not-found page.
Future<void> openAdLink(BuildContext context, String href) async {
  switch (AdLinkTarget.parse(href)) {
    case null:
      return;
    case final AdInAppLink link:
      if (link.isTab) {
        context.go(link.location);
      } else {
        context.push(link.location);
      }
    case AdExternalLink(:final uri):
      await launcher.launchUrl(
        uri,
        mode: launcher.LaunchMode.externalApplication,
      );
  }
}

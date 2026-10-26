import 'package:animations/animations.dart';
import 'package:flutter/material.dart';

import '../constants/constants.dart';
import '../pages/app/app_page.dart';
import '../pages/feed/feed_page.dart';
import '../pages/others/imageview_page.dart';
import '../pages/search/search_page.dart';
import '../pages/topic/topic_page.dart';
import '../pages/user/user_page.dart';
import '../utils/miuix_palette.dart';
import 'app_anim.dart';

/// Source-anchored page transitions ("container transform").
///
/// Tapping a card / row / avatar grows the target page out of that exact
/// element's rect; leaving the page (back button or system back) shrinks it
/// back into the same element. When the source element has scrolled away or
/// been disposed while the page is open, [OpenContainer] degrades to a plain
/// fade on the way back instead of misplacing the animation.
///
/// Why OpenContainer and not Hero: the requirement is that the *whole page*
/// expands from the source rect and disappears back into it, which is the
/// container transform. Hero only flies a single shared element between two
/// already-laid-out pages and cannot express the page itself growing out of
/// a card. OpenContainer pushes a regular route on the nearest Navigator, so
/// it composes with GetX (GetPageRoute pages keep their own transitions;
/// container routes are ordinary Navigator routes above the source page).
/// Hero is also unusable for the image gallery: PhotoViewGallery would
/// register one hero per built page and several would fly at once.
///
/// All containers here are `tappable: false`: the source element wires the
/// provided open action into its own tap handler, so existing gesture
/// behaviour (inner buttons, long-press menus, nested containers) keeps the
/// exact arena resolution it had before.

/// Shared duration, matching the app's GetX page transitions
/// (miuix18 起统一为 [AppAnim.page] = 300ms，见全局动画规范）。
const Duration kAnchoredTransitionDuration = AppAnim.page;

typedef AnchoredClosedBuilder = Widget Function(
    BuildContext context, VoidCallback open);
typedef AnchoredOpenBuilder = Widget Function(
    BuildContext context, VoidCallback close);

/// [OpenContainer] preconfigured with the app's look: no elevation jump,
/// fadeThrough for page opens, zero-elevation flat surfaces.
class AnchoredContainer extends StatelessWidget {
  const AnchoredContainer({
    super.key,
    required this.closedBuilder,
    required this.openBuilder,
    required this.closedColor,
    required this.openColor,
    this.closedShape = const RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
    ),
    this.transitionType = ContainerTransitionType.fadeThrough,
    this.transitionDuration = kAnchoredTransitionDuration,
  });

  final AnchoredClosedBuilder closedBuilder;
  final AnchoredOpenBuilder openBuilder;

  /// Painted behind the closed element; must match the color the element
  /// itself fills its rect with so the morph has no visible seam.
  final Color closedColor;

  /// Background color of the opened page (its Scaffold background).
  final Color openColor;

  final ShapeBorder closedShape;
  final ContainerTransitionType transitionType;
  final Duration transitionDuration;

  @override
  Widget build(BuildContext context) {
    return OpenContainer(
      tappable: false,
      closedElevation: 0,
      openElevation: 0,
      closedColor: closedColor,
      openColor: openColor,
      closedShape: closedShape,
      transitionType: transitionType,
      transitionDuration: transitionDuration,
      closedBuilder: closedBuilder,
      openBuilder: openBuilder,
    );
  }
}

/// Opens the feed detail page ([FeedPage]) from the source element.
class FeedContainer extends StatelessWidget {
  const FeedContainer({
    super.key,
    required this.feedId,
    required this.closedColor,
    required this.closedBuilder,
    this.closedShape = const RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(24)),
    ),
  });

  final String feedId;
  final Color closedColor;
  final ShapeBorder closedShape;
  final AnchoredClosedBuilder closedBuilder;

  @override
  Widget build(BuildContext context) {
    return AnchoredContainer(
      closedColor: closedColor,
      openColor: miuixPageBackground(context),
      closedShape: closedShape,
      closedBuilder: closedBuilder,
      openBuilder: (_, __) => FeedPage(id: feedId),
    );
  }
}

/// Opens a user profile page ([UserPage]) from the source element
/// (avatar, username, user row, ...).
class UserContainer extends StatelessWidget {
  const UserContainer({
    super.key,
    required this.uid,
    required this.closedColor,
    required this.closedBuilder,
    this.closedShape = const RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
    ),
  });

  final String uid;
  final Color closedColor;
  final ShapeBorder closedShape;
  final AnchoredClosedBuilder closedBuilder;

  @override
  Widget build(BuildContext context) {
    return AnchoredContainer(
      closedColor: closedColor,
      openColor: miuixPageBackground(context),
      closedShape: closedShape,
      closedBuilder: closedBuilder,
      openBuilder: (_, __) => UserPage(uid: uid),
    );
  }
}

/// Opens an app page ([AppPage]) from the source element (app chip, app
/// row, ...). Mirrors the '/apk/:packageName' route; game links resolve to
/// the same page, exactly like `Utils.onOpenLink`.
class AppContainer extends StatelessWidget {
  const AppContainer({
    super.key,
    required this.packageName,
    required this.closedColor,
    required this.closedBuilder,
    this.closedShape = const RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
    ),
  });

  final String packageName;
  final Color closedColor;
  final ShapeBorder closedShape;
  final AnchoredClosedBuilder closedBuilder;

  @override
  Widget build(BuildContext context) {
    return AnchoredContainer(
      closedColor: closedColor,
      openColor: miuixPageBackground(context),
      closedShape: closedShape,
      closedBuilder: closedBuilder,
      openBuilder: (_, __) => AppPage(packageName: packageName),
    );
  }
}

/// Opens a topic/product page ([TopicPage]) from the source element.
/// Exactly one of [tag] / [id] is set, mirroring the '/t/:tag' and
/// '/product/:id' routes.
class TopicContainer extends StatelessWidget {
  const TopicContainer({
    super.key,
    this.tag,
    this.id,
    required this.closedColor,
    required this.closedBuilder,
    this.closedShape = const RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
    ),
  });

  final String? tag;
  final String? id;
  final Color closedColor;
  final ShapeBorder closedShape;
  final AnchoredClosedBuilder closedBuilder;

  @override
  Widget build(BuildContext context) {
    return AnchoredContainer(
      closedColor: closedColor,
      openColor: miuixPageBackground(context),
      closedShape: closedShape,
      closedBuilder: closedBuilder,
      openBuilder: (_, __) => TopicPage(tag: tag, id: id),
    );
  }
}

/// An avatar image that grows into its user's profile page. Falls back to
/// the plain child when [uid] is empty (no viable target). The closed color
/// is transparent: the avatar fills its circle completely, so the container
/// leaves no footprint in the closed state regardless of the surface the
/// avatar sits on.
class UserAvatarContainer extends StatelessWidget {
  const UserAvatarContainer({
    super.key,
    required this.uid,
    required this.child,
  });

  final String uid;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (uid.isEmpty) return child;
    return UserContainer(
      uid: uid,
      closedColor: Colors.transparent,
      closedShape: const CircleBorder(),
      closedBuilder: (context, open) => GestureDetector(
        onTap: open,
        child: child,
      ),
    );
  }
}

/// Opens the fullscreen image gallery ([ImageViewPage]) from a thumbnail.
/// Uses the `fade` transition (both sides visible while the rect grows)
/// which reads as the photo itself expanding, instead of fadeThrough.
class ImageContainer extends StatelessWidget {
  const ImageContainer({
    super.key,
    required this.imgList,
    required this.initialPage,
    required this.closedColor,
    required this.closedBuilder,
    this.closedShape = const RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
    ),
  });

  final List<String> imgList;
  final int initialPage;
  final Color closedColor;
  final ShapeBorder closedShape;
  final AnchoredClosedBuilder closedBuilder;

  @override
  Widget build(BuildContext context) {
    return AnchoredContainer(
      closedColor: closedColor,
      openColor: Theme.of(context).scaffoldBackgroundColor,
      closedShape: closedShape,
      transitionType: ContainerTransitionType.fade,
      transitionDuration: AppAnim.page,
      closedBuilder: closedBuilder,
      openBuilder: (_, __) =>
          ImageViewPage(imgList: imgList, initialPage: initialPage),
    );
  }
}

/// Opens the search page ([SearchPage]) from the source element (the
/// home page's fake search field), so the field itself grows into the
/// search page instead of the page sliding in unrelated.
///
/// Only for parameter-less entries: [SearchPage] reads its optional
/// title/pageType/pageParam from GetX route parameters, which a
/// container route does not carry. The home entry passes none — exactly
/// like the `Get.toNamed('/search')` call this replaces — while the
/// parameterised search entries elsewhere keep their named routes.
class SearchContainer extends StatelessWidget {
  const SearchContainer({
    super.key,
    required this.closedColor,
    required this.closedBuilder,
  });

  /// Must match the search field's own fill colour so the morph has no
  /// visible seam.
  final Color closedColor;
  final AnchoredClosedBuilder closedBuilder;

  @override
  Widget build(BuildContext context) {
    return AnchoredContainer(
      closedColor: closedColor,
      openColor: Theme.of(context).scaffoldBackgroundColor,
      closedShape: const StadiumBorder(),
      closedBuilder: closedBuilder,
      openBuilder: (_, __) => const SearchPage(),
    );
  }
}

/// Resolves a Coolapk link to the page a source-anchored container should
/// open, or null when the link has no anchored target (external links,
/// carousel, ...), in which case callers keep the legacy
/// `Utils.onOpenLink` behaviour.
///
/// Mirrors the matching rules of `Utils._openLink` for the in-app targets:
/// feed detail (only when [includeFeed]), user profile, topic, product and
/// app pages ('/apk/' and '/game/' both land on [AppPage]).
/// Feed targets are excluded when [includeFeed] is false for sources that
/// live under a reading-pane scope, where feed taps must keep going through
/// `FeedNavigation` so the pane can claim them.
Widget? anchoredPageForUrl(
  String url, {
  bool needConvert = false,
  bool includeFeed = true,
}) {
  if (url.isEmpty) return null;
  String path = url;
  if (needConvert) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    const hosts = {
      'coolapk.com',
      'www.coolapk.com',
      'm.coolapk.com',
      'coolapk1s.com',
      'www.coolapk1s.com',
    };
    if (uri.scheme == 'coolmarket') {
      path = hosts.contains(uri.host) || uri.host == 'com.coolapk.market'
          ? uri.path
          : '/${uri.host}${uri.path}';
      if (uri.hasQuery) path += '?${uri.query}';
    } else if ((uri.scheme == 'http' || uri.scheme == 'https') &&
        hosts.contains(uri.host)) {
      path = uri.path;
      if (uri.hasQuery) path += '?${uri.query}';
    } else {
      return null;
    }
  }
  if (!path.startsWith('/')) return null;
  final parsed = Uri.parse(path);
  final segments = parsed.pathSegments;
  if (segments.isEmpty) return null;
  // Same malformed-link guard as Utils._openLink: a known prefix without an
  // identifier is not a viable target.
  if (const {'feed', 'event', 'u', 'apk', 'game', 't', 'product'}
          .contains(segments.first) &&
      (segments.length < 2 || segments[1].trim().isEmpty)) {
    return null;
  }
  if (includeFeed && RegExp(r'^/feed/[0-9]+/?(?:[?#]|$)').hasMatch(path)) {
    return FeedPage(id: segments[1]);
  }
  if (path.startsWith(Constants.PREFIX_USER)) {
    // pathSegments are percent-decoded, which is the value UserPage expects
    // (GetX decodes route parameters the same way).
    return UserPage(uid: segments.skip(1).join('/'));
  }
  if (path.startsWith(Constants.PREFIX_TOPIC)) {
    if (parsed.queryParameters['type'] == '8') return null; // coolpic list
    // TopicPage decodes its tag once in initState (the route parameter it
    // normally receives is percent-encoded), so hand it the encoded form.
    return TopicPage(tag: Uri.encodeComponent(segments.skip(1).join('/')));
  }
  if (path.startsWith(Constants.PREFIX_PRODUCT)) {
    return TopicPage(id: segments[1]);
  }
  if (path.startsWith(Constants.PREFIX_APP) ||
      path.startsWith(Constants.PREFIX_GAME)) {
    // pathSegments are percent-decoded; package names are plain ASCII, so
    // this is the same value the '/apk/:packageName' route parameter
    // would carry after GetX decodes it.
    return AppPage(packageName: segments[1]);
  }
  return null;
}

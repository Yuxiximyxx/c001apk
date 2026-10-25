import 'dart:io';

import 'package:animations/animations.dart';
import 'package:c001apk_flutter/components/cards/feed_card.dart';
import 'package:c001apk_flutter/components/imageview.dart';
import 'package:c001apk_flutter/components/source_container.dart';
import 'package:c001apk_flutter/logic/model/feed/datum.dart';
import 'package:c001apk_flutter/pages/feed/feed_page.dart';
import 'package:c001apk_flutter/pages/others/imageview_page.dart';
import 'package:c001apk_flutter/pages/topic/topic_page.dart';
import 'package:c001apk_flutter/pages/user/user_page.dart';
import 'package:c001apk_flutter/utils/storage_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory temp;
  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('c001apk-anchored-');
    Hive.init(temp.path);
    GStorage.settings = await Hive.openBox('settings');
  });
  tearDownAll(() async {
    await Hive.close();
    await temp.delete(recursive: true);
  });
  tearDown(Get.reset);

  group('anchoredPageForUrl', () {
    test('feed links resolve to FeedPage with the numeric id', () {
      final page = anchoredPageForUrl('/feed/123');
      expect(page, isA<FeedPage>());
      expect((page! as FeedPage).id, '123');

      final shared = anchoredPageForUrl('/feed/123?s=synthetic-share');
      expect(shared, isA<FeedPage>());
      expect((shared! as FeedPage).id, '123');
    });

    test('full coolapk urls resolve when conversion is requested', () {
      final page = anchoredPageForUrl('https://www.coolapk.com/feed/456',
          needConvert: true);
      expect(page, isA<FeedPage>());
      expect((page! as FeedPage).id, '456');
    });

    test('feed links are excluded when includeFeed is false', () {
      expect(anchoredPageForUrl('/feed/123', includeFeed: false), isNull);
    });

    test('user links resolve to UserPage with the decoded uid', () {
      final page = anchoredPageForUrl('/u/789');
      expect(page, isA<UserPage>());
      expect((page! as UserPage).uid, '789');
    });

    test('topic links resolve to TopicPage with the route-form tag', () {
      final page = anchoredPageForUrl('/t/小米手机');
      expect(page, isA<TopicPage>());
      // TopicPage decodes its tag once in initState, so the resolver hands
      // it the percent-encoded form a route parameter would carry.
      expect((page! as TopicPage).tag, Uri.encodeComponent('小米手机'));
      expect((page as TopicPage).id, isNull);
    });

    test('coolpic topic links have no anchored target', () {
      expect(anchoredPageForUrl('/t/abc?type=8'), isNull);
    });

    test('product links resolve to TopicPage with the id', () {
      final page = anchoredPageForUrl('/product/42');
      expect(page, isA<TopicPage>());
      expect((page! as TopicPage).id, '42');
      expect((page as TopicPage).tag, isNull);
    });

    test('non-anchored and malformed links resolve to null', () {
      expect(anchoredPageForUrl('/apk/com.coolapk.market'), isNull);
      expect(anchoredPageForUrl('/event/12'), isNull);
      expect(anchoredPageForUrl(''), isNull);
      expect(anchoredPageForUrl('/feed/'), isNull);
      expect(anchoredPageForUrl('/u/'), isNull);
      expect(
          anchoredPageForUrl('https://example.com/feed/1', needConvert: true),
          isNull);
      expect(anchoredPageForUrl('https://www.coolapk.com/feed/1'), isNull,
          reason: 'full urls need needConvert, like Utils.onOpenLink');
    });
  });

  testWidgets('AnchoredContainer opens its page and returns to the source',
      (tester) async {
    await tester.pumpWidget(GetMaterialApp(
      home: Scaffold(
        body: Center(
          child: AnchoredContainer(
            closedColor: Colors.red,
            openColor: Colors.white,
            closedBuilder: (context, open) => GestureDetector(
              onTap: open,
              child: const SizedBox(
                width: 80,
                height: 60,
                child: Text('源头卡片'),
              ),
            ),
            openBuilder: (context, close) =>
                const Scaffold(body: Center(child: Text('目标页'))),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('源头卡片'), findsOneWidget);
    expect(find.byType(OpenContainer), findsOneWidget);

    await tester.tap(find.text('源头卡片'));
    await tester.pumpAndSettle();
    expect(find.text('目标页'), findsOneWidget);

    // System back pops the container route and lands back on the source.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('目标页'), findsNothing);
    expect(find.text('源头卡片'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('FeedCard wires card, avatar and username containers',
      (tester) async {
    final data = Datum.fromJson({
      'id': 123,
      'uid': 7,
      'dateline': 1760000000,
      'message': '合成正文',
      'userAvatar': '',
      'userInfo': {'uid': 7, 'username': '合成作者'},
      'likenum': 0,
      'replynum': 0,
    });
    await tester.pumpWidget(GetMaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: FeedCard(data: data))),
    ));
    await tester.pumpAndSettle();

    // The card itself is a FeedContainer for feed 123.
    final feedContainers =
        tester.widgetList<FeedContainer>(find.byType(FeedContainer));
    expect(feedContainers.map((c) => c.feedId), contains('123'));

    // Its openBuilder really produces the detail page for that feed.
    final context = tester.element(find.byType(FeedCard));
    final anchored = (feedContainers.first.build(context) as AnchoredContainer);
    final opened = anchored.openBuilder(context, () {});
    expect(opened, isA<FeedPage>());
    expect((opened as FeedPage).id, '123');

    // Avatar and username are UserContainers for uid 7 whose openBuilder
    // produces the matching profile page.
    final userContainers =
        tester.widgetList<UserContainer>(find.byType(UserContainer));
    expect(userContainers, isNotEmpty);
    expect(userContainers.every((c) => c.uid == '7'), isTrue);
    final userAnchored =
        (userContainers.first.build(context) as AnchoredContainer);
    final userPage = userAnchored.openBuilder(context, () {});
    expect(userPage, isA<UserPage>());
    expect((userPage as UserPage).uid, '7');

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('image thumbnails wire an ImageContainer for the gallery',
      (tester) async {
    const pics = [
      'https://image.coolapk.com/a@100x80.jpg',
      'https://image.coolapk.com/b@100x80.jpg',
    ];
    await tester.pumpWidget(GetMaterialApp(
      home: Scaffold(body: image(300, pics)),
    ));
    await tester.pumpAndSettle();

    final containers =
        tester.widgetList<ImageContainer>(find.byType(ImageContainer));
    expect(containers.length, 2);
    expect(containers.first.imgList, pics);
    expect(containers.first.initialPage, 0);
    expect(containers.last.initialPage, 1);

    final context = tester.element(find.byType(ImageContainer).first);
    final anchored = (containers.first.build(context) as AnchoredContainer);
    final opened = anchored.openBuilder(context, () {});
    expect(opened, isA<ImageViewPage>());
    expect((opened as ImageViewPage).imgList, pics);
    expect(opened.initialPage, 0);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

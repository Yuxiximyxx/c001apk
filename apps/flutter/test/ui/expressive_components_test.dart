import 'dart:async';

import 'package:c001apk_flutter/components/expressive_loading_indicator.dart';
import 'package:c001apk_flutter/components/expressive_navigation_bar.dart';
import 'package:c001apk_flutter/components/expressive_refresh_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'navigation matches the 64dp short bar and adds the bottom inset once',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(padding: EdgeInsets.only(bottom: 24)),
        child: Scaffold(
          bottomNavigationBar: ExpressiveNavigationBar(
            selectedIndex: 0,
            onDestinationSelected: (_) {},
          ),
        ),
      ),
    ));
    expect(tester.getSize(find.byType(NavigationBar)).height, 88);
    final target = tester.getRect(find.byType(NavigationDestination).first);
    expect(target.height, 64);
    expect(target.bottom,
        tester.getBottomLeft(find.byType(NavigationBar)).dy - 24);
  });

  testWidgets('scrolling upward from the top does not pretend to refresh',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ExpressiveRefreshIndicator(
          onRefresh: () async {},
          child: ListView(
            children: [for (var i = 0; i < 60; i++) Text('内容 $i')],
          ),
        ),
      ),
    ));
    final gesture = await tester.startGesture(const Offset(300, 400));
    await gesture.moveBy(const Offset(0, -150));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(ExpressiveLoadingIndicator), findsNothing);
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('programmatic refresh preserves its key and clears when finished',
      (tester) async {
    final key = GlobalKey<RefreshIndicatorState>();
    final pending = Completer<void>();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ExpressiveRefreshIndicator(
          refreshKey: key,
          onRefresh: () => pending.future,
          child: ListView(children: const [Text('列表内容')]),
        ),
      ),
    ));
    final refresh = key.currentState!.show();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(ExpressiveLoadingIndicator), findsOneWidget);
    expect(find.text('列表内容'), findsOneWidget);
    pending.complete();
    await tester.pumpAndSettle();
    await refresh;
    expect(find.byType(ExpressiveLoadingIndicator), findsNothing);
    expect(key.currentState, isNotNull);
  });
  testWidgets('loading stops scheduling frames when reduced motion is enabled',
      (tester) async {
    Widget app(bool reduced) => MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduced),
            child: const Center(child: ExpressiveLoadingIndicator()),
          ),
        );
    await tester.pumpWidget(app(false));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.binding.hasScheduledFrame, isTrue);
    expect(find.bySemanticsLabel('正在加载'), findsOneWidget);
    await tester.pumpWidget(app(true));
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(find.bySemanticsLabel('正在加载'), findsOneWidget);
    await tester.pumpWidget(app(false));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('hidden loading animation releases its frame scheduling',
      (tester) async {
    Widget app(bool active) => MaterialApp(
          home: TickerMode(
            enabled: active,
            child: const ExpressiveLoadingIndicator(),
          ),
        );
    await tester.pumpWidget(app(true));
    await tester.pumpWidget(app(false));
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(app(true));
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('compact navigation remains selectable at double text size',
      (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var selected = 0;
    await tester.pumpWidget(MaterialApp(
        home: StatefulBuilder(
      builder: (context, setState) => MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: Scaffold(
          bottomNavigationBar: ExpressiveNavigationBar(
            selectedIndex: selected,
            onDestinationSelected: (value) => setState(() => selected = value),
          ),
        ),
      ),
    )));
    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    expect(selected, 2);
    expect(find.text('主页'), findsOneWidget);
    expect(find.text('关注'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

// 有效性验证：诊断观察者的存在不得改变预测式返回的任何生产行为。
// 方法是在与 predictive_back_test.dart 相同的手势注入下，对照断言：
// 页面几何（跟随缩小/取消复原/提交只 pop 一层）与未装诊断时一致；
// 同时断言日志确实捕获了通道事件、认领信号与门控派生值。
// 另含一例「无 detector 认领时 commit 走离散兜底」——若观察者错误地
// 认领了手势，该兜底会被吞掉、路由状态必然不同，以此反证恒 false 的
// 观察者不改变分发拓扑。
import 'package:c001apk_flutter/diagnostics/predictive_back_diagnostics.dart';
import 'package:c001apk_flutter/router/app_pages.dart';
import 'package:c001apk_flutter/router/page_transitions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

void main() {
  tearDown(Get.reset);

  late BackDiagNavigatorObserver navObserver;
  late BackDiagBindingObserver bindingObserver;

  setUp(() {
    BackDiagLog.instance.clear();
    navObserver = BackDiagNavigatorObserver();
    bindingObserver = BackDiagBindingObserver(navObserver);
  });

  Future<void> backEvent(WidgetTester tester, String method,
      {double progress = 0, int edge = 0, double y = 300}) async {
    final width = tester.view.physicalSize.width;
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/backgesture',
      const StandardMethodCodec().encodeMethodCall(MethodCall(method, {
        'touchOffset': <double>[
          width * (edge == 0 ? progress : 1 - progress),
          y,
        ],
        'progress': progress,
        'swipeEdge': edge,
      })),
      (_) {},
    );
    await tester.pump();
  }

  Future<void> openPage(WidgetTester tester, {bool blocked = false}) async {
    tester.binding.addObserver(bindingObserver);
    addTearDown(() => tester.binding.removeObserver(bindingObserver));
    final route = AppPages.getPages.firstWhere((page) => page.name == '/about');
    await tester.pumpWidget(GetMaterialApp(
      customTransition: AppPageTransition(),
      theme: ThemeData(platform: TargetPlatform.android),
      initialRoute: '/',
      navigatorObservers: [navObserver],
      getPages: [
        GetPage(name: '/', page: () => const Scaffold(body: Text('上一页'))),
        route.copy(
          curve: Curves.easeOutQuad,
          page: () => PopScope(
            canPop: !blocked,
            child: const Scaffold(body: Text('当前页')),
          ),
        ),
      ],
    ));
    Get.toNamed('/about');
    await tester.pumpAndSettle();
  }

  Rect pageBounds(WidgetTester tester) => tester.getRect(find
      .ancestor(of: find.text('当前页'), matching: find.byType(Scaffold))
      .first);

  String logText() => BackDiagLog.instance.fullText;

  testWidgets('diagnostics observe a GetX gesture without changing it',
      (tester) async {
    await openPage(tester);
    final original = pageBounds(tester);

    // 门控派生值应在进子页后变为 true 并被记录。
    expect(logText(), contains('canHandlePop'));
    expect(logText(), contains('-> true'));

    await backEvent(tester, 'startBackGesture');
    // 通道层：start 到达且载荷被完整记录（非按钮事件）。
    expect(logText(), contains('[通道] startBackGesture 到达 Dart'));
    expect(logText(), contains('isButtonEvent=false'));
    // 路由层：detector 认领信号被记录。
    expect(logText(), contains('[手势] didStartUserGesture'));

    await backEvent(tester, 'updateBackGestureProgress', progress: 0.5);
    // 行为与未装诊断时一致：页面跟随缩小。
    expect(pageBounds(tester).width, lessThan(original.width));
    // 进度驱动动画的代理指标被记录。
    expect(logText(), contains('[动画]'));
    expect(logText(), contains('手势驱动中'));

    await backEvent(tester, 'cancelBackGesture');
    await tester.pumpAndSettle();
    expect(pageBounds(tester), original);
    expect(Get.currentRoute, '/about');
    expect(Get.key.currentState!.userGestureInProgress, isFalse);

    // 提交路径同样只 pop 一层。
    await backEvent(tester, 'startBackGesture');
    await backEvent(tester, 'updateBackGestureProgress', progress: 0.5);
    await backEvent(tester, 'commitBackGesture');
    await tester.pumpAndSettle();
    expect(find.text('当前页'), findsNothing);
    expect(find.text('上一页'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('diagnostics do not swallow the discrete fallback pop',
      (tester) async {
    await openPage(tester, blocked: true);
    await backEvent(tester, 'startBackGesture');
    expect(logText(), contains('[通道] startBackGesture 到达 Dart'));
    // 被 PopScope 拦截的路由：detector 不认领（_GuardedBackRoute 的
    // popGestureEnabled 为 false），不得出现认领信号。
    expect(logText(), isNot(contains('[手势] didStartUserGesture')));
    await backEvent(tester, 'commitBackGesture');
    await tester.pumpAndSettle();
    // commit 走框架的离散兜底（didPopRoute），路由因 doNotPop 保留原状——
    // 与未装诊断时的行为一致；若观察者错误认领，兜底不会触发。
    expect(logText(), contains('[框架] didPopRoute 被调用'));
    expect(Get.currentRoute, '/about');
    expect(Get.key.currentState!.userGestureInProgress, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('plain MaterialPageRoute arm of the A/B experiment follows',
      (tester) async {
    tester.binding.addObserver(bindingObserver);
    addTearDown(() => tester.binding.removeObserver(bindingObserver));
    await tester.pumpWidget(GetMaterialApp(
      customTransition: AppPageTransition(),
      theme: ThemeData(
        platform: TargetPlatform.android,
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: <TargetPlatform, PageTransitionsBuilder>{
            TargetPlatform.android: AppPredictiveBackPageTransitionsBuilder(),
          },
        ),
      ),
      navigatorObservers: [navObserver],
      home: const Scaffold(body: Text('主页')),
    ));
    await tester.pumpAndSettle();
    final context = tester.element(find.text('主页'));
    navObserver.armNextRouteLabel('B-普通路由测试页');
    Navigator.of(context).push<void>(MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'diag/plain-test'),
      builder: (_) => const Scaffold(body: Text('普通页')),
    ));
    await tester.pumpAndSettle();
    expect(logText(), contains('B-普通路由测试页'));

    final original = tester.getRect(find
        .ancestor(of: find.text('普通页'), matching: find.byType(Scaffold))
        .first);
    await backEvent(tester, 'startBackGesture');
    expect(logText(), contains('[手势] didStartUserGesture'));
    await backEvent(tester, 'updateBackGestureProgress', progress: 0.5);
    final shrunk = tester.getRect(find
        .ancestor(of: find.text('普通页'), matching: find.byType(Scaffold))
        .first);
    expect(shrunk.width, lessThan(original.width));
    await backEvent(tester, 'cancelBackGesture');
    await tester.pumpAndSettle();
    expect(find.text('普通页'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

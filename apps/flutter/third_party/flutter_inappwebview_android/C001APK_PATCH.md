# Local AGP 9 compatibility patch

Source: `flutter_inappwebview_android` 1.1.3, published 2024-10-02.
Archive: https://pub.dev/api/archives/flutter_inappwebview_android-1.1.3.tar.gz
Archive SHA-256: `62557c15a5c2db5d195cb3892aab74fcaec266d7b86d59a6f0027abd672cddba` (pub.dev metadata).
Repository: https://github.com/pichillilorenzo/flutter_inappwebview
Upstream release tag `v6.1.5`: commit `f67ae1f34868c7660c16a2473f53a7a7bfb6f784`; the package archive above is the exact source of this copy.
License: Apache-2.0; upstream LICENSE, source copyright notices and complete package retained.

Modified 2026-10-22: in `android/build.gradle`, replace both `getDefaultProguardFile('proguard-android.txt')` calls with `getDefaultProguardFile('proguard-android-optimize.txt')`. AGP 9 rejects the removed default. A dated modification notice is added to that file. Java, Dart, consumer rules and dependency versions are unchanged. The global Pub cache is never modified. This patch was validated in an isolated candidate before migration into the maintained app.

This enables R8 optimization for the plugin release variant; a successful debug build alone is insufficient. Validate release shrinking and WebView runtime before promoting. Replace this local override when a tested stable upstream supports the selected AGP.

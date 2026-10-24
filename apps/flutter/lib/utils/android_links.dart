import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Android keeps ACTION_VIEW intents until the root navigator can consume them.
/// External URLs must pass through our normal link parser, not GetX's router.
class AndroidLinks {
  AndroidLinks({required this.onOpen});

  final void Function(String) onOpen;
  static const _channel = MethodChannel('app.awavenue.c001apk/links');
  bool _ready = false;
  bool _reading = false;
  bool _readAgain = false;

  void listen() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'linksChanged' && _ready) await _readPending();
    });
  }

  Future<void> ready() async {
    _ready = true;
    await _readPending();
  }

  Future<void> _readPending() async {
    if (_reading) {
      _readAgain = true;
      return;
    }
    _reading = true;
    try {
      do {
        _readAgain = false;
        final links =
            await _channel.invokeListMethod<String>('takePendingLinks');
        for (final link in links ?? <String>[]) {
          onOpen(link);
          // Let each destination mount before another intent changes parameters.
          await WidgetsBinding.instance.endOfFrame;
        }
      } while (_readAgain);
    } on PlatformException {
      // No URL or platform error text is logged: links may contain private data.
    } finally {
      _reading = false;
    }
  }
}

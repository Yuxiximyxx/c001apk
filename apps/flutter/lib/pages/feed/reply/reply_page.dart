import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:chat_bottom_container/chat_bottom_container.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import '../../../logic/network/api_failure.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart' hide Response, FormData;
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:uuid/uuid.dart';

import '../../../components/no_splash_factory.dart';
import '../../../logic/model/feed/data_model.dart';
import '../../../logic/model/login/login_response.dart';
import '../../../logic/model/oss_upload/datum.dart';
import '../../../logic/model/oss_upload/oss_upload_model.dart';
import '../../../logic/network/network_repo.dart';
import '../../../pages/feed/reply/emoji_panel.dart';
import '../../../pages/feed/reply/reply_dialog.dart' show ReplyType;
import '../../../pages/feed/reply/toolbar_icon_button.dart';
import '../../../utils/extensions.dart';
import '../../../utils/app_theme.dart';
import '../../../utils/oss/aliyunoss_client.dart';
import '../../../utils/oss/aliyunoss_config.dart';
import '../../../utils/oss_util.dart';
import '../../../utils/utils.dart';
import '../../../utils/storage_util.dart';
import '../../../constants/constants.dart';

enum PanelType { none, keyboard, emoji }

class ReplyPage extends StatefulWidget {
  const ReplyPage({
    super.key,
    this.type,
    this.id,
    this.username,
    this.targetType,
    this.targetId,
    this.title,
  });

  final ReplyType? type;
  final dynamic id;
  final String? username;
  final String? targetType;
  final dynamic targetId;
  final String? title;

  @override
  State<ReplyPage> createState() => _ReplyPageState();
}

class _ReplyPageState extends State<ReplyPage>
    with SingleTickerProviderStateMixin {
  /// 键盘态回复卡的下移补偿（dp），与「键盘态卡片底边距置 0」配套。
  ///
  /// 真机截图实测（1000379938/1000379949，936×2048，以卡片 16dp
  /// 水平边距 =41px 定标 2.5625 px/dp）：键盘弹起时卡片白区底边
  /// 在 y=1234，可见键盘框顶边在 y≈1264，缝 ≈30px ≈ 11.7dp。
  /// 面板占位高度 = viewInsets.bottom（IME 窗口高度），卡片的底
  /// 边距外缘被顶在窗口顶边上；两张截图里可见键盘框顶与窗口顶
  /// 边几乎重合（差约 1px），即这条缝基本就是卡片自带的 12dp
  /// 底边距本身。修法：键盘态把卡片底边距置 0（补回 12dp），
  /// 再用 changeKeyboardPanelHeight 把占位高度扣掉本常量 3dp，
  /// 合计下移 15dp，卡片底边最终压住键盘框顶约 3.3dp（在允许
  /// 的 6dp 内），缝被消除。前两轮（miuix4 改占位涂色、miuix5
  /// 加整页变暗层）改的是缝里透出什么，本轮改的是卡片位置本身。
  static const double _keyboardCardDownShift = 3;

  late final _focusNode = FocusNode();
  late final _controller = ChatBottomPanelContainerController<PanelType>();
  late final _replyContentController = TextEditingController(
      text: widget.targetType == 'tag' ? '#${widget.title}# ' : null);
  // PanelType _currentPanelType = PanelType.none;
  bool _readOnly = false;
  final _readOnlyStream = StreamController<bool>();
  late final _enableSend = StreamController<bool>();
  bool _enablePublish = false;
  bool _publishing = false;
  final _publishStream = StreamController<bool>();
  bool _selectKeyboard = true;
  final _keyboardStream = StreamController<bool>.broadcast();

  final _checkBoxStream = StreamController<bool>();
  bool _checkBoxValue = false;
  final TextEditingController _captchaController = TextEditingController();

  late final _imagePicker = ImagePicker();
  late final _pathStream = StreamController<List<String>>();
  late final _pathList = <String>[];
  late final _modelList = <OssUploadModel>[];
  String? _pic;

  late final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    () async {
      await Future.delayed(const Duration(milliseconds: 300));
      if (mounted) {
        _focusNode.requestFocus();
      }
    }();
  }

  @override
  void dispose() async {
    _readOnlyStream.close();
    _enableSend.close();
    _focusNode.dispose();
    _publishStream.close();
    _checkBoxStream.close();
    _pathStream.close();
    _replyContentController.dispose();
    _captchaController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // GetDialogRoute 不继承 GetMaterialApp builder 里的 AnimatedTheme，
    // 深色模式下 Theme.of(context) 会拿到浅色主题，导致弹窗背景发白。
    // 按 main.dart 同样的逻辑算出实际亮度，对不上就手动套一层正确的主题。
    final effectiveBrightness = switch (GStorage.getThemeMode()) {
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
      ThemeMode.system => MediaQuery.platformBrightnessOf(context),
    };
    // 键盘是否弹起（viewInsets 与面板包的占位高度同源）。键盘态
    // 需要把卡片底边距置 0 贴住键盘，见 _keyboardCardDownShift。
    final keyboardUp = MediaQuery.viewInsetsOf(context).bottom > 0;
    Widget content = MediaQuery.removePadding(
        removeTop: true,
        context: context,
        child: Scaffold(
          resizeToAvoidBottomInset: false,
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
              // 变暗层由本页自带，不再依赖路线 barrier。原先变暗只靠
              // GetDialogRoute 的 barrier（0x80000000）：键盘弹起时面板
              // 占位按 viewInsets.bottom（=IME 窗口高度）把卡片顶到键盘
              // 窗口顶边，而本机透明皮肤键盘的窗口顶部有约 27dp 的透明
              // 边距，绘制内容比窗口顶边低一截——卡片（含 12dp 底边距）
              // 与可见键盘之间留出一条缝，缝落在 IME 窗口范围内，下层
              // 页面以接近原亮度透出，应用窗口里的 barrier 变暗盖不住
              // 它（miuix5 话题发布截图实测：缝内亮度约 245，正常
              // barrier 区约 123）。把同色变暗层铺满本页（含键盘占位
              // 区，占位 widget 本身仍保持全透明）后，缝里透出的是经
              // 本页变暗的下层页面，与上方均匀一致、一直覆盖到可见
              // 键盘顶边。各入口路线的 barrierColor 已同步改透明，
              // 避免双层变暗叠加。
              const Positioned.fill(
                child: ColoredBox(color: Color(0x80000000)),
              ),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                    child: InkWell(
                      highlightColor: Colors.transparent,
                      splashColor: Colors.transparent,
                      splashFactory: NoSplashFactory(),
                      onTap: () {
                        FocusScope.of(context).unfocus();
                        Get.back();
                      },
                    ),
                  ),
                  _buildInputView(keyboardUp: keyboardUp),
                  _buildImagePreview(),
                  _buildPanelContainer(),
                ],
              ),
            ],
          ),
        ));
    if (Theme.of(context).brightness != effectiveBrightness) {
      final staticColor =
          GStorage.settings.get(SettingsBoxKey.staticColor, defaultValue: 0);
      content = Theme(
        data: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Constants.seedColors[staticColor],
            brightness: effectiveBrightness,
          ),
          fontFamily: appFontFamily,
          useMaterial3: true,
        ),
        child: MiuixTheme(
          data: appMiuixThemeData(effectiveBrightness),
          child: content,
        ),
      );
    }
    return content;
  }

  Widget _buildPanelContainer() {
    return ChatBottomPanelContainer<PanelType>(
      controller: _controller,
      inputFocusNode: _focusNode,
      // 键盘态占位高度扣掉 _keyboardCardDownShift，让卡片再下移
      // 一点、底边压住可见键盘框顶；包内在回调之后还有
      // safeAreaBottom 兜底，高度不会被扣成负数。此回调只在
      // 键盘态占位构建时调用，无键盘/表情面板态不受影响。
      changeKeyboardPanelHeight: (height) => height - _keyboardCardDownShift,
      otherPanelWidget: (type) {
        if (type == null) return const SizedBox.shrink();
        switch (type) {
          case PanelType.emoji:
            return _buildEmojiPickerPanel();
          default:
            return const SizedBox.shrink();
        }
      },
      // onPanelTypeChange: (panelType, data) {
      //   debugPrint('panelType: $panelType');
      //   switch (panelType) {
      //     case ChatBottomPanelType.none:
      //       _currentPanelType = PanelType.none;
      //       break;
      //     case ChatBottomPanelType.keyboard:
      //       _currentPanelType = PanelType.keyboard;
      //       break;
      //     case ChatBottomPanelType.other:
      //       if (data == null) return;
      //       switch (data) {
      //         case PanelType.emoji:
      //           _currentPanelType = PanelType.emoji;
      //           break;
      //         default:
      //           _currentPanelType = PanelType.none;
      //           break;
      //       }
      //       break;
      //   }
      // },
      // 默认容器会把 panelBgColor 涂满整个面板区，包括键盘态的等高
      // 占位区——透明输入法会透出一整条纯色带。改走自定义容器：
      // 键盘态不涂色，让下层帖子详情页透出来；其余状态保持原底色。
      // 注意 none 态也不能涂色：buildInPanel(none) 返回的是包内建的
      // 安全区占位（SizedBox 高 = viewPadding.bottom，即手势条高度），
      // 一旦给它涂 surfaceContainer，卡片下方到屏幕底边就会出现一条
      // 与变暗下层页面不连贯的纯色带（根部导航栏透明管不到这块，
      // 因为它不是系统栏，而是本页自己画的 widget）。只有 other
      // （表情面板）态才需要底色衬托面板内容。
      customPanelContainer: (panelType, data) => AnimatedSize(
        alignment: Alignment.topCenter,
        duration: const Duration(milliseconds: 200),
        curve: Curves.linear,
        child: Container(
          color: panelType == ChatBottomPanelType.other
              ? MiuixTheme.of(context).colors.surfaceContainer
              : Colors.transparent,
          child: _controller.buildInPanel(panelType) ?? const SizedBox.shrink(),
        ),
      ),
    );
  }

  Widget _buildEmojiPickerPanel() {
    double height = 200;
    final keyboardHeight = _controller.keyboardHeight;
    if (keyboardHeight != 0) {
      height = max(height, keyboardHeight);
    }
    return SizedBox(
      height: height,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
        child: EmotePanel(
          index: 1,
          onClick: (emoji) {
            _onChooseEmote(emoji);
            if (!_enablePublish) {
              _enablePublish = true;
              _publishStream.add(true);
            }
          },
        ),
      ),
    );
  }

  Widget _buildImagePreview() {
    return StreamBuilder(
      stream: _pathStream.stream,
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data.isSafeNotEmpty) {
          return Container(
            height: 85,
            color: MiuixTheme.of(context).colors.surfaceContainer,
            padding: const EdgeInsets.only(bottom: 10),
            child: Scrollbar(
              controller: _scrollController,
              thumbVisibility: Utils.isDesktop,
              interactive: Utils.isDesktop,
              thickness: Utils.isDesktop ? 8 : 0,
              child: ListView.separated(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 15),
                itemCount: _pathList.length,
                itemBuilder: (context, index) => GestureDetector(
                  onTap: () {
                    _pathList.removeAt(index);
                    _modelList.removeAt(index);
                    _pathStream.add(_pathList);
                  },
                  child: Image(
                    height: 75,
                    fit: BoxFit.fitHeight,
                    filterQuality: FilterQuality.low,
                    image: FileImage(File(_pathList[index])),
                  ),
                ),
                separatorBuilder: (_, index) => const SizedBox(width: 10),
              ),
            ),
          );
        } else {
          return const SizedBox.shrink();
        }
      },
    );
  }

  Widget _buildInputView({required bool keyboardUp}) {
    return Container(
      margin: EdgeInsets.only(
        left: 16,
        right: 16,
        // 键盘态底边距置 0：占位把边距外缘顶在 IME 窗口顶边上，
        // 留着 12dp 就会在卡片与可见键盘之间留一条等高的缝；
        // 其余状态保持 12dp 悬浮卡样式。见 _keyboardCardDownShift。
        bottom: keyboardUp ? 0 : 12,
      ),
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.all(Radius.circular(24)),
        color: MiuixTheme.of(context).colors.surfaceContainer,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding:
                const EdgeInsets.only(top: 12, right: 15, left: 15, bottom: 10),
            child: Form(
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: Listener(
                onPointerUp: (event) {
                  if (_readOnly) {
                    updatePanelType(PanelType.keyboard);
                    if (!_selectKeyboard) {
                      _selectKeyboard = true;
                      _keyboardStream.add(true);
                    }
                  }
                },
                child: StreamBuilder(
                  initialData: false,
                  stream: _readOnlyStream.stream,
                  builder: (context, snapshot) => TextField(
                    minLines: 4,
                    maxLines: 8,
                    maxLength: 500,
                    autofocus: false,
                    focusNode: _focusNode,
                    readOnly: snapshot.data ?? false,
                    controller: _replyContentController,
                    onChanged: (value) {
                      bool isNotEmpty = value.replaceAll('\n', '').isNotEmpty;
                      if (isNotEmpty && !_enablePublish) {
                        _enablePublish = true;
                        _publishStream.add(true);
                      } else if (!isNotEmpty && _enablePublish) {
                        _enablePublish = false;
                        _publishStream.add(false);
                      }
                    },
                    decoration: InputDecoration(
                      hintText: widget.username != null
                          ? '回复: ${widget.username}'
                          : '发布${widget.title != null ? '于: ${widget.title}' : '动态'}',
                      border: InputBorder.none,
                      hintStyle: const TextStyle(fontSize: 14),
                    ),
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
              ),
            ),
          ),
          Divider(
            height: 1,
            color: Theme.of(context).dividerColor.withOpacity(0.1),
          ),
          Container(
            height: 52,
            padding: const EdgeInsets.only(left: 12, right: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                StreamBuilder(
                  initialData: true,
                  stream: _keyboardStream.stream,
                  builder: (_, snapshot) => ToolbarIconButton(
                    onPressed: () {
                      if (!_selectKeyboard) {
                        _selectKeyboard = true;
                        _keyboardStream.add(true);
                        updatePanelType(PanelType.keyboard);
                      }
                    },
                    icon: const Icon(Icons.keyboard, size: 22),
                    selected: snapshot.data!,
                  ),
                ),
                const SizedBox(width: 4),
                StreamBuilder(
                  initialData: true,
                  stream: _keyboardStream.stream,
                  builder: (_, snapshot) => ToolbarIconButton(
                    onPressed: () {
                      if (_selectKeyboard) {
                        _selectKeyboard = false;
                        _keyboardStream.add(false);
                        updatePanelType(PanelType.emoji);
                      }
                    },
                    icon: const Icon(Icons.emoji_emotions, size: 22),
                    selected: !snapshot.data!,
                  ),
                ),
                const SizedBox(width: 4),
                ToolbarIconButton(
                  selected: false,
                  icon: const Icon(Icons.image, size: 22),
                  onPressed: () async {
                    List<XFile> pickedFiles = await _imagePicker.pickMultiImage(
                      limit: 9,
                      imageQuality: 100,
                    );
                    if (pickedFiles.isNotEmpty) {
                      try {
                        for (int i = 0; i < pickedFiles.length; i++) {
                          if (_pathList.length == 9) {
                            SmartDialog.dismiss();
                            SmartDialog.showToast('最多选择9张图片');
                            if (i != 0) {
                              _pathStream.add(_pathList);
                            }
                            break;
                          } else {
                            SmartDialog.showLoading(
                                msg: '正在加载图片: $i/${pickedFiles.length}');
                            Uint8List imageBytes =
                                await pickedFiles[i].readAsBytes();
                            ui.Image image =
                                await decodeImageFromList(imageBytes);
                            int width = image.width;
                            int height = image.height;
                            Digest md5Hash = md5.convert(imageBytes);
                            String mimeType =
                                lookupMimeType(pickedFiles[i].path) ??
                                    'image/png';
                            String name =
                                '${const Uuid().v1().replaceAll('-', '')}.${mimeType.replaceFirst('image/', '')}';
                            OssUploadModel uploadModel = OssUploadModel(
                              name: name,
                              resolution: '${width}x$height',
                              md5: md5Hash.toString(),
                            );
                            _pathList.add(pickedFiles[i].path);
                            _modelList.add(uploadModel);
                            if (i == pickedFiles.length - 1) {
                              SmartDialog.dismiss();
                              _pathStream.add(_pathList);
                            }
                          }
                        }
                      } catch (e) {
                        SmartDialog.dismiss();
                        debugPrint(e.toString());
                      }
                    }
                  },
                ),
                const Spacer(),
                StreamBuilder(
                  initialData: false,
                  stream: _checkBoxStream.stream,
                  builder: (_, snapshot) => TextButton(
                    onPressed: () {
                      _checkBoxValue = !_checkBoxValue;
                      _checkBoxStream.add(_checkBoxValue);
                    },
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 9),
                      visualDensity: const VisualDensity(
                        horizontal: -2,
                        vertical: -2,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Checkbox(
                          side: BorderSide(
                              width: 2,
                              color: Theme.of(context).colorScheme.outline),
                          fillColor: WidgetStateProperty.resolveWith((states) {
                            if (states.contains(WidgetState.selected)) {
                              return Theme.of(context).colorScheme.primary;
                            }
                            return null;
                          }),
                          value: _checkBoxValue,
                          onChanged: null,
                          visualDensity:
                              const VisualDensity(horizontal: -4, vertical: -4),
                        ),
                        Text(
                          widget.type == null ? '仅自己可见' : '回复并转发',
                          style: TextStyle(
                            height: 1,
                            color: _checkBoxValue
                                ? Theme.of(context).colorScheme.onSurface
                                : Theme.of(context).colorScheme.outline,
                          ),
                          strutStyle: const StrutStyle(height: 1, leading: 0),
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                StreamBuilder(
                  initialData: false,
                  stream: _publishStream.stream,
                  builder: (_, snapshot) => FilledButton.tonal(
                    onPressed: snapshot.data == true ? _onPublish : null,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      visualDensity: const VisualDensity(
                        horizontal: -2,
                        vertical: -2,
                      ),
                    ),
                    child: const Text('发布'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  updatePanelType(PanelType type) async {
    final isSwitchToKeyboard = PanelType.keyboard == type;
    final isSwitchToEmojiPanel = PanelType.emoji == type;
    bool isUpdated = false;
    switch (type) {
      case PanelType.keyboard:
        updateInputView(isReadOnly: false);
        break;
      case PanelType.emoji:
        isUpdated = updateInputView(isReadOnly: true);
        break;
      default:
        break;
    }

    updatePanelTypeFunc() {
      _controller.updatePanelType(
        isSwitchToKeyboard
            ? ChatBottomPanelType.keyboard
            : ChatBottomPanelType.other,
        data: type,
        forceHandleFocus: isSwitchToEmojiPanel
            ? ChatBottomHandleFocus.requestFocus
            : ChatBottomHandleFocus.none,
      );
    }

    if (isUpdated) {
      // Waiting for the input view to update.
      WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
        updatePanelTypeFunc();
      });
    } else {
      updatePanelTypeFunc();
    }
  }

  hidePanel() async {
    if (_focusNode.hasFocus) {
      await Future.delayed(const Duration(milliseconds: 100));
      _focusNode.unfocus();
    }
    updateInputView(isReadOnly: false);
    if (ChatBottomPanelType.none == _controller.currentPanelType) return;
    _controller.updatePanelType(ChatBottomPanelType.none);
  }

  bool updateInputView({
    required bool isReadOnly,
  }) {
    if (_readOnly != isReadOnly) {
      _readOnly = isReadOnly;
      _readOnlyStream.add(_readOnly);
      return true;
    }
    return false;
  }

  Future _onPublish() async {
    if (_publishing) return;
    _publishing = true;
    try {
      if (_pathList.isNotEmpty) {
        OssDatum? data = await OssUtil.onPostOSSUploadPrepare(
          'image',
          'feed',
          _modelList,
        );
        if (data != null) {
          _pic = data.fileInfo!
              .map((item) =>
                  '${data.uploadPrepareInfo!.uploadImagePrefix}/${item.uploadFileName}')
              .toList()
              .join(',');
          AliyunOssClient client = AliyunOssClient(
            accessKeyId: data.uploadPrepareInfo!.accessKeyId!,
            accessKeySecret: data.uploadPrepareInfo!.accessKeySecret!,
            securityToken: data.uploadPrepareInfo!.securityToken!,
          );
          AliyunOssConfig config = AliyunOssConfig(
            endpoint: data.uploadPrepareInfo!.endPoint!,
            bucket: data.uploadPrepareInfo!.bucket!,
            directory: "feed",
          );
          for (int i = 0; i < data.fileInfo!.length; i++) {
            SmartDialog.showLoading(msg: '正在上传图片 $i/${data.fileInfo!.length}');
            AliyunOssResult result = await client.upload(
              id: i.toString(),
              config: config,
              ossFileName:
                  data.fileInfo![i].uploadFileName!.replaceFirst('feed', ''),
              filePath: _pathList[i],
            );
            if (result.state == AliyunOssResultState.fail) {
              SmartDialog.dismiss();
              SmartDialog.showToast('第 $i 张图片上传失败，请稍后重试');
              return;
            }
          }
        }
      }
      SmartDialog.showLoading(msg: '正在发布');
      if (widget.id == null) {
        Response response = await NetworkRepo.postCreateFeed(
          FormData.fromMap(
            {
              'type': 'feed',
              if (widget.targetType != null) 'targetType': widget.targetType,
              if (widget.targetType == 'apk') 'type': 'comment',
              if (widget.targetId != null) 'targetId': widget.targetId,
              'message': _replyContentController.text,
              'status': _checkBoxValue ? -1 : 1,
              'pic': _pic,
            },
          ),
        );
        if (response.data is! Map ||
            response.data['messageStatus'] != 'err_request_captcha') {
          readApiObject(response);
        }
        LoginResponse data = LoginResponse.fromJson(response.data);
        if (!data.message.isNullOrEmpty) {
          SmartDialog.dismiss();
          SmartDialog.showToast(data.message!);
          if (data.messageStatus == 'err_request_captcha') {
            _onGetCaptcha();
          }
        } else if (data.data != null) {
          SmartDialog.dismiss();
          SmartDialog.showToast('发布成功');
          Get.back();
        }
      } else {
        Response response = await NetworkRepo.postReply(
          FormData.fromMap({
            'message': _replyContentController.text,
            'replyAndForward': _checkBoxValue ? 1 : 0,
            'pic': _pic,
          }),
          widget.id,
          widget.type!.name,
        );
        if (response.data is! Map ||
            response.data['messageStatus'] != 'err_request_captcha') {
          readApiObject(response);
        }
        DataModel data = DataModel.fromJson(response.data);
        if (!data.message.isNullOrEmpty) {
          SmartDialog.dismiss();
          SmartDialog.showToast(data.message!);
          if (data.messageStatus == 'err_request_captcha') {
            _onGetCaptcha();
          }
        } else if (data.data != null) {
          SmartDialog.dismiss();
          SmartDialog.showToast('回复成功');
          Get.back(result: {'data': data.data});
        }
      }
    } catch (e) {
      SmartDialog.dismiss();
      SmartDialog.showToast(ApiFailure.fromError(e).message);
    } finally {
      _publishing = false;
      SmartDialog.dismiss(status: SmartStatus.loading);
    }
  }

  Future<void> _onGetCaptcha() async {
    try {
      Response response = await NetworkRepo.getValidateCaptcha();
      if (mounted) {
        _captchaController.clear();
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('验证码'),
            content: IntrinsicHeight(
              child: Row(
                children: [
                  Expanded(
                    flex: 1,
                    child: Image.memory(response.data),
                  ),
                  Expanded(
                    flex: 1,
                    child: TextField(
                      controller: _captchaController,
                      autofocus: true,
                      inputFormatters: [
                        LengthLimitingTextInputFormatter(4),
                        FilteringTextInputFormatter.allow(
                            RegExp("[0-9a-zA-Z]")),
                      ],
                      decoration: const InputDecoration(
                        border: UnderlineInputBorder(),
                        filled: true,
                        labelText: '验证码',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Get.back(),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () {
                  Get.back();
                  _postRequestValidate();
                },
                child: const Text('验证并继续'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      SmartDialog.showToast('无法获取验证码：${ApiFailure.fromError(e).message}');
      debugPrint(e.toString());
    }
  }

  Future<void> _postRequestValidate() async {
    try {
      Response response = await NetworkRepo.postRequestValidate(
        FormData.fromMap({
          'type': 'err_request_captcha',
          'code': _captchaController.text,
        }),
      );
      LoginResponse data = LoginResponse.fromJson(response.data);
      if (data.data == '验证通过') {
        _onPublish();
      } else if (!data.message.isNullOrEmpty) {
        SmartDialog.showToast(data.message!);
        if (data.message == "请输入正确的图形验证码") {
          _onGetCaptcha();
        }
      }
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  void _onChooseEmote(String emoji) {
    if (!_enablePublish) {
      _enablePublish = true;
      _publishStream.add(true);
    }
    final int cursorPosition = _replyContentController.selection.baseOffset;
    final String currentText = _replyContentController.text;
    final String newText = currentText.substring(0, cursorPosition) +
        emoji +
        currentText.substring(cursorPosition);
    _replyContentController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: cursorPosition + emoji.length),
    );
  }
}

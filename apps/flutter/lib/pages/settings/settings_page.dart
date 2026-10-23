// ignore_for_file: constant_identifier_names

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../components/dialog.dart';
import '../../components/update_check_tile.dart';
import '../../logic/app_update/update_preferences.dart';
import '../../logic/accounts/account_store.dart';
import '../../components/settings/drop_down_menu_item.dart';
import '../../components/settings/item_title.dart';
import '../../components/settings/switch_item.dart';
import '../../constants/constants.dart';
import '../../pages/blacklist/black_list_page.dart' show BlackListType;
import '../../utils/cache_util.dart';
import '../../utils/storage_util.dart';
import '../../utils/global_data.dart';
import '../../logic/local_follow/local_follow_store.dart';
import '../local_follow/local_follow_page.dart';
import 'device_identity_page.dart';

enum ImageQuality {
  AUTO,
  ORIGIN,
  THUMBNAIL;

  String get label => switch (this) {
        ImageQuality.AUTO => '自动',
        ImageQuality.ORIGIN => '原图',
        ImageQuality.THUMBNAIL => '缩略图',
      };
}

enum SettingsSection {
  appearance('外观与字号', '动态取色、主题、深色模式与字体大小', Icons.palette_outlined),
  content('关注与内容', '本地关注、悄悄关注、账号关注与表情', Icons.feed_outlined),
  privacy('浏览与隐私', '用户与话题黑名单、浏览历史、外部链接', Icons.privacy_tip_outlined),
  storage('存储与更新', '图片缓存、版本与更新检查', Icons.storage_outlined),
  protocol('协议与设备', '设备标识与客户端请求参数', Icons.developer_mode);

  const SettingsSection(this.title, this.description, this.icon);
  final String title, description;
  final IconData icon;
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  SettingsSection _section = SettingsSection.appearance;
  Widget _categories(bool wide) => ListView(
        padding: const EdgeInsets.all(12),
        children: [
          MiuixCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final section in SettingsSection.values)
                  MiuixArrowPreference(
                    title: section.title,
                    summary: section.description,
                    startAction: Icon(section.icon),
                    onClick: () {
                      if (wide) {
                        setState(() => _section = section);
                      } else {
                        Get.to(() => SettingsDetailPage(section: section));
                      }
                    },
                  ),
                ValueListenableBuilder(
                  valueListenable: GStorage.settings
                      .listenable(keys: [AccountStore.storageKey]),
                  builder: (context, _, __) => MiuixArrowPreference(
                    title: '账号管理',
                    summary:
                        '已保存 ${AccountStore().accounts.length} 个账号 · 切换、添加或移除',
                    startAction: const Icon(Icons.switch_account_outlined),
                    onClick: () => Get.toNamed('/accounts'),
                  ),
                ),
                MiuixArrowPreference(
                  title: '关于',
                  startAction: const Icon(Icons.info_outline),
                  onClick: () async {
                    final info = await PackageInfo.fromPlatform();
                    if (mounted) {
                      Get.toNamed('/about', parameters: {
                        'version': '${info.version}(${info.buildNumber})'
                      });
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      );
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('设置')),
        body: SafeArea(
            top: false,
            child: LayoutBuilder(builder: (context, constraints) {
              final wide = constraints.maxWidth >= 840;
              return wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                          SizedBox(width: 320, child: _categories(true)),
                          const VerticalDivider(width: 1),
                          Expanded(
                              child: SettingsDetailPage(
                                  key: ValueKey(_section),
                                  section: _section,
                                  embedded: true)),
                        ])
                  : _categories(false);
            })),
      );
}

class SettingsDetailPage extends StatefulWidget {
  const SettingsDetailPage(
      {super.key, required this.section, this.embedded = false});
  final SettingsSection section;
  final bool embedded;
  @override
  State<SettingsDetailPage> createState() => _SettingsDetailPageState();
}

class _SettingsDetailPageState extends State<SettingsDetailPage> {
  final _settingsController = SettingsController();
  @override
  void initState() {
    super.initState();
    if (widget.section == SettingsSection.storage) {
      _settingsController.getCacheSize();
    }
  }

  List<Widget> _items(BuildContext context) => switch (widget.section) {
        SettingsSection.appearance => [
            const SwitchItem(
              icon: Icons.palette_outlined,
              title: '动态取色',
              subtitle: '根据系统配色调整应用主题',
              boxKey: SettingsBoxKey.useMaterial,
              defaultValue: true,
            ),
            ValueListenableBuilder(
              valueListenable: GStorage.settings
                  .listenable(keys: [SettingsBoxKey.useMaterial]),
              builder: (context, settings, _) => DropDownMenuItem(
                icon: Icons.format_color_fill,
                title: '主题颜色',
                subtitle: '关闭动态取色后可选择固定配色',
                boxKey: SettingsBoxKey.staticColor,
                enabled: !GStorage.useMaterial,
                items: Constants.themeType
                    .map((type) => DropdownMenuItem<int>(
                          value: Constants.themeType.indexOf(type),
                          child: Text(type),
                        ))
                    .toList(),
              ),
            ),
            const DropDownMenuItem(
              icon: Icons.dark_mode_outlined,
              title: '深色模式',
              subtitle: '选择浅色、深色或跟随系统',
              boxKey: SettingsBoxKey.selectedTheme,
              items: [
                DropdownMenuItem<int>(
                  value: 1,
                  child: Text('始终关闭'),
                ),
                DropdownMenuItem<int>(
                  value: 2,
                  child: Text('始终开启'),
                ),
                DropdownMenuItem<int>(
                  value: 0,
                  child: Text('跟随系统'),
                ),
              ],
              forceAppUpdate: true,
            ),
            MiuixArrowPreference(
              title: '字体大小',
              summary: '调整界面文字大小 · ${GStorage.fontScale.toStringAsFixed(2)}x',
              startAction: const Icon(Icons.text_fields),
              onClick: () => showDialog<void>(
                context: context,
                builder: (context) => SliderDialog(
                  fontScale: GStorage.fontScale,
                  setData: (newValue) {
                    GStorage.setFontScale(newValue);
                    if (mounted) setState(() {});
                  },
                ),
              ),
            ),
          ],
        SettingsSection.content => [
            const ItemTitle(title: '关注'),
            ValueListenableBuilder(
              valueListenable:
                  GStorage.settings.listenable(keys: [SettingsBoxKey.isLogin]),
              builder: (context, _, __) => Column(children: [
                if (GlobalData().isLogin)
                  const SwitchItem(
                    icon: Icons.visibility_off_outlined,
                    title: '悄悄关注',
                    subtitle: '开启后，长按用户主页的关注按钮添加或取消。仅保存在本机，不会同步到账号',
                    boxKey: LocalFollowStore.enabledKey,
                    defaultValue: false,
                  )
                else
                  const MiuixBasicComponent(
                    startAction: Icon(Icons.person_add_alt_outlined),
                    title: '本地关注',
                    summary: '游客可在用户主页直接关注，并在底栏“关注”查看内容。名单仅保存在本机',
                  ),
                MiuixArrowPreference(
                  startAction: const Icon(Icons.manage_accounts_outlined),
                  title: '管理$localFollowLabel',
                  summary: '查看本机关注名单、进入用户主页或取消关注',
                  onClick: () => Get.to(() => const LocalFollowListPage()),
                ),
              ]),
            ),
            const SwitchItem(
              icon: Icons.emoji_emotions_outlined,
              title: '显示表情',
              subtitle: '将内容中的酷安表情标记显示为图片',
              boxKey: SettingsBoxKey.showEmoji,
              defaultValue: true,
            ),
          ],
        SettingsSection.privacy => [
            MiuixArrowPreference(
              title: '用户黑名单',
              summary: '管理屏蔽的用户，隐藏其动态',
              startAction: const Icon(Icons.block),
              onClick: () => Get.toNamed(
                '/blacklist/',
                arguments: {'type': BlackListType.user},
              ),
            ),
            MiuixArrowPreference(
              title: '话题黑名单',
              summary: '按关键词过滤相关话题内容',
              startAction: const Icon(Icons.block),
              onClick: () => Get.toNamed(
                '/blacklist/',
                arguments: {'type': BlackListType.topic},
              ),
            ),
            const SwitchItem(
              icon: Icons.history,
              title: '记录浏览历史',
              subtitle: '将浏览过的动态保存在本机，便于再次查看',
              boxKey: SettingsBoxKey.recordHistory,
              defaultValue: true,
            ),
            const SwitchItem(
              icon: Icons.travel_explore,
              title: '在浏览器中打开',
              subtitle: '使用系统浏览器打开外部网页链接',
              boxKey: SettingsBoxKey.openInBrowser,
              defaultValue: false,
            ),
          ],
        SettingsSection.storage => [
            ValueListenableBuilder(
              valueListenable: GStorage.settings
                  .listenable(keys: [UpdatePreferences.enabledKey]),
              builder: (context, _, __) => MiuixSwitchPreference(
                startAction: const Icon(Icons.update),
                title: '自动检查 c001apk 更新',
                summary: '每次启动时检查一次最新正式版本',
                value: UpdatePreferences(GStorage.settings).enabled,
                onChanged: (value) =>
                    UpdatePreferences(GStorage.settings).setEnabled(value),
              ),
            ),
            const UpdateCheckTile(),
            if (Platform.isAndroid)
              const SwitchItem(
                icon: Icons.system_update,
                title: '检查已安装应用更新',
                subtitle: '在应用列表中显示已安装应用的更新入口',
                boxKey: SettingsBoxKey.checkUpdate,
                defaultValue: true,
              ),
            Obx(
              () => MiuixArrowPreference(
                title: '清理缓存',
                summary: _settingsController.cacheSize.value.isNotEmpty
                    ? _settingsController.cacheSize.value
                    : null,
                startAction: const Icon(Icons.cleaning_services_outlined),
                onClick: () async {
                  await _settingsController.getCacheSize();
                  if (context.mounted) {
                    showDialog<void>(
                      context: context,
                      builder: (context) => ClearDialog(
                        cacheSize: _settingsController.cacheSize.value,
                        onClearCache: () async {
                          if (await CacheManage().clearCacheAll()) {
                            _settingsController.getCacheSize();
                          }
                        },
                      ),
                    );
                  }
                },
              ),
            ),
          ],
        SettingsSection.protocol => [
            MiuixArrowPreference(
              startAction: const Icon(Icons.smartphone),
              title: '导入官方设备标识',
              summary: '减少重复人机验证 · 获取说明与粘贴识别',
              onClick: () => Get.to(() => const DeviceIdentityPage()),
            ),
            MiuixArrowPreference(
              startAction: const Icon(Icons.developer_mode),
              title: '协议参数',
              summary: '配置客户端版本、设备与请求参数',
              onClick: () => Get.toNamed('/params'),
            ),
          ],
      };
  @override
  Widget build(BuildContext context) {
    final body = Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                children: [
                  if (widget.embedded) ItemTitle(title: widget.section.title),
                  MiuixCard(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: _items(context),
                    ),
                  ),
                ])));
    return widget.embedded
        ? body
        : Scaffold(
            appBar: AppBar(title: Text(widget.section.title)),
            body: SafeArea(top: false, child: body));
  }
}

class SettingsController {
  final RxString cacheSize = ''.obs;
  Future<void> getCacheSize() async {
    cacheSize.value = await CacheManage().loadApplicationCache();
  }
}

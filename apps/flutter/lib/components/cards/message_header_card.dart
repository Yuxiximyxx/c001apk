import 'package:c001apk_flutter/components/network_image.dart';
import 'package:flutter/material.dart';

import '../../components/source_container.dart';
import '../../logic/model/feed/datum.dart';
import '../../pages/login/login_page.dart';
import '../../utils/global_data.dart';
import '../../utils/miuix_palette.dart';
import '../../utils/storage_util.dart';

class MessageHeaderCard extends StatelessWidget {
  const MessageHeaderCard({
    super.key,
    this.userInfo,
  });

  final Datum? userInfo;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: miuixPageBackground(context),
      child: Stack(
        alignment: AlignmentDirectional.center,
        children: [
          if (!GlobalData().isLogin)
            AnchoredContainer(
              closedColor: miuixPageBackground(context),
              openColor: miuixPageBackground(context),
              closedShape: const StadiumBorder(),
              closedBuilder: (context, open) => FilledButton.tonal(
                onPressed: open,
                child: const Text('点击登录'),
              ),
              openBuilder: (context, close) => const LoginPage(),
            ),
          Visibility(
            maintainSize: true,
            maintainAnimation: true,
            maintainState: true,
            visible: GlobalData().isLogin,
            child: Row(
              children: [
                const SizedBox(width: 20),
                UserAvatarContainer(
                  uid: (userInfo?.uid ?? GlobalData().uid).toString(),
                  child: clipNetworkImage(
                    userInfo?.userAvatar ?? GStorage.userAvatar,
                    isAvatar: true,
                    width: 45,
                    height: 45,
                  ),
                ),
                const SizedBox(width: 10),
                Flexible(
                  flex: 75,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        () {
                          String username =
                              userInfo?.username ?? GlobalData().username;
                          try {
                            username = Uri.decodeComponent(username);
                          } catch (e) {
                            debugPrint(e.toString());
                          }
                          return username;
                        }(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            flex: 1,
                            child: Text(
                              'Lv.${userInfo?.level ?? GStorage.level}',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                          Text(
                            '${userInfo?.experience ?? GStorage.exp}/${userInfo?.nextLevelExperience ?? GStorage.nextExp}',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      LinearProgressIndicator(
                        value: (userInfo?.experience ?? GStorage.exp) /
                            (userInfo?.nextLevelExperience ?? GStorage.nextExp),
                        borderRadius: const BorderRadius.all(
                          Radius.circular(10),
                        ),
                      ),
                    ],
                  ),
                ),
                const Expanded(flex: 25, child: SizedBox()),
                const SizedBox(width: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

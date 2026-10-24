# 公告与 c001apk 小助手

入口为“我的 → 私信与信息 → c001apk 小助手”，游客也可查看。酷安小秘书与账号私信维持原有登录要求。小助手列表只读取公告表的标题、摘要、日期、重要标记和未读状态；点开才下载该篇 Markdown，弹窗可展开为完整阅读页，支持上下键滚动、返回和 Esc。

## 公告来源与维护

公告数据单独保存在本仓库的 [announcements 分支](https://github.com/TG-Twilight/c001apk/tree/announcements)，根目录 README 有完整发布说明。正文与索引在该分支的 announcements/ 目录；应用代码继续保存在 main，不把测试公告作为应用内置内容。公告更新不需要重新构建应用。2026-10-23 已按用户授权建立目录并发布第一篇明确标注的测试公告，提交 8c35603；不改 main／Release／workflow，分支无工作流且现有构建仅监听 main 的应用／workflow 路径。

客户端入口为 [index.json](https://raw.githubusercontent.com/TG-Twilight/c001apk/announcements/announcements/index.json)。schemaVersion=1，revision 每次变更递增，announcements 是完整列表。每项含 id、title、summary、publishedAt（带时区）、contentRevision、reminderRevision、important、path、sha256；可选 withdrawn、expiresAt。ID 永不复用于其他公告；正文路径限本目录 Markdown，SHA256 为原文件字节摘要。

- 发布新公告：新增 ID、Markdown 文件、索引条目，并提高顶层 revision。
- 正文修订：提高 contentRevision，更换正文文件名、SHA256，提高顶层 revision；普通纠错保留 reminderRevision，不重复提醒。
- 再次通知：明确提高 reminderRevision；该修订重新未读，important=true 才允许自动弹窗。
- 撤回：withdrawn=true 或从完整索引移除，同时提高顶层 revision；不要只删除正文。新版本的合法空数组表示撤回全部。

正文及索引应同次提交。GitHub 缓存传播期间若表／正文不匹配，客户端拒绝缓存错误内容，保留原记录并允许重试。

## 检查与提醒

冷启动后台检查一次；从后台回前台距上次成功检查6小时补查；进入小助手超过15分钟补查；手动刷新立即检查。同类并发请求合并，自动失败至少退避1分钟；无后台常驻轮询。设置“存储与更新 → 自动检查公告”独立于版本更新，关闭不影响主动查看／刷新。

普通公告静默进入列表；重要公告每个提醒修订最多自动展示一次，仅选最新一篇，其余历史保留未读但不补弹。删除最新公告不会使旧公告依次弹出。新版本更新优先，同次运行弹过更新后不自动弹公告；非根页、后台、现有弹窗／菜单／验证期间不打断。正文请求后再次核对修订、撤回和页面状态。

自动卡片成功显示正文才记录已提醒，关闭不等于已读；主动打开并显示正文或展开阅读才标记该篇已读。进入列表不清空未读。切换酷安账号不重置本机记录。

## 缓存与失败

复用 Hive，单独 announcements Box 保存小表、阅读／提醒记录与按需正文。正文最多20篇且总计2MiB，单篇最多256KiB；菜单可“清理公告正文缓存”，已读／提醒记录保留。图片沿用现有图片机制，不为整个公告列表预下载图片。

只有完整合法且未回退的索引能替换本地表。HTTP失败、HTML、缺字段、重复ID、同版本冲突或旧表均保留原表。正文404不等于公告撤回；旧修订缓存不作为最新正文呈现。撤回／移除清理正文、扣除未读，但保留轻量阅读／提醒凭据；到期自动隐藏并通知界面。离线时只能反映上次成功同步的清单。

请求使用独立 Dio，不加入酷安账号 Cookie、Token 或设备头。测试均用合成表与临时 Hive；本次另用上述公开测试公告验收 GitHub 实际读取。服务实现 `lib/logic/announcements/`，UI `components/announcement_*.dart` 和 `pages/announcements/`，回归 `test/announcements/`。

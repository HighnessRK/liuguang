import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../core/store.dart';
import '../core/updates.dart';
import '../ui/glass.dart';
import 'settings.dart' show SettingsDetail;

Future<void> checkForAppUpdates(BuildContext context, AppStore store) async {
  final service = UpdateService(store);
  try {
    await service.configure();
    if (!service.auto) return;
    final release = await service.check();
    if (release == null ||
        compareVersions(release.version, appVersion) <= 0 ||
        !service.notify ||
        !context.mounted) {
      return;
    }
    if (store.prefs.getString('update_seen') == release.version) return;
    await store.prefs.setString('update_seen', release.version);
    if (context.mounted) {
      await floatingRelease(
        context,
        ReleaseCard(service: service, release: release),
      );
    }
  } catch (_) {
    /* Scheduled checks remain quiet; details are in diagnostics. */
  }
}

class UpdatesScreen extends StatefulWidget {
  final AppStore store;
  final UpdateService? service;
  const UpdatesScreen({super.key, required this.store, this.service});
  @override
  State<UpdatesScreen> createState() => _UpdatesScreenState();
}

class _UpdatesScreenState extends State<UpdatesScreen> {
  late final service = widget.service ?? UpdateService(widget.store);
  bool checking = false;
  ReleaseInfo? release;
  String? message;
  Future<void> check() async {
    setState(() {
      checking = true;
      message = null;
    });
    try {
      final value = await service.check();
      if (mounted) {
        setState(() {
          release = value;
          message = value == null
              ? '暂未发布版本'
              : compareVersions(value.version, appVersion) <= 0
              ? '当前已是最新版本'
              : '发现新版本';
        });
      }
      if (value != null &&
          compareVersions(value.version, appVersion) > 0 &&
          mounted) {
        setState(() => checking = false);
        await floatingRelease(
          context,
          ReleaseCard(service: service, release: value),
        );
      }
    } catch (_) {
      if (mounted) setState(() => message = '检查失败，请重试或切换下载源');
    } finally {
      if (mounted) setState(() => checking = false);
    }
  }

  @override
  Widget build(BuildContext context) => SettingsDetail(
    title: '应用更新',
    children: [
      const SectionLabel('下载源'),
      GlassSegments(
        labels: const ['GitHub', 'Gitee'],
        selected: service.source == 'github' ? 0 : 1,
        onChanged: (v) async {
          await service.configure(source: v == 0 ? 'github' : 'gitee');
          if (mounted) {
            setState(() {
              release = null;
              message = null;
            });
          }
        },
      ),
      const SizedBox(height: 16),
      Glass(
        child: Column(
          children: [
            Row(
              children: [
                const Expanded(child: Text('自动检查更新')),
                GlassToggle(
                  value: service.auto,
                  onChanged: (v) async {
                    await service.configure(auto: v);
                    if (mounted) setState(() {});
                  },
                ),
              ],
            ),
            Text(
              '启动时及每天 09:00、21:00 检查；系统省电策略可能延迟后台任务。',
              style: TextStyle(color: muted(context), fontSize: 12),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Expanded(child: Text('更新提醒')),
                GlassToggle(
                  value: service.notify,
                  onChanged: (v) async {
                    await service.configure(notify: v, requestPermission: v);
                    if (mounted) setState(() {});
                  },
                ),
              ],
            ),
            Text(
              '后台通知需允许系统通知。强制停止后，重新打开应用恢复检查。',
              style: TextStyle(color: muted(context), fontSize: 12),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      GlassButton(
        '检查更新',
        primary: true,
        busy: checking,
        onTap: checking ? null : check,
      ),
      if (message != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(message!, textAlign: TextAlign.center),
        ),
      const SectionLabel('更新日志'),
      const VersionLog(),
      const SizedBox(height: 20),
      GlassButton(
        '诊断日志',
        icon: Icons.article_outlined,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const DiagnosticsScreen()),
        ),
      ),
    ],
  );
}

class ReleaseCard extends StatefulWidget {
  final UpdateService service;
  final ReleaseInfo release;
  const ReleaseCard({super.key, required this.service, required this.release});
  @override
  State<ReleaseCard> createState() => _ReleaseCardState();
}

class _ReleaseCardState extends State<ReleaseCard> {
  CancelToken? token;
  int received = 0, total = 0;
  String? message;
  String? downloadedPath;
  @override
  void dispose() {
    token?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    widget.service
        .downloadedPackage(widget.release)
        .then((path) {
          if (mounted &&
              token == null &&
              downloadedPath == null &&
              path != null) {
            setState(() => downloadedPath = path);
          }
        })
        .catchError((Object _) {});
  }

  Future<void> download() async {
    setState(() {
      token = CancelToken();
      message = null;
      received = 0;
      total = 0;
    });
    try {
      final path = await widget.service.downloadPackage(
        widget.release,
        token!,
        (r, t) {
          if (mounted) {
            setState(() {
              received = r;
              total = t;
            });
          }
        },
      );
      if (mounted)
        setState(() {
          downloadedPath = path;
          message = '下载完成，可前往安装';
        });
    } catch (e) {
      if (mounted) {
        setState(
          () => message = e is DioException && CancelToken.isCancel(e)
              ? '下载已取消'
              : '下载未完成，请检查网络后重试。',
        );
      }
    } finally {
      if (mounted) setState(() => token = null);
    }
  }

  @override
  Widget build(BuildContext context) => Glass(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '琉光 V${widget.release.version.replaceFirst(RegExp(r"^[vV]"), "")}',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260),
            child: SingleChildScrollView(
              primary: false,
              child: ReleaseNotesView(
                notes: widget.release.notes.trim().isEmpty
                    ? '此版本暂无发布说明'
                    : widget.release.notes,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (token != null) ...[
          LinearProgressIndicator(
            value: total > 0 ? (received / total).clamp(0, 1) : null,
          ),
          const SizedBox(height: 8),
          Text(
            '${(received / 1048576).toStringAsFixed(1)} MB${total > 0 ? ' / ${(total / 1048576).toStringAsFixed(1)} MB' : ''}',
          ),
          const SizedBox(height: 12),
          GlassButton('取消下载', onTap: () => token?.cancel()),
        ] else if (downloadedPath != null)
          GlassButton(
            '去安装',
            primary: true,
            icon: Icons.install_mobile_rounded,
            onTap: () async {
              try {
                await widget.service.installDownloaded(downloadedPath!);
                if (mounted) setState(() => message = '已打开系统安装页面');
              } on PlatformException catch (e) {
                if (mounted)
                  setState(() => message = e.message ?? '无法打开系统安装页面');
              } catch (_) {
                if (mounted)
                  setState(() {
                    downloadedPath = null;
                    message = '安装包不存在，请重新下载';
                  });
              }
            },
          )
        else if (widget.release.apk != null)
          GlassButton(
            '下载更新',
            primary: true,
            icon: Icons.system_update,
            onTap: download,
          )
        else
          const Text('此版本尚未提供可下载的 APK 附件'),
        if (message != null)
          Text(message!, style: TextStyle(color: muted(context), fontSize: 12)),
      ],
    ),
  );
}

class VersionLog extends StatefulWidget {
  const VersionLog({super.key});
  @override
  State<VersionLog> createState() => _VersionLogState();
}

Color changeTagColor(String type, bool dark) => switch (type) {
  '新增' => Color(dark ? 0xff6bdba6 : 0xff198754),
  '修复' => Color(dark ? 0xffffbc79 : 0xffc96108),
  _ => Color(dark ? 0xff94baff : 0xff2e68cd),
};

class _VersionLogState extends State<VersionLog> {
  final expanded = <String>{appVersion};
  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final entry in [
        (appVersion, releaseNotes, '2026-11-23'),
        ('1.1.2', releaseNotesV112, '2026-11-23'),
        ('1.1.1', releaseNotesV111, '2026-11-23'),
        ('1.1.0', releaseNotesV110, '2026-11-19'),
        ('1.0.9', '修复：恢复历史作品与请求明细，新增自定义表情角色创建和 GIF 参数校验。', '2026-11-19'),
        ('1.0.8', releaseNotesV108, '2026-11-19'),
        ('1.0.7', releaseNotesV107, '2026-11-19'),
        ('1.0.6', releaseNotesV106, '2026-11-18'),
        ('1.0.4', releaseNotesV104, '2026-11-10'),
        ('1.0.3', releaseNotesV103, '2026-11-10'),
        ('1.0.2', releaseNotesV102, '2026-11-10'),
        ('1.0.1', releaseNotesV101, '2026-11-09'),
        ('1.0.0', previousReleaseNotes, '2026-11-09'),
      ])
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Glass(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() {
                    if (!expanded.add(entry.$1)) expanded.remove(entry.$1);
                  }),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'V${entry.$1} · ${entry.$3}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      AnimatedRotation(
                        turns: expanded.contains(entry.$1) ? .5 : 0,
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 165),
                        child: const Icon(Icons.expand_more),
                      ),
                    ],
                  ),
                ),
                AnimatedSize(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 165),
                  alignment: Alignment.topCenter,
                  child: expanded.contains(entry.$1)
                      ? Column(
                          children: [
                            for (final line in entry.$2.split('\n'))
                              Padding(
                                padding: const EdgeInsets.only(top: 14),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    ChangeTag(type: line.substring(0, 2)),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        line.substring(3),
                                        style: const TextStyle(
                                          fontSize: 14,
                                          height: 1.6,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
    ],
  );
}

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});
  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  late Future<String> log = AppLog.read();

  @override
  Widget build(BuildContext context) => SettingsDetail(
    title: '日志详情',
    children: [
      const SectionLabel('异常记录', caption: '自动保留 7 天'),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          GlassButton(
            '刷新',
            icon: Icons.refresh_rounded,
            small: true,
            onTap: () => setState(() => log = AppLog.read()),
          ),
          GlassButton(
            '导出',
            icon: Icons.ios_share_rounded,
            small: true,
            onTap: () async {
              final dir = await safeTemporaryDirectory();
              final file = await File('${dir.path}/liuguang-diagnostics.jsonl')
                  .writeAsString(await AppLog.read());
              if (mounted)
                await SharePlus.instance.share(
                  ShareParams(files: [XFile(file.path)]),
                );
            },
          ),
          GlassButton(
            '清空',
            icon: Icons.delete_outline_rounded,
            small: true,
            onTap: () async {
              if (await confirm(context, '清空日志？', '将删除本机保存的异常记录。')) {
                await AppLog.clear();
                if (mounted) setState(() => log = AppLog.read());
              }
            },
          ),
        ],
      ),
      const SizedBox(height: 16),
      FutureBuilder<String>(
        future: log,
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Text('日志读取失败');
          if (!snapshot.hasData) return const Text('正在读取日志…');
          final entries = snapshot.data!
              .trim()
              .split('\n')
              .reversed
              .map(AppLog.parse)
              .whereType<Map<String, dynamic>>()
              .toList();
          if (entries.isEmpty) {
            return const EmptyState(
              icon: Icons.verified_outlined,
              title: '暂无异常记录',
              subtitle: '出现异常时，可在这里查看原因。',
            );
          }
          return Column(
            children: [
              for (final entry in entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _DiagnosticEntry(entry: entry),
                ),
            ],
          );
        },
      ),
    ],
  );
}

class _DiagnosticEntry extends StatelessWidget {
  const _DiagnosticEntry({required this.entry});

  final Map<String, dynamic> entry;

  String get _event => entry['event']?.toString() ?? '';
  String get _time =>
      (entry['time']?.toString() ?? '').replaceFirst('T', ' ').split('.').first;
  String get _title => switch (_event) {
    'sticker_gif_failure' => 'GIF 表情包生成失败',
    'model_request_failure' => '模型调用未完成',
    'flutter_framework_error' || 'unhandled_app_error' => '应用运行异常',
    'shared_view_error' => '系统图片转场未能启动',
    'update_check_failure' => '检查更新失败',
    'update_install_or_download_failure' => '下载或安装更新失败',
    _ when _event.startsWith('model_image_poll_') => '查询生图进度失败',
    _ when _event.startsWith('model_image_') => '生图接口异常',
    _ when _event.startsWith('model_chat_') => '对话接口异常',
    _ when _event.startsWith('model_') => '模型接口异常',
    _ when _event.startsWith('update_') => '应用更新异常',
    _ => '应用操作异常',
  };

  String get _cause {
    final detail = entry['detail'];
    if (_event == 'sticker_gif_failure' &&
        detail is String &&
        detail.isNotEmpty)
      return detail;
    return switch (entry['status']) {
      400 => '服务端拒绝了请求参数。请检查所选模型、图片协议与生成规格。',
      401 || 403 => '服务端拒绝授权。请检查 API Key、模型权限或账户状态。',
      404 => '服务端找不到对应接口或任务。请检查基础地址和模型配置。',
      413 => '上传文件超过服务端大小限制。请选择较小的参考图。',
      429 => '请求超过服务端限额。请检查频率限制或账户余额。',
      final int value when value >= 500 => '服务端暂时无法处理请求，请稍后再试。',
      _ when _event.contains('timeout') => '等候接口回复超时。请检查网络和服务端的任务状态。',
      _ when _event.contains('connection') => '请检查网络和接口基础地址。',
      _ when _event == 'shared_view_error' => '系统未能打开转场，应用将尝试在内置预览中打开图片。',
      _ when _event.startsWith('update_') => '请检查网络、下载源或设备剩余空间。',
      _ when _event.startsWith('model_') => '模型请求未完成。请同时查看「使用明细 → 请求明细」中的同一时段。',
      _ => '应用遇到异常。若问题再次出现，可导出这条日志协助排查。',
    };
  }

  @override
  Widget build(BuildContext context) => Glass(
    blur: false,
    radius: 19,
    padding: EdgeInsets.zero,
    child: ListTile(
      leading: Icon(
        Icons.error_outline_rounded,
        color: Theme.of(context).colorScheme.error,
      ),
      title: Text(
        _title,
        style: TextStyle(color: ink(context), fontWeight: FontWeight.w600),
      ),
      subtitle: Text(_time, style: TextStyle(color: muted(context))),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (context) => SettingsDetail(
            title: _title,
            children: [
              Glass(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '发生了什么',
                      style: TextStyle(
                        color: ink(context),
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _cause,
                      style: TextStyle(height: 1.55, color: ink(context)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Glass(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _metadata(context, '发生时间', _time),
                    if (entry['status'] != null)
                      _metadata(context, '服务端状态', 'HTTP ${entry['status']}'),
                    if (entry['elapsedMs'] case final num duration)
                      _metadata(
                        context,
                        '耗时',
                        '${(duration / 1000).toStringAsFixed(1)} 秒',
                      ),
                    if (entry['inputTokens'] != null ||
                        entry['outputTokens'] != null)
                      _metadata(
                        context,
                        'Token 用量',
                        '输入 ${entry['inputTokens'] ?? '—'} · 输出 ${entry['outputTokens'] ?? '—'}',
                      ),
                    _metadata(context, '诊断代码', _event),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _metadata(BuildContext context, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: muted(context), fontSize: 12)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(color: ink(context))),
      ],
    ),
  );
}

class ReleaseNotesView extends StatelessWidget {
  final String notes;
  const ReleaseNotesView({super.key, required this.notes});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final raw in notes.split('\n').where((s) => s.trim().isNotEmpty))
        Builder(
          builder: (context) {
            final line = raw.replaceFirst(RegExp(r'^[-*#\s]+'), '').trim();
            final match = RegExp(r'^(新增|修复|优化)[：: ]*').firstMatch(line);
            final tag = match?.group(1);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (tag != null) ...[
                    ChangeTag(type: tag),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Text(
                      match == null ? line : line.substring(match.end),
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.7,
                        color: ink(context),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
    ],
  );
}

class ChangeTag extends StatelessWidget {
  final String type;
  const ChangeTag({super.key, required this.type});
  @override
  Widget build(BuildContext context) {
    final color = changeTagColor(type, isDark(context));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(type, style: TextStyle(fontSize: 12, color: color)),
    );
  }
}

Future<void> floatingRelease(BuildContext context, Widget child) =>
    studioDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        constraints: const BoxConstraints(maxWidth: 480),
        child: StudioScope(store: StudioScope.of(context), child: child),
      ),
    );

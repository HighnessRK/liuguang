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
                        duration: const Duration(milliseconds: 200),
                        child: const Icon(Icons.expand_more),
                      ),
                    ],
                  ),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
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
  int kind = 0;
  @override
  Widget build(BuildContext context) => SettingsDetail(
    title: '日志详情',
    children: [
      Text(
        '记录操作、应用状态与模型请求结果。保留 7 天，不记录 Key、地址、提示词、图片或响应正文。',
        style: TextStyle(color: muted(context), height: 1.6),
      ),
      const SizedBox(height: 16),
      GlassSegments(
        labels: const ['正常', '错误'],
        selected: kind,
        onChanged: (v) => setState(() => kind = v),
      ),
      const SizedBox(height: 14),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          GlassButton(
            '刷新',
            icon: Icons.refresh_rounded,
            onTap: () => setState(() => log = AppLog.read()),
          ),
          GlassButton(
            '导出',
            icon: Icons.ios_share_rounded,
            onTap: () async {
              final dir = await safeTemporaryDirectory();
              final file = await File('${dir.path}/liuguang-diagnostics.jsonl')
                  .writeAsString(await AppLog.read());
              await SharePlus.instance.share(
                ShareParams(files: [XFile(file.path)]),
              );
            },
          ),
          GlassButton(
            '清空',
            icon: Icons.delete_outline,
            onTap: () async {
              if (await confirm(context, '清空日志？', '将删除正常与错误两类日志。')) {
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
              .where((entry) {
                final event = entry['event']?.toString() ?? '';
                final error =
                    entry['level'] == 'error' ||
                    event.contains('failure') ||
                    event.endsWith('_error');
                return error == (kind == 1);
              })
              .toList();
          if (entries.isEmpty) return Text(kind == 0 ? '暂无正常日志' : '暂无错误日志');
          return SizedBox(
            height: (MediaQuery.sizeOf(context).height * .58).clamp(200, 580),
            child: ListView.separated(
              primary: false,
              itemCount: entries.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final entry = entries[i];
                final date = (entry['time']?.toString() ?? '')
                    .replaceFirst('T', ' ')
                    .split('.')
                    .first;
                final details = [
                  date,
                  if (entry['status'] != null) 'HTTP ${entry['status']}',
                  if (entry['elapsedMs'] != null) '${entry['elapsedMs']} ms',
                  if (entry['images'] != null) '${entry['images']} 张',
                  if (entry['inputTokens'] != null ||
                      entry['outputTokens'] != null)
                    'Token ${entry['inputTokens'] ?? '—'}/${entry['outputTokens'] ?? '—'}',
                ];
                return Glass(
                  blur: false,
                  radius: 17,
                  padding: const EdgeInsets.all(13),
                  child: Row(
                    children: [
                      Icon(
                        kind == 1
                            ? Icons.error_outline
                            : Icons.check_circle_outline,
                        color: kind == 1
                            ? Theme.of(context).colorScheme.error
                            : accentInk(context),
                        size: 19,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry['event']?.toString() ?? '',
                              style: TextStyle(
                                color: ink(context),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              details.join(' · '),
                              style: TextStyle(
                                color: muted(context),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    ],
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
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        constraints: const BoxConstraints(maxWidth: 480),
        child: StudioScope(store: StudioScope.of(context), child: child),
      ),
    );

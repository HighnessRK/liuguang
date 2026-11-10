import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
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
      await glassSheet(
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
        await glassSheet(
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
  @override
  void dispose() {
    token?.cancel();
    super.dispose();
  }

  Future<void> install() async {
    setState(() {
      token = CancelToken();
      message = null;
      received = 0;
      total = 0;
    });
    try {
      await widget.service.downloadAndInstall(widget.release, token!, (r, t) {
        if (mounted) {
          setState(() {
            received = r;
            total = t;
          });
        }
      });
      if (mounted) setState(() => message = '已调起系统安装器');
    } catch (e) {
      if (mounted) {
        setState(
          () => message = e is DioException && CancelToken.isCancel(e)
              ? '下载已取消'
              : '下载或安装未完成。请检查网络；如系统要求，请允许“安装未知应用”后重试。',
        );
      }
    } finally {
      if (mounted) setState(() => token = null);
    }
  }

  @override
  Widget build(BuildContext context) => Glass(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.release.version,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        Text(
          widget.release.notes,
          style: const TextStyle(fontSize: 14, height: 1.7),
        ),
        const SizedBox(height: 16),
        if (token != null) ...[
          LinearProgressIndicator(value: total > 0 ? received / total : null),
          Text(
            '${(received / 1048576).toStringAsFixed(1)} MB${total > 0 ? ' / ${(total / 1048576).toStringAsFixed(1)} MB' : ''}',
          ),
          GlassButton('取消下载', onTap: () => token?.cancel()),
        ] else if (widget.release.apk != null)
          GlassButton(
            '下载并安装',
            primary: true,
            icon: Icons.system_update,
            onTap: install,
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
        (appVersion, releaseNotes, '2026-11-10'),
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
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 7,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: changeTagColor(
                                          line.substring(0, 2),
                                          isDark(context),
                                        ).withValues(alpha: .12),
                                        borderRadius: BorderRadius.circular(7),
                                      ),
                                      child: Text(
                                        line.substring(0, 2),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: changeTagColor(
                                            line.substring(0, 2),
                                            isDark(context),
                                          ),
                                        ),
                                      ),
                                    ),
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
    title: '诊断日志',
    children: [
      const Text('只记录事件、时间和状态码；不记录 Key、提示词、图片、接口地址和响应正文。最多保留 300 条。'),
      const SizedBox(height: 16),
      Row(
        children: [
          Expanded(
            child: GlassButton(
              '导出',
              onTap: () async {
                final dir = await getTemporaryDirectory();
                final file = File('${dir.path}/liuguang-diagnostics.jsonl');
                await file.writeAsString(await AppLog.read());
                await SharePlus.instance.share(
                  ShareParams(files: [XFile(file.path)]),
                );
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GlassButton(
              '清空',
              onTap: () async {
                if (!await confirm(
                  context,
                  '清空诊断日志？',
                  '只清空本机诊断事件，不影响作品和使用明细。',
                )) {
                  return;
                }
                await AppLog.clear();
                if (mounted) setState(() => log = AppLog.read());
              },
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      FutureBuilder<String>(
        future: log,
        builder: (_, snapshot) => StudioSelectable(
          snapshot.data?.isNotEmpty == true ? snapshot.data! : '暂无日志',
          style: const TextStyle(fontSize: 12, height: 1.6),
        ),
      ),
    ],
  );
}

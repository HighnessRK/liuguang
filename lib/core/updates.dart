import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'store.dart';

const appVersion = '1.0.2';
const releaseNotes = '''新增：六大类 32 种材质与离线预览，包含光透与毛绒。
新增：八套完整渐变主题，桌面图标支持造型、颜色与材质组合。
优化：生成默认 4K，传奇二瞬默认原尺寸画布，增加三种影调和强度。
修复：提示词尾部冗余、滑条与选框拥挤、色彩端点模糊。''';
const releaseNotesV101 = '''修复：景深上传体积与同步超时问题，随想接口改用异步任务。
修复：输入提示重叠、中文编辑菜单与文本选择体验。
修复：当前版本重复日志及不应出现的下载安装按钮。
优化：统一任务状态、取消操作、关于页面与控件布局。
优化：明确画布方向，核对接口实际返回的图片比例。''';
const previousReleaseNotes = '''新增：文生图、图生图、多参考图、局部重绘与提示词润色。
新增：实时调色、色彩平衡、裁切、景深增强与 GIF 导出。
新增：GitHub / Gitee 双源更新、后台检查、更新日志与脱敏诊断日志。
优化：采用 Flutter_miuix 控件与租房管家同款极光主题。
优化：比例与 K 档位选择，修图工具固定可见，作品长按删除。
修复：滚动边缘黑影、玻璃遮挡和导出控件显示问题。''';

int compareVersions(String a, String b) {
  List<int> parts(String v) => v
      .replaceFirst(RegExp(r'^[vV]'), '')
      .split(RegExp(r'[.+-]'))
      .take(3)
      .map((v) => int.tryParse(v) ?? 0)
      .toList();
  final x = parts(a), y = parts(b);
  for (var i = 0; i < 3; i++) {
    final c = (i < x.length ? x[i] : 0).compareTo(i < y.length ? y[i] : 0);
    if (c != 0) return c;
  }
  return 0;
}

class AppLog {
  static File? file;
  static Future<void> queue = Future.value();
  static Future<void> init(Directory directory) async {
    file = File('${directory.path}/diagnostics.jsonl');
    await record('application_start');
  }

  // Only event identifiers and numeric data are accepted: never log prompts,
  // keys, request bodies, response bodies, URLs or arbitrary exceptions.
  static Future<void> record(String event, {int? status}) {
    if (!RegExp(r'^[a-z_]+$').hasMatch(event)) return Future.value();
    queue = queue.catchError((_) {}).then((_) async {
      if (file == null) return;
      final lines = await file!.exists()
          ? await file!.readAsLines()
          : <String>[];
      lines.add(
        jsonEncode({
          'time': DateTime.now().toIso8601String(),
          'event': event,
          'status': ?status,
        }),
      );
      await file!.writeAsString(
        '${lines.skip(lines.length > 300 ? lines.length - 300 : 0).join('\n')}\n',
        flush: true,
      );
    });
    return queue;
  }

  static Future<String> read() async {
    await queue;
    return file != null && await file!.exists() ? file!.readAsString() : '';
  }

  static Future<void> clear() async {
    await queue;
    await file?.writeAsString('');
  }
}

class ReleaseInfo {
  final String version, notes, source, page;
  final String? apk;
  final int? size;
  ReleaseInfo(
    this.version,
    this.notes,
    this.source,
    this.page,
    this.apk,
    this.size,
  );
  static ReleaseInfo parse(Map<String, dynamic> value, String source) {
    final raw = value['assets'];
    final assets = raw is Map
        ? raw['links'] ?? []
        : raw ?? value['attachments'] ?? [];
    String? apk;
    int? size;
    for (final a in assets as List) {
      if ((a['name'] ?? '').toString().toLowerCase().endsWith('.apk')) {
        apk = (a['browser_download_url'] ?? a['download_url'] ?? a['url'])
            ?.toString();
        size = (a['size'] as num?)?.toInt();
        break;
      }
    }
    return ReleaseInfo(
      value['tag_name'] ?? '',
      value['body'] ?? '',
      source,
      value['html_url'] ??
          (source == 'github'
              ? 'https://github.com/HighnessRK/liuguang/releases'
              : 'https://gitee.com/highnesssrk/liuguang/releases'),
      apk,
      size,
    );
  }
}

class UpdateService {
  static const channel = MethodChannel('liuguang/native');
  static const github =
      'https://api.github.com/repos/HighnessRK/liuguang/releases/latest';
  static const gitee =
      'https://gitee.com/api/v5/repos/highnesssrk/liuguang/releases?per_page=50';
  final AppStore store;
  final Dio dio;
  UpdateService(this.store, {Dio? client})
    : dio =
          client ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
              headers: {
                'User-Agent': 'liuguang-updater',
                'Accept': 'application/json',
              },
            ),
          );
  String get source => store.prefs.getString('update_source') ?? 'gitee';
  bool get auto => store.prefs.getBool('update_auto') ?? true;
  bool get notify => store.prefs.getBool('update_notify') ?? true;
  Future<void> configure({
    String? source,
    bool? auto,
    bool? notify,
    bool requestPermission = false,
  }) async {
    if (source != null) await store.prefs.setString('update_source', source);
    if (auto != null) await store.prefs.setBool('update_auto', auto);
    if (notify != null) await store.prefs.setBool('update_notify', notify);
    if (Platform.isAndroid) {
      await channel.invokeMethod('configureUpdates', {
        'enabled': this.auto,
        'notify': this.notify,
        'source': this.source,
        'version': appVersion,
        'requestPermission': requestPermission,
      });
    }
  }

  Future<ReleaseInfo?> check() async {
    await AppLog.record('update_check');
    try {
      final response = await dio.get(source == 'github' ? github : gitee);
      final data = response.data is String
          ? jsonDecode(response.data)
          : response.data;
      final list = data is List ? data : [data];
      final releases = list
          .where(
            (v) =>
                v['draft'] != true &&
                v['prerelease'] != true &&
                (v['tag_name'] ?? '').toString().isNotEmpty,
          )
          .map((v) => ReleaseInfo.parse(Map<String, dynamic>.from(v), source))
          .toList();
      releases.sort((a, b) => compareVersions(b.version, a.version));
      await AppLog.record('update_check_success', status: response.statusCode);
      return releases.isEmpty ? null : releases.first;
    } on DioException catch (e) {
      await AppLog.record(
        'update_check_failure',
        status: e.response?.statusCode,
      );
      rethrow;
    }
  }

  Future<void> downloadAndInstall(
    ReleaseInfo info,
    CancelToken cancel,
    void Function(int, int) progress,
  ) async {
    final uri = Uri.tryParse(info.apk ?? '');
    if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty) {
      throw StateError('此版本没有可用的 HTTPS 安装包附件');
    }
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/liuguang-update.apk';
    final partial = '$path.part';
    await AppLog.record('update_download_start');
    try {
      await dio.download(
        uri.toString(),
        partial,
        cancelToken: cancel,
        onReceiveProgress: progress,
        deleteOnError: true,
        options: Options(
          headers: {'Accept': 'application/octet-stream'},
          receiveTimeout: const Duration(seconds: 45),
        ),
      );
      final downloaded = File(partial);
      if (info.size != null &&
          info.size! > 0 &&
          await downloaded.length() != info.size) {
        throw StateError('安装包长度校验失败');
      }
      await downloaded.rename(path);
      await AppLog.record('update_download_complete');
      await channel.invokeMethod('installUpdate', {'path': path});
    } catch (_) {
      if (await File(partial).exists()) await File(partial).delete();
      await AppLog.record('update_install_or_download_failure');
      rethrow;
    }
  }
}

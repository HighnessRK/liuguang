import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';

import 'store.dart';

const appVersion = '1.1.2';
const releaseNotes = '''修复：作品长按和多选保持滚动位置，表情包生成后打开新作品详情。
修复：角色切换、编辑和删除统一管理，三视图与角色名称同步。
新增：关于琉光提供分类日志，支持手动清理及自动保留七天。
优化：隐藏空间支持从作品顶部继续下拉并随手势显示进度。
优化：重做润色、生图任务和传奇二瞬界面，完成提示移到顶部。
新增：接入金标联盟 SharedView Kit，支持的设备可在作品大图使用原生过渡。''';
const releaseNotesV110 = '''新增：表情包动图固定输出 GIF、512 × 512、8 帧、每帧 150 ms，并加入 smooth motion、consistent character 与帧间一致性约束。
新增：存储管理支持查看、批量删除和安装已下载的更新安装包。
新增：作品隐藏空间，支持长按批量移入和还原，并保留原生成时间顺序。
新增：表情包角色创建支持从作品添加三视图、识图自动生成描述和角色切换。
修复：普通生图数量始终默认为 1，避免服务端误生成多张。
修复：更新弹窗日志始终显示当前版本，下载完成后改为“去安装”并进入安装页面。
优化：更新日志滚动区域独立滚动，下载进度不再被长日志遮挡。
优化：动态极光任务卡的光效、计时和取消按钮可读性。''';
const releaseNotesV108 =
    '''修复：解决小米设备冷启动时 path_provider JNI Context 查找失败导致应用无法进入首页的问题。
新增：创作页将 DeepSeek 表情包入口与文生图、图生图并列，入口更易发现。
优化：DeepSeek 页面间距与生成按钮统一为液态玻璃风格。''';
const releaseNotesV107 = '''新增：完成 V1.0.6 的 16 项功能复核，补齐全图点击放大、后台任务、流式进度和创作助手图片理解。
新增：DeepSeek 大肥鱼娘参考图完整展示，动图固定 512 × 512、8 帧、每帧 200 ms。
修复：更新弹窗改用当前版本日志，避免显示上一版本内容。
修复：大肥鱼娘动图加入 smooth motion、consistent character 与帧间一致性约束。
优化：生成规格窗增加液态玻璃关闭按钮，图片入口统一支持自由缩放查看。
优化：更新日志、表情包参数和作品预览与当前版本保持一致。''';
const releaseNotesV106 = '''新增：后台生图任务、动态极光进度卡、真实服务端百分比、图片理解式智能润色。
新增：创作助手上传图片、识图理解和直接切换模型。
新增：DeepSeek 大肥鱼娘静态 / 动图表情包模式，分享图模板扩展并支持保存相册。
修复：传奇二瞬运行状态、图生图底图比例、生成白边和识图复用对话地址。
优化：悬浮导航、专业模式、GIF 原生协议、全图放大、后台处理和内存回收。''';
const releaseNotesV104 = '''新增：修图关闭图片入口，离开前确认未导出修改或取消 AI 任务。
修复：修图功能按钮居中排列，收紧按钮与卡片的多余留白。
优化：返回按钮采用液态玻璃材质。
优化：个性化内外观与桌面图标并列，图标仅显示卡片勾选。
优化：简化传奇二瞬入口名称。''';
const releaseNotesV103 = '''新增：本机人像美化预设，支持自然柔肤、提亮、暖肤、红润和黑白。
优化：传奇二瞬自动匹配原图比例，仅提供 1K / 2K / 4K，默认 4K。
优化：外观收纳到个性化，桌面图标改为完整渐变设计。
优化：更新弹窗使用分类标签，隐私与开源许可采用统一玻璃卡片布局。''';
const releaseNotesV102 = '''新增：六大类 32 种材质与离线预览，包含光透与毛绒。
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
  static DateTime? _lastPrune;
  static const retention = Duration(days: 7);

  static Future<void> init(Directory directory) async {
    file = File('${directory.path}/diagnostics.jsonl');
    _lastPrune = null;
    await read().catchError((_) => '');
  }

  static Future<void> record(
    String event, {
    int? status,
    int? elapsedMs,
    bool error = false,
    int? images,
    int? inputTokens,
    int? outputTokens,
    String? detail,
  }) {
    if (file == null ||
        !RegExp(r'^[a-z_]{1,80}$').hasMatch(event) ||
        !_isAnomaly(event, status, error))
      return Future.value();
    return queue = queue
        .catchError((_) {})
        .then((_) async {
          final target = file;
          if (target == null) return;
          final now = DateTime.now();
          if (_lastPrune == null ||
              now.difference(_lastPrune!) > const Duration(hours: 1)) {
            await _prune(target, now);
          }
          final entry = {
            'time': now.toIso8601String(),
            'event': event,
            'level': 'error',
            'status': ?status,
            'elapsedMs': ?elapsedMs,
            'images': ?images,
            'inputTokens': ?inputTokens,
            'outputTokens': ?outputTokens,
            // Only locally generated descriptions from the GIF workflow.
            if (event == 'sticker_gif_failure' && detail != null)
              'detail': detail,
          };
          await target.writeAsString(
            '${jsonEncode(entry)}\n',
            mode: FileMode.append,
          );
        })
        .catchError((_) {});
  }

  static bool _isAnomaly(String event, int? status, bool error) =>
      error ||
      (status ?? 0) >= 400 ||
      event.contains('failure') ||
      event.endsWith('_error');

  static Map<String, dynamic>? parse(String line) {
    try {
      final value = jsonDecode(line);
      return value is Map<String, dynamic> ? value : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _prune(File target, DateTime now) async {
    _lastPrune = now;
    if (!await target.exists()) return;
    final cutoff = now.subtract(retention);
    final lines = await target.readAsLines();
    final retained = lines.where((line) {
      final entry = parse(line);
      final time = entry?['time'];
      final event = entry?['event'];
      final status = entry?['status'];
      final date = time is String ? DateTime.tryParse(time) : null;
      return date != null &&
          !date.isBefore(cutoff) &&
          event is String &&
          _isAnomaly(
            event,
            status is int ? status : null,
            entry?['level'] == 'error',
          );
    }).toList();
    if (retained.length == lines.length) return;
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsString(
      retained.isEmpty ? '' : '${retained.join('\n')}\n',
      flush: true,
    );
    await tmp.rename(target.path);
  }

  static Future<String> read() async {
    final result = queue.catchError((_) {}).then((_) async {
      final target = file;
      if (target == null || !await target.exists()) return '';
      await _prune(target, DateTime.now());
      return target.readAsString();
    });
    queue = result.then<void>((_) {}).catchError((_) {});
    return result;
  }

  static Future<void> clear() =>
      queue = queue.catchError((_) {}).then((_) async {
        final target = file;
        if (target != null && await target.exists()) await target.delete();
      });
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

  Directory get packageDirectory =>
      Directory('${store.directory.path}/packages');

  File _packageFile(ReleaseInfo info) {
    final version = info.version
        .replaceFirst(RegExp(r'^[vV]'), '')
        .replaceAll(RegExp(r'[^0-9A-Za-z._-]'), '_');
    return File('${packageDirectory.path}/liuguang-v$version.apk');
  }

  Future<String?> downloadedPackage(ReleaseInfo info) async {
    final file = _packageFile(info);
    final legacy = File(
      '${packageDirectory.path}/liuguang-${info.version.replaceAll(RegExp(r'[^0-9A-Za-z._-]'), '_')}.apk',
    );
    for (final candidate in [file, legacy]) {
      if (await candidate.exists()) {
        final length = await candidate.length();
        if (length > 0 &&
            (info.size == null || info.size == 0 || length == info.size))
          return candidate.path;
      }
    }
    return null;
  }

  Future<String> downloadPackage(
    ReleaseInfo info,
    CancelToken cancel,
    void Function(int, int) progress,
  ) async {
    final uri = Uri.tryParse(info.apk ?? '');
    if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty) {
      throw StateError('此版本没有可用的 HTTPS 安装包附件');
    }
    final existing = await downloadedPackage(info);
    if (existing != null) return existing;
    await packageDirectory.create(recursive: true);
    final path = _packageFile(info).path;
    final partial = '$path.${DateTime.now().microsecondsSinceEpoch}.part';
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
      return path;
    } catch (_) {
      if (await File(partial).exists()) await File(partial).delete();
      await AppLog.record('update_install_or_download_failure');
      rethrow;
    }
  }

  Future<void> installDownloaded(String path) async {
    final file = File(path);
    if (!await file.exists()) throw StateError('安装包不存在或已被删除');
    await channel.invokeMethod('installUpdate', {'path': file.path});
  }
}

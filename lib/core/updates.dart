import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'store.dart';

const appVersion = '1.0.5';
const releaseNotes = '''新增：高清重绘入口，按所选分辨率重建照片细节。
新增：独立识图配置，可复用对话 API Key，单独选择模型 ID。
新增：三套本地 3072 px 分享模板，展示图片、提示词、模型和已记录的生成参数，支持批量分享。
新增：gpt-image-2.6 系列原生 GIF，其他模型禁用；保留返回动画的原始尺寸与文件。
新增：识图分析上传图片生成动态提示词，并结合用户输入的运动要求。
新增：专业模式负面约束，以及可选 Seed、步数、CFG 和采样器。
新增：存储管理、缓存清理、作品压缩预览与确认替换，保护 GIF 和正在使用的图片。
修复：润色与创作助手的响应类型报错，兼容 JSON 字符串和流式文本。
修复：传奇二瞬完成后，按住对比可查看处理前的照片。
修复：数量加号消失、长玻璃按钮裁断、放大字号时明细时间轴溢出。
修复：深色玻璃主按钮文字过暗，统一文字、图标与加载指示颜色。
优化：作品长按直接进入多选，绿色勾选、触感反馈与操作栏展开收起动画。
优化：传奇二瞬支持调整景深程度，并可根据识图结果定制处理提示词。
优化：放大修图预览，支持全屏查看；传奇二瞬分享默认隐藏提示词，可勾选包含。
优化：底图、参考图统一从相册或作品选择，移除创作页独立的作品选图按钮。
优化：生图、对话、识图配置三标签并列，统一页面间距与液态玻璃按钮。
优化：生成规格修改立即生效，生成、编辑、导出、分享和存储参数自动保存。
优化：更新窗居中浮空，新增、修复、优化使用对应颜色标签。
优化：对话与润色流式显示，生图采用渐变加载卡和呼吸星光，显示接口返回的真实进度。
优化：云端请求与本地处理接入后台前台服务，任务结束后清理临时上传副本。
优化：接入公平内存回收协议，保存编辑现场并恢复比较原图，释放图像缓存。
优化：页面进出期间复用短时画面，结束即恢复实时玻璃；减少动态效果时关闭动画。
优化：精简旧图标和无关架构资源，保留桌面入口兼容，合并编辑参数保存。''';
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

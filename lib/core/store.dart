import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'updates.dart';

class AppStore extends ChangeNotifier {
  final FlutterSecureStorage secure;
  late SharedPreferences prefs;
  late Directory directory;
  EndpointConfig imageApi = EndpointConfig(), chatApi = EndpointConfig();
  GenerationOptions defaults = GenerationOptions();
  List<Artwork> artworks = [];
  List<UsageRecord> usage = [];
  List<ChatMessage> messages = [];
  String theme = 'system';
  int accent = 0xff2e68cd;
  double glassOpacity = .22, blur = 12, textScale = 1;
  bool haptics = true, reduceMotion = false, highContrast = false;
  String? storageWarning;
  Future<void> _saveQueue = Future.value();
  AppStore({FlutterSecureStorage? secure})
    : secure = secure ?? const FlutterSecureStorage();

  Future<void> init() async {
    prefs = await SharedPreferences.getInstance();
    directory = Directory(
      '${(await getApplicationSupportDirectory()).path}/studio',
    );
    await directory.create(recursive: true);
    final raw = prefs.getString('settings');
    if (raw != null) {
      try {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        imageApi = EndpointConfig.fromJson(j['image'] ?? {});
        chatApi = EndpointConfig.fromJson(j['chat'] ?? {});
        defaults = GenerationOptions.fromJson(j['defaults'] ?? {});
        theme = j['theme'] ?? 'system';
        accent = j['accent'] ?? accent;
        glassOpacity = (j['glassOpacity'] as num?)?.toDouble() ?? glassOpacity;
        blur = (j['blur'] as num?)?.toDouble() ?? blur;
        textScale = (j['textScale'] as num?)?.toDouble() ?? textScale;
        haptics = j['haptics'] ?? true;
        reduceMotion = j['reduceMotion'] ?? false;
        highContrast = j['highContrast'] ?? false;
      } catch (_) {
        storageWarning = '设置读取失败，已使用默认外观。';
      }
    }
    try {
      imageApi.key = await secure.read(key: 'image_api_key') ?? '';
      chatApi.key = await secure.read(key: 'chat_api_key') ?? '';
    } catch (_) {
      storageWarning = '无法读取加密 Key，请在连接设置中重新填写。';
    }
    final file = File('${directory.path}/catalog.json');
    if (await file.exists()) {
      try {
        final j = jsonDecode(await file.readAsString());
        artworks = (j['artworks'] as List)
            .map((v) => Artwork.fromJson(v))
            .toList();
        usage = (j['usage'] as List)
            .map((v) => UsageRecord.fromJson(v))
            .toList();
        messages = (j['messages'] as List? ?? [])
            .map((v) => ChatMessage.fromJson(v))
            .toList();
      } catch (_) {
        storageWarning = '作品索引读取失败，原始文件仍保存在应用内。';
      }
    }
    if (prefs.getInt('visual_revision') != 3) {
      accent = 0xff2e68cd;
      glassOpacity = .22;
      blur = 12;
      textScale = 1;
      highContrast = false;
      await prefs.setInt('visual_revision', 3);
      await saveSettings();
    }
  }

  Future<void> saveSettings({bool keys = false}) async {
    if (keys) {
      await secure.write(key: 'image_api_key', value: imageApi.key);
      await secure.write(key: 'chat_api_key', value: chatApi.key);
    }
    await prefs.setString(
      'settings',
      jsonEncode({
        'image': imageApi.toJson(),
        'chat': chatApi.toJson(),
        'defaults': defaults.toJson(),
        'theme': theme,
        'accent': accent,
        'glassOpacity': glassOpacity,
        'blur': blur,
        'textScale': textScale,
        'haptics': haptics,
        'reduceMotion': reduceMotion,
        'highContrast': highContrast,
      }),
    );
    notifyListeners();
  }

  Future<void> saveCatalog() {
    final content = jsonEncode({
      'artworks': artworks.map((v) => v.toJson()).toList(),
      'usage': usage.map((v) => v.toJson()).toList(),
      'messages': messages.map((v) => v.toJson()).toList(),
    });
    _saveQueue = _saveQueue.catchError((_) {}).then((_) async {
      final tmp = File('${directory.path}/catalog.tmp');
      await tmp.writeAsString(content, flush: true);
      await tmp.rename('${directory.path}/catalog.json');
    });
    notifyListeners();
    return _saveQueue;
  }

  Future<String> writeImage(Uint8List bytes, String extension) async {
    final name = '${DateTime.now().microsecondsSinceEpoch}';
    final file = File('${directory.path}/$name.$extension');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<String> demoImage() async {
    final data = await rootBundle.load('assets/mountain.jpg');
    return writeImage(data.buffer.asUint8List(), 'jpg');
  }

  Future<void> removeArtwork(Artwork art) async {
    artworks.removeWhere((a) => a.id == art.id);
    await saveCatalog();
    final file = File(art.path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<void> addUsage(UsageRecord record) async {
    await AppLog.record(
      record.success ? 'model_request_success' : 'model_request_failure',
    );
    usage.insert(0, record);
    await saveCatalog();
  }

  void refresh() => notifyListeners();
}

const native = MethodChannel('liuguang/native');

Future<void> saveToGallery(String path) async {
  await native.invokeMethod('saveToGallery', {'path': path});
}

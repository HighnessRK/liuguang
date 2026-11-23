import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/api.dart';
import '../core/models.dart';
import 'library.dart' show pickArtworkPaths;
import '../core/store.dart';
import '../ui/glass.dart';

class StickerProfile {
  final String id;
  final String name;
  final String description;
  final List<String> references;
  const StickerProfile({
    required this.id,
    required this.name,
    required this.description,
    required this.references,
  });
  factory StickerProfile.fromJson(Map<String, dynamic> j) => StickerProfile(
    id: j['id']?.toString() ?? '',
    name: j['name']?.toString() ?? '我的表情角色',
    description: j['description']?.toString() ?? '',
    references: List<String>.from(j['references'] ?? const []),
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'references': references,
  };
}

class StickerCharacterCreatorScreen extends StatefulWidget {
  final AppStore store;
  final StudioApi api;
  final StickerProfile? profile;
  const StickerCharacterCreatorScreen({
    super.key,
    required this.store,
    required this.api,
    this.profile,
  });
  @override
  State<StickerCharacterCreatorScreen> createState() =>
      _StickerCharacterCreatorScreenState();
}

class _StickerCharacterCreatorScreenState
    extends State<StickerCharacterCreatorScreen> {
  late final name = TextEditingController(text: widget.profile?.name);
  late final description = TextEditingController(
    text: widget.profile?.description,
  );
  late final references = [...?widget.profile?.references];
  bool polishing = false, analyzing = false, saving = false;
  bool get busy => polishing || analyzing || saving;
  CancelToken? token;

  @override
  void dispose() {
    token?.cancel();
    name.dispose();
    description.dispose();
    super.dispose();
  }

  Future<void> pickReferences() async {
    if (name.text.trim().isEmpty) {
      toast(context, '请先填写角色名称，再添加三视图');
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    final source = await glassSheet<String>(
      context,
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '添加角色三视图',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          GlassButton(
            '从相册选择',
            icon: Icons.photo_library_outlined,
            onTap: () => Navigator.pop(context, 'album'),
          ),
          const SizedBox(height: 10),
          GlassButton(
            '从作品选择',
            icon: Icons.collections_outlined,
            onTap: () => Navigator.pop(context, 'works'),
          ),
        ],
      ),
    );
    if (!mounted || source == null) return;
    List<String> paths;
    if (source == 'album') {
      paths = (await ImagePicker().pickMultiImage(limit: 3))
          .take(3)
          .map((f) => f.path)
          .toList();
    } else {
      paths = await pickArtworkPaths(context, widget.store, limit: 3);
    }
    if (!mounted || paths.isEmpty) return;
    setState(
      () => references
        ..clear()
        ..addAll(paths),
    );
    await generateDescriptionFromReferences();
  }

  Future<void> generateDescriptionFromReferences() async {
    if (references.isEmpty) return;
    setState(() => analyzing = true);
    token = CancelToken();
    try {
      final visual = await widget.api.imageBrief(
        references,
        '角色名称：${name.text.trim()}。根据角色三视图，生成可重复制作表情包的基本角色描述，保留外观、服饰、发型、配色、配件和不可改变特征。只输出描述正文。',
        cancelToken: token,
      );
      if (mounted) description.text = withStickerProps(visual);
    } catch (e) {
      if (mounted) toast(context, describeError(e));
    } finally {
      if (mounted) setState(() => analyzing = false);
    }
  }

  Future<void> polishDescription() async {
    if (references.isEmpty && description.text.trim().isEmpty) {
      toast(context, '请先添加三视图或填写基本描述');
      return;
    }
    setState(() => polishing = true);
    token = CancelToken();
    try {
      final result = await widget.api.chat([
        ChatMessage(
          'user',
          '润色表情角色「${name.text.trim()}」的描述，保留设定，明确可添加适合的道具。只输出描述正文。\n${description.text.trim()}',
        ),
      ], cancelToken: token);
      if (mounted) description.text = withStickerProps(result);
    } catch (e) {
      if (mounted) toast(context, describeError(e));
    } finally {
      if (mounted) setState(() => polishing = false);
    }
  }

  Future<void> save() async {
    if (busy) return;
    if (name.text.trim().isEmpty ||
        references.isEmpty ||
        description.text.trim().isEmpty) {
      toast(context, '请填写角色名称、三视图和基本描述');
      return;
    }
    setState(() => saving = true);
    final id =
        widget.profile?.id ?? DateTime.now().microsecondsSinceEpoch.toString();
    try {
      final savedPaths = <String>[];
      for (final path in references) {
        if (path.startsWith(
          '${widget.store.directory.path}${Platform.pathSeparator}sticker_refs',
        )) {
          savedPaths.add(path);
          continue;
        }
        final folder = Directory(
          '${widget.store.directory.path}${Platform.pathSeparator}sticker_refs',
        );
        await folder.create(recursive: true);
        final bytes = await File(path).readAsBytes();
        final file = File(
          '${folder.path}${Platform.pathSeparator}$id-${DateTime.now().microsecondsSinceEpoch}.${imageExtension(bytes)}',
        );
        await file.writeAsBytes(bytes, flush: true);
        savedPaths.add(file.path);
      }
      final profile = StickerProfile(
        id: id,
        name: name.text.trim(),
        description: withStickerProps(description.text),
        references: savedPaths,
      );
      await saveStickerProfile(widget.store, profile);
      if (mounted) Navigator.pop(context, profile);
    } catch (e) {
      if (mounted) toast(context, describeError(e));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: GlassMotionScope(
      staticSurface: true,
      child: StudioBackground(
        child: SafeArea(
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            children: [
              PageHeader(
                title: widget.profile == null ? '创建表情角色' : '编辑表情角色',
                action: GlassIcon(
                  Icons.arrow_back_rounded,
                  tooltip: '返回',
                  onTap: () => Navigator.pop(context),
                ),
              ),
              const SectionLabel('角色名称'),
              GlassField(readOnly: busy, controller: name, hint: '例如：蓝莓小猫'),
              const SectionLabel('角色三视图'),
              Glass(
                blur: false,
                child: Column(
                  children: [
                    if (references.isEmpty)
                      Text(
                        '上传正面、侧面、背面或其他能固定角色特征的参考图。',
                        style: TextStyle(color: muted(context), height: 1.6),
                      )
                    else
                      StickerReferencePreview(
                        images: references
                            .map((path) => FileImage(File(path)))
                            .toList(),
                      ),
                    const SizedBox(height: 12),
                    GlassButton(
                      references.isEmpty ? '添加三视图' : '重新选择三视图',
                      icon: Icons.add_photo_alternate_outlined,
                      onTap: busy ? null : pickReferences,
                    ),
                  ],
                ),
              ),
              const SectionLabel('基本描述'),
              GlassField(
                readOnly: busy,
                controller: description,
                onChanged: (_) => setState(() {}),
                hint: '描述角色的身份、性格、服饰、配色和不可改变特征…',
                minLines: 4,
                maxLines: 8,
              ),
              const SizedBox(height: 16),
              if (analyzing || polishing) ...[
                Glass(
                  radius: 16,
                  blur: false,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      const SizedBox.square(
                        dimension: 18,
                        child: StudioProgress(),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          analyzing ? '正在识别三视图并生成基本描述…' : '正在润色基本描述…',
                          style: TextStyle(color: ink(context)),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else
                GlassButton(
                  '智能润色描述',
                  icon: Icons.edit_note_rounded,
                  onTap: busy || description.text.trim().isEmpty
                      ? null
                      : polishDescription,
                ),
              const SizedBox(height: 12),
              GlassButton(
                '保存并开始制作',
                primary: true,
                icon: Icons.save_rounded,
                busy: saving,
                onTap: busy ? null : save,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

const stickerProps = '允许添加适合的道具来最大程度展现表情包';
String withStickerProps(String text) => text.contains(stickerProps)
    ? text.trim()
    : '${text.trim()}\n$stickerProps。';

List<StickerProfile> readStickerProfiles(AppStore store) {
  final profiles = <StickerProfile>[];
  for (final encoded
      in store.prefs.getStringList('sticker_profiles') ?? <String>[]) {
    try {
      final profile = StickerProfile.fromJson(jsonDecode(encoded));
      if (profile.id.isNotEmpty) profiles.add(profile);
    } catch (_) {
      // Ignore a damaged entry without discarding the other characters.
    }
  }
  return profiles;
}

Future<void> saveStickerProfile(AppStore store, StickerProfile profile) async {
  final all = readStickerProfiles(store);
  final index = all.indexWhere((p) => p.id == profile.id);
  if (index == -1) {
    all.add(profile);
  } else {
    all[index] = profile;
  }
  await store.prefs.setStringList(
    'sticker_profiles',
    all.map((p) => jsonEncode(p.toJson())).toList(),
  );
}

class StickerReferencePreview extends StatelessWidget {
  final List<ImageProvider> images;
  const StickerReferencePreview({super.key, required this.images});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (final (index, image) in images.indexed) ...[
        if (index > 0) const SizedBox(width: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: ColoredBox(
              color: ink(context).withValues(alpha: .04),
              child: ZoomableImage(
                image: image,
                child: SizedBox(
                  height: images.length == 1 ? 178 : 112,
                  width: double.infinity,
                  child: Image(
                    image: ResizeImage(
                      image,
                      width: images.length == 1 ? 820 : 480,
                      height: images.length == 1 ? 820 : 480,
                      policy: ResizeImagePolicy.fit,
                      allowUpscaling: false,
                    ),
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) =>
                        const Center(child: Icon(Icons.broken_image_outlined)),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ],
  );
}

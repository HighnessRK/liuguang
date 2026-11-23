import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../core/api.dart';
import '../core/models.dart';
import '../core/store.dart';
import '../ui/glass.dart';

class AssistantScreen extends StatefulWidget {
  final AppStore store;
  final StudioApi api;
  final ValueChanged<String>? onUsePrompt;
  const AssistantScreen({
    super.key,
    required this.store,
    required this.api,
    this.onUsePrompt,
  });
  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final input = TextEditingController();
  final scroll = ScrollController();
  bool busy = false;
  CancelToken? token;
  String? attachedImage;
  Timer? streamFlush;
  bool followStream = true;
  @override
  void dispose() {
    token?.cancel();
    streamFlush?.cancel();
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<void> attach() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file != null && mounted) setState(() => attachedImage = file.path);
  }

  Future<void> send() async {
    if (busy || (input.text.trim().isEmpty && attachedImage == null)) {
      return;
    }
    final text = input.text.trim();
    final image = attachedImage;
    final request = token = CancelToken();
    final messages = widget.store.messages;
    final userIndex = messages.length;
    int? replyIndex;
    String latest = '';
    followStream = true;
    input.clear();
    setState(() {
      attachedImage = null;
      busy = true;
      messages.add(ChatMessage('user', text.isEmpty ? '请分析我上传的图片。' : text));
    });
    _toEnd();
    try {
      await widget.store.saveCatalog();
      final visual = image == null
          ? ''
          : await widget.api.describeImage(
              image,
              goal: 'assistant',
              cancelToken: request,
            );
      if (!mounted || request.isCancelled) return;
      final history = messages.takeLast(30);
      if (visual.isNotEmpty) {
        final content = '${messages[userIndex].text}\n\n图片理解：$visual';
        history[history.length - 1] = ChatMessage('user', content);
      }
      replyIndex = messages.length;
      messages.add(ChatMessage('assistant', ''));
      final index = replyIndex;
      final reply = await widget.api.chat(
        history,
        cancelToken: request,
        onText: (chunk) {
          latest = chunk;
          streamFlush ??= Timer(const Duration(milliseconds: 55), () {
            streamFlush = null;
            if (!mounted) return;
            setState(() => messages[index] = ChatMessage('assistant', latest));
            _toEnd();
          });
        },
      );
      streamFlush?.cancel();
      streamFlush = null;
      if (visual.isNotEmpty) messages[userIndex] = history.last;
      messages[index] = ChatMessage('assistant', reply);
      await widget.store.saveCatalog();
    } catch (e) {
      streamFlush?.cancel();
      streamFlush = null;
      if (replyIndex != null &&
          messages.length > replyIndex &&
          latest.trim().isEmpty) {
        messages.removeAt(replyIndex);
      } else if (replyIndex != null && messages.length > replyIndex) {
        messages[replyIndex] = ChatMessage('assistant', latest);
      }
      if (mounted && !request.isCancelled) toast(context, describeError(e));
      await widget.store.saveCatalog();
    } finally {
      if (mounted) {
        setState(() => busy = false);
        _toEnd();
      }
    }
  }

  void _toEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted && scroll.hasClients && followStream) {
      scroll.jumpTo(scroll.position.maxScrollExtent);
    }
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    body: StudioBackground(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Row(
                children: [
                  GlassIcon(
                    Icons.arrow_back_rounded,
                    tooltip: '返回',
                    onTap: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 15),
                  const Expanded(
                    child: Text(
                      '创作助手',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  GlassIcon(
                    Icons.swap_horiz_rounded,
                    tooltip: '切换模型',
                    onTap: () async {
                      final model = await glassSheet<String>(
                        context,
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              '切换对话模型',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 12),
                            for (final id in widget.store.chatApi.models)
                              ListTile(
                                title: Text(id),
                                trailing: id == widget.store.chatApi.model
                                    ? Icon(
                                        Icons.check_rounded,
                                        color: accent(context),
                                      )
                                    : null,
                                onTap: () => Navigator.pop(context, id),
                              ),
                          ],
                        ),
                      );
                      if (model != null) {
                        widget.store.chatApi.model = model;
                        await widget.store.saveSettings(keys: true);
                        if (mounted) setState(() {});
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                  GlassIcon(
                    Icons.delete_outline_rounded,
                    tooltip: '清空对话',
                    onTap: () async {
                      if (busy) {
                        return;
                      }
                      if (await confirm(context, '清空对话？', '仅删除本机对话记录。')) {
                        widget.store.messages.clear();
                        await widget.store.saveCatalog();
                        if (mounted) {
                          setState(() {});
                        }
                      }
                    },
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 24),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  widget.store.chatApi.model.isEmpty
                      ? '在「设置」中连接对话模型后使用'
                      : widget.store.chatApi.model,
                  style: TextStyle(fontSize: 12, color: muted(context)),
                ),
              ),
            ),
            Expanded(
              child: widget.store.messages.isEmpty
                  ? EmptyState(
                      icon: Icons.auto_awesome_outlined,
                      title: '给灵感一个回声',
                      subtitle: '构思画面，寻找光线，写下更好的提示词。\n连接你自己的对话模型，开始一次创作。',
                      action: GlassButton(
                        '帮我构思一张电影感照片',
                        small: true,
                        onTap: () {
                          input.text = '帮我构思一张电影感照片，给出可直接生图的中文提示词。';
                        },
                      ),
                    )
                  : NotificationListener<ScrollNotification>(
                      onNotification: (notice) {
                        if (notice is ScrollUpdateNotification &&
                            notice.dragDetails != null) {
                          followStream = notice.metrics.extentAfter < 55;
                        }
                        return false;
                      },
                      child: ListView.builder(
                        controller: scroll,
                        padding: const EdgeInsets.all(20),
                        itemCount: widget.store.messages.length,
                        itemBuilder: (context, i) {
                          final message = widget.store.messages[i];
                          final user = message.role == 'user';
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 17),
                            child: Align(
                              alignment: user
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: Glass(
                                opacity: user ? .78 : null,
                                tint: user
                                    ? accent(context).withValues(alpha: .8)
                                    : null,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      user ? '你' : '琉光助手',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: user
                                            ? primaryOn(context, opacity: .78)
                                            : accentInk(context),
                                      ),
                                    ),
                                    const SizedBox(height: 9),
                                    StudioSelectable(
                                      message.text,
                                      style: TextStyle(
                                        color: user
                                            ? primaryOn(context, opacity: .78)
                                            : ink(context),
                                        fontSize: 14,
                                        height: 1.8,
                                      ),
                                    ),
                                    if (!user) ...[
                                      const SizedBox(height: 12),
                                      Row(
                                        children: [
                                          GestureDetector(
                                            behavior: HitTestBehavior.opaque,
                                            onTap: () {
                                              Clipboard.setData(
                                                ClipboardData(
                                                  text: message.text,
                                                ),
                                              );
                                              toast(context, '已复制');
                                            },
                                            child: Text(
                                              '复制',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: muted(context),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 22),
                                          if (widget.onUsePrompt != null)
                                            GestureDetector(
                                              behavior: HitTestBehavior.opaque,
                                              onTap: () {
                                                widget.onUsePrompt!(
                                                  message.text,
                                                );
                                                Navigator.pop(context);
                                              },
                                              child: Text(
                                                '用作提示词 ↗',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: accentInk(context),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
            ),
            if (attachedImage case final path?)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 2),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: ZoomableImage(
                        image: FileImage(File(path)),
                        child: Image.file(
                          File(path),
                          width: 54,
                          height: 54,
                          cacheWidth: 160,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const SizedBox(
                            width: 54,
                            height: 54,
                            child: Icon(Icons.broken_image_outlined),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(child: Text('已添加图片')),
                    GlassIcon(
                      Icons.close_rounded,
                      tooltip: '移除图片',
                      onTap: () => setState(() => attachedImage = null),
                    ),
                  ],
                ),
              ),
            if (busy)
              Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: StudioProgress(strokeWidth: 1.5),
                    ),
                    const SizedBox(width: 10),
                    const Text('正在思考…', style: TextStyle(fontSize: 14)),
                    const SizedBox(width: 20),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => token?.cancel(),
                      child: const Text('停止', style: TextStyle(fontSize: 14)),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GlassIcon(
                    Icons.add_photo_alternate_outlined,
                    tooltip: '上传图片',
                    onTap: busy ? null : attach,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GlassField(
                      controller: input,
                      hint: '聊聊你的灵感…',
                      maxLines: 5,
                    ),
                  ),
                  const SizedBox(width: 10),
                  GlassIcon(
                    Icons.arrow_upward_rounded,
                    tooltip: '发送',
                    onTap: busy ? null : send,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

extension _LastMessages<T> on List<T> {
  List<T> takeLast(int count) => sublist(length > count ? length - count : 0);
}

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  @override
  void dispose() {
    token?.cancel();
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<void> send() async {
    if (busy || input.text.trim().isEmpty) {
      return;
    }
    final text = input.text.trim();
    input.clear();
    widget.store.messages.add(ChatMessage('user', text));
    await widget.store.saveCatalog();
    setState(() => busy = true);
    token = CancelToken();
    try {
      final reply = await widget.api.chat(
        widget.store.messages.takeLast(30),
        cancelToken: token,
      );
      widget.store.messages.add(ChatMessage('assistant', reply));
      await widget.store.saveCatalog();
    } catch (e) {
      if (mounted) {
        toast(context, describeError(e));
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
        _toEnd();
      }
    }
  }

  void _toEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (scroll.hasClients) {
      scroll.animateTo(
        scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
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
                  : ListView.builder(
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
                                          ? const Color(0xff24412c)
                                          : accentInk(context),
                                    ),
                                  ),
                                  const SizedBox(height: 9),
                                  SelectableText(
                                    message.text,
                                    style: TextStyle(
                                      color: user
                                          ? primaryOn(context)
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
                                              ClipboardData(text: message.text),
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
                                              widget.onUsePrompt!(message.text);
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
            if (busy)
              Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 1.5),
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
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
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
                    onTap: send,
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

import 'dart:async';

import 'package:flutter/material.dart';

import '../core/store.dart';
import '../core/api.dart';
import '../ui/glass.dart';
import 'settings.dart';

class VisionSettings extends StatefulWidget {
  final AppStore store;
  final StudioApi api;
  final bool embedded;
  const VisionSettings({
    super.key,
    required this.store,
    required this.api,
    this.embedded = false,
  });
  @override
  State<VisionSettings> createState() => _VisionSettingsState();
}

class _VisionSettingsState extends State<VisionSettings> {
  late final address = TextEditingController(
    text: widget.store.visionApi.baseUrl,
  );
  late final keyField = TextEditingController(text: widget.store.visionApi.key);
  late final model = TextEditingController(text: widget.store.visionApi.model);
  bool detecting = false;
  Timer? autosave;
  void scheduleSave() {
    autosave?.cancel();
    autosave = Timer(const Duration(milliseconds: 350), persist);
  }

  Future<void> persist() async {
    final config = widget.store.visionApi;
    config.baseUrl = address.text.trim();
    config.key = keyField.text.trim();
    config.model = model.text.trim();
    await widget.store.saveSettings(keys: true);
  }

  @override
  void dispose() {
    autosave?.cancel();
    if (autosave != null) persist();
    address.dispose();
    keyField.dispose();
    model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      const SizedBox(height: 16),
      Row(
        children: [
          const Expanded(child: Text('使用对话模型 API Key')),
          GlassToggle(
            value: widget.store.visionUsesChatKey,
            onChanged: (v) {
              setState(() => widget.store.visionUsesChatKey = v);
              persist();
            },
          ),
        ],
      ),
      if (widget.store.visionUsesChatKey)
        Text(
          widget.store.chatApi.baseUrl.isEmpty
              ? '请先配置对话模型地址'
              : widget.store.chatApi.baseUrl,
          style: TextStyle(fontSize: 12, color: muted(context)),
        ),
      if (!widget.store.visionUsesChatKey) ...[
        const SectionLabel('API 基础地址'),
        GlassField(
          controller: address,
          hint: 'https://example.com/v1',
          onChanged: (_) => scheduleSave(),
        ),
        const SectionLabel('API Key'),
        GlassField(
          controller: keyField,
          obscure: true,
          hint: '识图接口独立 Key',
          onChanged: (_) => scheduleSave(),
        ),
      ],
      const SectionLabel('模型 ID'),
      GlassField(
        controller: model,
        hint: '选择或填写支持图片输入的模型',
        onChanged: (_) => scheduleSave(),
      ),
      const SizedBox(height: 16),
      GlassButton(
        '检测识图接口模型',
        busy: detecting,
        onTap: detecting
            ? null
            : () async {
                await persist();
                setState(() => detecting = true);
                try {
                  final config = widget.store.effectiveVisionApi;
                  final models = await widget.api.discover(config);
                  widget.store.visionApi.models = models;
                  await persist();
                  if (mounted) setState(() {});
                } catch (e) {
                  if (mounted) toast(this.context, describeError(e));
                } finally {
                  if (mounted) setState(() => detecting = false);
                }
              },
      ),
      for (final id in widget.store.visionApi.models)
        ListTile(
          title: Text(id),
          trailing: model.text == id
              ? Icon(Icons.check_rounded, color: accent(context))
              : null,
          onTap: () {
            setState(() => model.text = id);
            persist();
          },
        ),
    ];
    return widget.embedded
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          )
        : SettingsDetail(title: '识图模型', children: children);
  }
}

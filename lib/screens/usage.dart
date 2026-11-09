import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../core/store.dart';
import '../ui/glass.dart';

class UsageScreen extends StatefulWidget {
  final AppStore store;
  const UsageScreen({super.key, required this.store});
  @override
  State<UsageScreen> createState() => _UsageScreenState();
}

class _UsageScreenState extends State<UsageScreen> {
  int period = 1;
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final start = period == 0
        ? DateTime(now.year, now.month, now.day)
        : period == 1
        ? now.subtract(const Duration(days: 7))
        : DateTime(2000);
    final records = widget.store.usage
        .where((u) => !u.time.isBefore(start))
        .toList();
    final input = records.fold(0, (sum, r) => sum + (r.inputTokens ?? 0));
    final output = records.fold(0, (sum, r) => sum + (r.outputTokens ?? 0));
    final known = records
        .where((r) => r.inputTokens != null || r.outputTokens != null)
        .length;
    final success = records.where((r) => r.success).length;
    final cost = records.fold(0.0, (sum, r) => sum + (r.estimatedCost ?? 0));
    final hasCost = records.any((r) => r.estimatedCost != null);
    final milliseconds = records.fold(0, (sum, r) => sum + r.milliseconds);
    final hours = List<int>.filled(24, 0);
    for (final r in records) {
      hours[r.time.toLocal().hour]++;
    }
    final models = records.map((r) => r.model).toSet();
    return Scaffold(
      body: StudioBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(22),
            children: [
              Row(
                children: [
                  GlassIcon(
                    Icons.arrow_back_rounded,
                    tooltip: '返回',
                    onTap: () => Navigator.pop(context),
                  ),
                  const Spacer(),
                  GlassIcon(
                    Icons.ios_share_rounded,
                    tooltip: '导出使用明细',
                    onTap: () async {
                      final content = StringBuffer(
                        '时间,操作,模型,状态,耗时ms,输入Token,输出Token,图片数,估算USD\r\n',
                      );
                      String cell(Object? value) {
                        var text = value?.toString() ?? '';
                        if (RegExp(r'^[=+@-]').hasMatch(text)) {
                          text = "'$text";
                        }
                        return '"${text.replaceAll('"', '""')}"';
                      }

                      for (final r in records) {
                        content.writeln(
                          [
                            r.time.toLocal().toIso8601String(),
                            r.operation,
                            r.model,
                            r.success ? '成功' : '失败',
                            r.milliseconds,
                            r.inputTokens,
                            r.outputTokens,
                            r.images,
                            r.estimatedCost,
                          ].map(cell).join(','),
                        );
                      }
                      final file = File(
                        '${widget.store.directory.path}/usage_${DateTime.now().millisecondsSinceEpoch}.csv',
                      );
                      await file.writeAsString('\uFEFF$content');
                      await SharePlus.instance.share(
                        ShareParams(files: [XFile(file.path)], text: '琉光使用明细'),
                      );
                    },
                  ),
                ],
              ),
              const PageHeader(title: '使用明细'),
              GlassSegments(
                labels: const ['今天', '近 7 天', '全部'],
                selected: period,
                onChanged: (v) => setState(() => period = v),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: _metric(
                      context,
                      '请求次数',
                      '${records.length}',
                      '$success 次成功',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _metric(
                      context,
                      '已知 Token',
                      _number(input + output),
                      '$known 次返回用量',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _metric(
                      context,
                      '估算费用 / USD',
                      hasCost ? '\$${cost.toStringAsFixed(4)}' : '—',
                      '按自定义单价估算',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _metric(
                      context,
                      '平均耗时',
                      records.isEmpty
                          ? '—'
                          : '${(milliseconds / records.length / 1000).toStringAsFixed(1)}s',
                      '包含失败与取消',
                    ),
                  ),
                ],
              ),
              const SectionLabel('24 小时创作分布', caption: '本地时间'),
              Glass(
                child: Column(
                  children: [
                    SizedBox(
                      height: 130,
                      child: CustomPaint(
                        size: const Size(double.infinity, 130),
                        painter: _HoursPainter(
                          hours,
                          accentInk(context),
                          muted(context),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        for (final text in [
                          '00:00',
                          '06:00',
                          '12:00',
                          '18:00',
                          '23:00',
                        ])
                          Text(
                            text,
                            style: TextStyle(
                              fontSize: 12,
                              color: muted(context),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SectionLabel('模型用量'),
              if (models.isEmpty)
                Text(
                  '还没有请求记录。',
                  style: TextStyle(fontSize: 14, color: muted(context)),
                ),
              for (final model in models) ...[
                Glass(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        model,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '${records.where((r) => r.model == model).length} 次请求 · ${records.where((r) => r.model == model).fold(0, (s, r) => s + r.images)} 张图片',
                        style: TextStyle(fontSize: 12, color: muted(context)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 9),
              ],
              const SectionLabel('请求明细'),
              if (records.isEmpty)
                const EmptyState(
                  icon: Icons.bar_chart_rounded,
                  title: '从第一次创作开始',
                  subtitle: '请求耗时、模型与服务端返回的 Token\n会自动记录在这里。',
                ),
              for (final r in records.take(200))
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => glassSheet(
                      context,
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            r.operation,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 16),
                          StudioSelectable(
                            '模型：${r.model}\n时间：${r.time.toLocal()}\n耗时：${r.milliseconds} ms\n输入 Token：${r.inputTokens ?? '服务端未返回'}\n输出 Token：${r.outputTokens ?? '服务端未返回'}\n图片：${r.images}\n估算 USD：${r.estimatedCost?.toStringAsFixed(6) ?? '未设置单价或无用量'}${r.error == null ? '' : '\n错误：${r.error}'}',
                            style: const TextStyle(fontSize: 14, height: 1.9),
                          ),
                        ],
                      ),
                    ),
                    child: Glass(
                      padding: const EdgeInsets.all(15),
                      child: Row(
                        children: [
                          Icon(
                            r.success
                                ? Icons.check_circle_outline_rounded
                                : Icons.error_outline_rounded,
                            size: 20,
                            color: r.success
                                ? accentInk(context)
                                : const Color(0xffd58e7d),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  r.operation,
                                  style: const TextStyle(fontSize: 14),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  r.model,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: muted(context),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${(r.milliseconds / 1000).toStringAsFixed(1)}s',
                                style: const TextStyle(fontSize: 14),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${r.time.toLocal().hour.toString().padLeft(2, '0')}:${r.time.toLocal().minute.toString().padLeft(2, '0')}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: muted(context),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 15),
              Text(
                'Token 仅累计 API 实际返回值；未返回时显示未知。费用为本机估算，实际扣费以服务商账单为准。此页仅记录本机发起的请求。',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.8,
                  color: muted(context),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _metric(
  BuildContext context,
  String label,
  String value,
  String caption,
) => Glass(
  padding: const EdgeInsets.all(16),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: TextStyle(fontSize: 12, color: muted(context))),
      const SizedBox(height: 14),
      Text(
        value,
        style: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          letterSpacing: -1,
        ),
      ),
      const SizedBox(height: 9),
      Text(caption, style: TextStyle(fontSize: 12, color: muted(context))),
    ],
  ),
);
String _number(int n) => n >= 1000000
    ? '${(n / 1000000).toStringAsFixed(1)}M'
    : n >= 10000
    ? '${(n / 1000).toStringAsFixed(1)}K'
    : '$n';

class _HoursPainter extends CustomPainter {
  final List<int> values;
  final Color color, grid;
  _HoursPainter(this.values, this.color, this.grid);
  @override
  void paint(Canvas canvas, Size size) {
    final maximum = values.fold(1, (a, b) => a > b ? a : b);
    for (var i = 0; i < 4; i++) {
      final y = i * size.height / 3;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()..color = grid.withValues(alpha: .1),
      );
    }
    for (var i = 0; i < 24; i++) {
      final width = size.width / 24;
      final h = values[i] == 0 ? 3.0 : values[i] / maximum * (size.height - 8);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(i * width + 2, size.height - h, width - 4, h),
          const Radius.circular(3),
        ),
        Paint()
          ..color = values[i] == 0
              ? color.withValues(alpha: .13)
              : color.withValues(alpha: .8),
      );
    }
  }

  @override
  bool shouldRepaint(_HoursPainter old) => true;
}

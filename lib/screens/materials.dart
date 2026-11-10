import 'package:flutter/material.dart';

import '../core/materials.dart';
import '../ui/glass.dart';

class MaterialPicker extends StatefulWidget {
  final String? initialId;
  const MaterialPicker({super.key, this.initialId});
  @override
  State<MaterialPicker> createState() => _MaterialPickerState();
}

class _MaterialPickerState extends State<MaterialPicker> {
  late String category =
      materialById(widget.initialId)?.category ?? materialCategories.first;
  late String? selected = widget.initialId;
  @override
  Widget build(BuildContext context) {
    final items = studioMaterials.where((m) => m.category == category).toList();
    final current = materialById(selected);
    return Scaffold(
      body: StudioBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
                child: Row(
                  children: [
                    GlassIcon(
                      Icons.arrow_back_rounded,
                      tooltip: '返回',
                      onTap: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Text(
                        '材质',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    GlassButton(
                      '不使用',
                      small: true,
                      onTap: () => Navigator.pop(context, ''),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 48,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  scrollDirection: Axis.horizontal,
                  itemCount: materialCategories.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (_, i) => GlassButton(
                    materialCategories[i],
                    small: true,
                    primary: category == materialCategories[i],
                    onTap: () =>
                        setState(() => category = materialCategories[i]),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: GridView.builder(
                  key: ValueKey(category),
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 210,
                    childAspectRatio: .76,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: items.length,
                  itemBuilder: (_, i) {
                    final m = items[i];
                    final active = selected == m.id;
                    return Semantics(
                      excludeSemantics: true,
                      button: true,
                      selected: active,
                      label: m.name,
                      child: GestureDetector(
                        onTap: () => setState(() => selected = m.id),
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: isDark(context)
                                ? const Color(0xff20252c)
                                : Colors.white.withValues(alpha: .75),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color: active
                                  ? accent(context)
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: Image.asset(
                                    m.preview,
                                    fit: BoxFit.cover,
                                    filterQuality: FilterQuality.high,
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(9, 12, 9, 8),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        m.name,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    if (active)
                                      Icon(
                                        Icons.check_circle_rounded,
                                        size: 18,
                                        color: accent(context),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (current != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Text(
                          current.description,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.6,
                            color: muted(context),
                          ),
                        ),
                      ),
                    GlassButton(
                      current == null ? '保持原有材质' : '应用 · ${current.name}',
                      primary: true,
                      onTap: () => Navigator.pop(context, selected ?? ''),
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
}

class MaterialSelection extends StatelessWidget {
  final String? selected;
  final ValueChanged<String?> onChanged;
  const MaterialSelection({
    super.key,
    required this.selected,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) {
    final material = materialById(selected);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        final result = await Navigator.push<String>(
          context,
          MaterialPageRoute(
            builder: (_) => MaterialPicker(initialId: selected),
          ),
        );
        if (result != null) onChanged(result.isEmpty ? null : result);
      },
      child: Glass(
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: material == null
                  ? Container(
                      width: 60,
                      height: 60,
                      color: accent(context).withValues(alpha: .08),
                      child: Icon(
                        Icons.blur_on_rounded,
                        color: accent(context),
                        size: 28,
                      ),
                    )
                  : Image.asset(
                      material.preview,
                      width: 60,
                      height: 60,
                      fit: BoxFit.cover,
                    ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    material?.name ?? '保留原有材质',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    material == null
                        ? '光透、毛绒、金属与更多'
                        : '${material.category} · 点按更换',
                    style: TextStyle(fontSize: 12, color: muted(context)),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: muted(context)),
          ],
        ),
      ),
    );
  }
}

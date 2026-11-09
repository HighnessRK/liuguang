import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart' as mx;

/// All editable fields share Flutter's editing pipeline and a Miuix skin.
/// Hint rendering depends on EditableText's real value, including IME composing
/// and programmatic controller updates; no separate placeholder overlay exists.
class StudioEditable extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final int minLines, maxLines;
  final bool obscure;
  final TextInputType? keyboard;
  final ValueChanged<String>? onChanged;
  final Widget? suffix;
  const StudioEditable({
    super.key,
    required this.controller,
    required this.hint,
    this.minLines = 1,
    this.maxLines = 1,
    this.obscure = false,
    this.keyboard,
    this.onChanged,
    this.suffix,
  });
  @override
  Widget build(BuildContext context) {
    final c = mx.MiuixTheme.of(context).colors;
    final shape = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide.none,
    );
    return TextField(
      controller: controller,
      minLines: obscure ? 1 : minLines,
      maxLines: obscure ? 1 : maxLines,
      obscureText: obscure,
      textAlignVertical: maxLines > 1
          ? TextAlignVertical.top
          : TextAlignVertical.center,
      keyboardType: keyboard,
      onChanged: onChanged,
      enableInteractiveSelection: true,
      autocorrect: !obscure && keyboard == null,
      enableSuggestions: !obscure && keyboard == null,
      contextMenuBuilder: studioEditingMenu,
      style: TextStyle(fontSize: 16, color: c.onSurface, height: 1.5),
      cursorColor: c.primary,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          fontSize: 16,
          color: c.onSurfaceVariantSummary.withValues(alpha: .7),
        ),
        filled: true,
        fillColor: c.surfaceContainer,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        suffixIcon: suffix,
        border: shape,
        enabledBorder: shape,
        focusedBorder: shape.copyWith(
          borderSide: BorderSide(
            color: c.primary.withValues(alpha: .5),
            width: 1.2,
          ),
        ),
      ),
    );
  }
}

Widget studioEditingMenu(BuildContext context, EditableTextState state) {
  const labels = {
    ContextMenuButtonType.cut: '剪切',
    ContextMenuButtonType.copy: '复制',
    ContextMenuButtonType.paste: '粘贴',
    ContextMenuButtonType.selectAll: '全选',
  };
  final items = state.contextMenuButtonItems.where(
    (item) => labels.containsKey(item.type),
  );
  return TextSelectionToolbar(
    anchorAbove: state.contextMenuAnchors.primaryAnchor,
    anchorBelow:
        state.contextMenuAnchors.secondaryAnchor ??
        state.contextMenuAnchors.primaryAnchor,
    children: [
      for (final item in items)
        TextButton(
          onPressed: item.onPressed,
          style: TextButton.styleFrom(
            foregroundColor: mx.MiuixTheme.of(context).colors.primary,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
          child: Text(labels[item.type]!, style: const TextStyle(fontSize: 14)),
        ),
    ],
  );
}

class StudioSelectable extends StatelessWidget {
  final String data;
  final TextStyle? style;
  const StudioSelectable(this.data, {super.key, this.style});
  @override
  Widget build(BuildContext context) =>
      SelectableText(data, style: style, contextMenuBuilder: studioEditingMenu);
}

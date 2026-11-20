import 'dart:ui';

import 'package:flutter/material.dart';

class GlassScheme {
  final bool isDark;
  const GlassScheme(this.isDark);

  static GlassScheme of(BuildContext context) =>
      GlassScheme(Theme.of(context).brightness == Brightness.dark);

  // 文本
  Color get textPrimary =>
      isDark ? Colors.white : const Color(0xFF16181D);
  Color get textSecondary => isDark
      ? Colors.white.withValues(alpha: 0.65)
      : Colors.black.withValues(alpha: 0.6);
  Color get textHint => isDark
      ? Colors.white.withValues(alpha: 0.35)
      : Colors.black.withValues(alpha: 0.35);
  Color get textDisabled => isDark
      ? Colors.white.withValues(alpha: 0.3)
      : Colors.black.withValues(alpha: 0.3);

  // 玻璃卡片
  Color get cardFill => isDark
      ? Colors.white.withValues(alpha: 0.07)
      : Colors.white.withValues(alpha: 0.55);
  Color get cardGradientTop => isDark
      ? Colors.white.withValues(alpha: 0.14)
      : Colors.white.withValues(alpha: 0.8);
  Color get cardGradientBottom => isDark
      ? Colors.white.withValues(alpha: 0.04)
      : Colors.white.withValues(alpha: 0.45);
  Color get cardBorder => isDark
      ? Colors.white.withValues(alpha: 0.18)
      : Colors.white.withValues(alpha: 0.7);
  Color get cardShadow => isDark
      ? Colors.black.withValues(alpha: 0.25)
      : Colors.black.withValues(alpha: 0.08);

  // 输入框 / 次级表面
  Color get fieldFill => isDark
      ? Colors.black.withValues(alpha: 0.22)
      : Colors.white.withValues(alpha: 0.6);
  Color get fieldBorder => isDark
      ? Colors.white.withValues(alpha: 0.12)
      : Colors.black.withValues(alpha: 0.1);
  Color get chipFill => isDark
      ? Colors.white.withValues(alpha: 0.12)
      : Colors.white.withValues(alpha: 0.65);

  // 语义色
  Color get success => const Color(0xFF30D158);
  Color get danger => const Color(0xFFFF453A);
  Color get accent => const Color(0xFF0A84FF);

  Color get successText =>
      isDark ? const Color(0xFF7BE495) : const Color(0xFF1E8E3E);
  Color get dangerText =>
      isDark ? const Color(0xFFFF8A80) : const Color(0xFFC5221F);
  Color get warnText =>
      isDark ? const Color(0xFFFFD166) : const Color(0xFF9A6700);

  Color logDefault() => isDark
      ? Colors.white.withValues(alpha: 0.75)
      : Colors.black.withValues(alpha: 0.75);

  // 课程卡片选中/未选中底色
  Color courseFill(bool selected) => isDark
      ? Colors.white.withValues(alpha: selected ? 0.07 : 0.03)
      : Colors.white.withValues(alpha: selected ? 0.75 : 0.45);
  Color courseBorder(bool grabbed) => grabbed
      ? success.withValues(alpha: 0.5)
      : isDark
          ? Colors.white.withValues(alpha: 0.1)
          : Colors.black.withValues(alpha: 0.08);
}

class LiquidBackground extends StatelessWidget {
  const LiquidBackground({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (isDark) {
      return Container(
        color: const Color(0xFF0A0D14),
        child: Stack(
          children: [
            Positioned(top: -120, left: -80, child: _blob(const Color(0xFF3A6DFF), 380, 0.5)),
            Positioned(top: 120, right: -140, child: _blob(const Color(0xFF8A4DFF), 420, 0.38)),
            Positioned(bottom: -160, left: 180, child: _blob(const Color(0xFF00C2A8), 460, 0.3)),
            Positioned(bottom: 40, right: 60, child: _blob(const Color(0xFFFF5E8A), 300, 0.22)),
          ],
        ),
      );
    }
    return Container(
      color: const Color(0xFFE9EDF5),
      child: Stack(
        children: [
          Positioned(top: -120, left: -80, child: _blob(const Color(0xFF3A6DFF), 380, 0.3)),
          Positioned(top: 120, right: -140, child: _blob(const Color(0xFF8A4DFF), 420, 0.22)),
          Positioned(bottom: -160, left: 180, child: _blob(const Color(0xFF00C2A8), 460, 0.2)),
          Positioned(bottom: 40, right: 60, child: _blob(const Color(0xFFFF5E8A), 300, 0.16)),
        ],
      ),
    );
  }

  Widget _blob(Color color, double size, double opacity) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color.withValues(alpha: opacity),
            color.withValues(alpha: 0.0),
          ],
        ),
      ),
    );
  }
}

/// 玻璃容器：毛玻璃模糊 + 顶部高光描边 + 内侧反光渐变
class GlassContainer extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double blur;

  const GlassContainer({
    super.key,
    required this.child,
    this.radius = 22,
    this.padding = const EdgeInsets.all(20),
    this.margin,
    this.blur = 24,
  });

  @override
  Widget build(BuildContext context) {
    final s = GlassScheme.of(context);
    return Container(
      padding: margin ?? EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              color: s.cardFill,
              border: Border.all(color: s.cardBorder, width: 1),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [s.cardGradientTop, s.cardGradientBottom],
              ),
              boxShadow: [
                BoxShadow(
                  color: s.cardShadow,
                  blurRadius: 30,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

/// 玻璃按钮（主操作 / 次操作）
class GlassButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool primary;
  final Color? accent;

  const GlassButton({
    super.key,
    required this.label,
    required this.icon,
    this.onPressed,
    this.primary = false,
    this.accent,
  });

  @override
  State<GlassButton> createState() => _GlassButtonState();
}

class _GlassButtonState extends State<GlassButton> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final s = GlassScheme.of(context);
    final accent = widget.accent ?? s.accent;
    final enabled = widget.onPressed != null;
    // 禁用态：无 hover / 无按压动效，保持静止；hover 不再放大，改为发光
    final glow = enabled && _hover;
    final scale = !enabled ? 1.0 : (_down ? 0.97 : 1.0);
    final glowColor = widget.primary
        ? (widget.accent ?? s.accent)
        : s.isDark
            ? Colors.white
            : s.accent;

    final Color fill = widget.primary
        ? accent.withValues(alpha: enabled ? 0.85 : 0.35)
        : s.chipFill.withValues(alpha: enabled ? 1.0 : (s.isDark ? 0.05 : 0.35));
    final Color fg = widget.primary
        ? Colors.white
        : (enabled ? s.textPrimary.withValues(alpha: 0.92) : s.textDisabled);

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) {
        if (enabled) setState(() => _hover = true);
      },
      onExit: (_) => setState(() {
        _hover = false;
        _down = false;
      }),
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: enabled ? () => setState(() => _down = false) : null,
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 90),
          curve: Curves.easeOutBack,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 80),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              color: fill,
              border: Border.all(
                color: glow
                    ? glowColor.withValues(alpha: 0.8)
                    : s.isDark
                        ? Colors.white.withValues(alpha: 0.22)
                        : Colors.white.withValues(alpha: 0.8),
                width: 1,
              ),
              // hover 发光效果
              boxShadow: glow
                  ? [
                      BoxShadow(
                        color: glowColor.withValues(alpha: 0.45),
                        blurRadius: 14,
                        spreadRadius: 1,
                      ),
                    ]
                  : const [],
              gradient: widget.primary
                  ? LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        accent.withValues(alpha: 0.95),
                        accent.withValues(alpha: 0.7),
                      ],
                    )
                  : LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: enabled
                          ? [
                              s.isDark
                                  ? Colors.white.withValues(alpha: 0.16)
                                  : Colors.white.withValues(alpha: 0.85),
                              s.isDark
                                  ? Colors.white.withValues(alpha: 0.06)
                                  : Colors.white.withValues(alpha: 0.55),
                            ]
                          : [
                              s.isDark
                                  ? Colors.white.withValues(alpha: 0.08)
                                  : Colors.white.withValues(alpha: 0.5),
                              s.isDark
                                  ? Colors.white.withValues(alpha: 0.03)
                                  : Colors.white.withValues(alpha: 0.3),
                            ],
                    ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.icon, size: 15, color: fg),
                const SizedBox(width: 7),
                Text(
                  widget.label,
                  style: TextStyle(
                    color: fg,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 玻璃输入框；obscure=true 时右侧出现眼睛图标切换明文
class GlassTextField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final bool obscure;
  final IconData icon;
  final ValueChanged<String>? onChanged;
  final String? hint;

  /// true = 标签并入输入框作为占位文字
  /// false = 标签显示在输入框上方
  final bool labelInside;

  /// 紧凑模式：更小的内边距与字号
  final bool compact;

  const GlassTextField({
    super.key,
    required this.controller,
    required this.label,
    required this.icon,
    this.obscure = false,
    this.onChanged,
    this.hint,
    this.labelInside = true,
    this.compact = false,
  });

  @override
  State<GlassTextField> createState() => _GlassTextFieldState();
}

class _GlassTextFieldState extends State<GlassTextField> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) {
    final s = GlassScheme.of(context);
    // 标签并入输入框作为占位文字，或显示在上方
    final hint = widget.labelInside
        ? (widget.hint ?? widget.label)
        : widget.hint;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!widget.labelInside) ...[
          Text(
            widget.label,
            style: TextStyle(
              color: s.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
        ],
        Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: s.fieldFill,
        border: Border.all(color: s.fieldBorder, width: 1),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          Icon(widget.icon, size: widget.compact ? 12 : 14, color: s.textHint),
          const SizedBox(width: 7),
          Expanded(
            child: TextField(
              controller: widget.controller,
              obscureText: widget.obscure && !_visible,
              onChanged: widget.onChanged,
              style: TextStyle(
                color: s.textPrimary,
                fontSize: widget.compact ? 12 : 12.5,
                letterSpacing: 0.2,
              ),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: hint,
                hintStyle: TextStyle(
                  color: s.textHint,
                  fontSize: widget.compact ? 12 : 12.5,
                ),
                contentPadding:
                    EdgeInsets.symmetric(vertical: widget.compact ? 5.5 : 9),
              ),
            ),
          ),
          if (widget.obscure)
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28),
              icon: Icon(
                _visible ? Icons.visibility_off : Icons.visibility,
                size: 16,
                color: s.textSecondary,
              ),
              tooltip: _visible ? '隐藏密码' : '显示密码',
              onPressed: () => setState(() => _visible = !_visible),
            ),
        ],
      ),
        ),
      ],
    );
  }
}

/// 玻璃风格日期时间选择框：点击弹出日期选择器 + 时间选择器，
/// enabled=false 时置灰且不可交互
class GlassDateTimeField extends StatelessWidget {
  final String value;
  final bool enabled;
  final ValueChanged<DateTime> onPicked;

  const GlassDateTimeField({
    super.key,
    required this.value,
    required this.enabled,
    required this.onPicked,
  });

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final initial =
        DateTime.tryParse(value) ?? now.add(const Duration(hours: 1));

    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
    );
    if (date == null || !context.mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !context.mounted) return;

    onPicked(
        DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  @override
  Widget build(BuildContext context) {
    final s = GlassScheme.of(context);
    return Opacity(
      opacity: enabled ? 1.0 : 0.45,
      child: GestureDetector(
        onTap: enabled ? () => _pick(context) : null,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: s.fieldFill,
            border: Border.all(color: s.fieldBorder, width: 1),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.event, size: 14, color: s.textHint),
              const SizedBox(width: 7),
              Text(
                value.isEmpty ? '请选择开始时间' : value,
                style: TextStyle(
                  color: value.isEmpty ? s.textHint : s.textPrimary,
                  fontSize: 12.5,
                  letterSpacing: 0.2,
                ),
              ),
              const Spacer(),
              if (enabled)
                Icon(Icons.arrow_drop_down,
                    size: 18, color: s.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

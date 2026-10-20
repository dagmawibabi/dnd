import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_theme.dart';

export 'app_theme.dart';

/// Flat card: surface, hairline border, rounded corners.
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap, this.color, this.borderColor, this.radius = 16, this.margin});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final Color? borderColor;
  final double radius;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius), side: BorderSide(color: borderColor ?? AppColors.border));
    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: Material(
        color: color ?? AppColors.surface,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Small uppercase section label with optional trailing action.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing, this.padding = const EdgeInsets.fromLTRB(4, 24, 4, 10)});
  final String text;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(children: [
        Expanded(child: Text(text.toUpperCase(), style: T.overline())),
        ?trailing,
      ]),
    );
  }
}

enum ButtonKind { primary, secondary, ghost, danger, accent }

class AppButton extends StatelessWidget {
  const AppButton({super.key, required this.label, this.onPressed, this.icon, this.kind = ButtonKind.primary, this.expand = true, this.busy = false, this.height = 48});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final ButtonKind kind;
  final bool expand;
  final bool busy;
  final double height;

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg, Color? border) = switch (kind) {
      ButtonKind.primary => (AppColors.text, AppColors.bg, null),
      ButtonKind.secondary => (AppColors.surface2, AppColors.text, AppColors.border),
      ButtonKind.ghost => (Colors.transparent, AppColors.text, null),
      ButtonKind.danger => (AppColors.danger.withValues(alpha: 0.12), AppColors.danger, null),
      ButtonKind.accent => (AppColors.accent, Colors.white, null),
    };
    final enabled = onPressed != null && !busy;
    final child = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (busy)
          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: fg))
        else if (icon != null)
          Icon(icon, size: 18, color: fg),
        if (busy || icon != null) const SizedBox(width: 8),
        Flexible(child: Text(label, style: T.h3(color: fg), overflow: TextOverflow.ellipsis)),
      ],
    );
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: SizedBox(
        height: height,
        child: Material(
          color: bg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: border == null ? BorderSide.none : BorderSide(color: border)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled
                ? () {
                    HapticFeedback.selectionClick();
                    onPressed!();
                  }
                : null,
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: child),
          ),
        ),
      ),
    );
  }
}

/// Round icon button on a subtle surface.
class CircleIconButton extends StatelessWidget {
  const CircleIconButton({super.key, required this.icon, required this.onPressed, this.tooltip, this.badge = false, this.busy = false, this.size = 40});
  final bool busy;
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool badge;
  final double size;

  @override
  Widget build(BuildContext context) {
    final btn = SizedBox(
      width: size,
      height: size,
      child: Material(
        color: AppColors.surface2,
        shape: const CircleBorder(side: BorderSide(color: AppColors.border)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: busy ? null : onPressed,
          child: Center(child: busy
              ? SizedBox.square(dimension: size * 0.48, child: const CircularProgressIndicator(strokeWidth: 2))
              : Badge(isLabelVisible: badge, smallSize: 7, child: Icon(icon, size: size * 0.48, color: onPressed == null ? AppColors.textFaint : AppColors.text))),
        ),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
  }
}

/// Selectable card with a check indicator.
class SelectCard extends StatelessWidget {
  const SelectCard({super.key, required this.selected, required this.onTap, required this.child, this.padding = const EdgeInsets.all(14), this.showCheck = true});
  final bool selected;
  final VoidCallback onTap;
  final Widget child;
  final EdgeInsets padding;
  final bool showCheck;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      decoration: BoxDecoration(
        color: selected ? AppColors.surface2 : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: selected ? AppColors.text : AppColors.border, width: selected ? 1.4 : 1),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Stack(children: [
            Padding(padding: padding, child: child),
            if (showCheck && selected)
              const Positioned(top: 8, right: 8, child: Icon(Icons.check_circle, size: 18, color: AppColors.text)),
          ]),
        ),
      ),
    );
  }
}

/// Settings-style row.
class ListRow extends StatelessWidget {
  const ListRow({super.key, required this.title, this.subtitle, this.leading, this.trailing, this.onTap, this.danger = false});
  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          if (leading != null) ...[leading!, const SizedBox(width: 14)],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: T.body(color: danger ? AppColors.danger : AppColors.text)),
              if (subtitle != null && subtitle!.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(subtitle!, style: T.small())),
            ]),
          ),
          if (trailing != null) trailing! else if (onTap != null) const Icon(Icons.chevron_right, size: 20, color: AppColors.textFaint),
        ]),
      ),
    );
  }
}

/// Group of rows inside a card with dividers.
class RowGroup extends StatelessWidget {
  const RowGroup({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const Divider(indent: 16),
          children[i],
        ],
      ]),
    );
  }
}

class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this.icon, this.color = AppColors.textMuted, this.filled = false});
  final String text;
  final IconData? icon;
  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: filled ? color.withValues(alpha: 0.14) : AppColors.surface2,
        borderRadius: BorderRadius.circular(999),
        border: filled ? null : Border.all(color: AppColors.border),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 13, color: color), const SizedBox(width: 4)],
        Text(text, style: T.caption(color: filled ? color : AppColors.textMuted)),
      ]),
    );
  }
}

/// Thin rounded progress bar.
class Bar extends StatelessWidget {
  const Bar({super.key, required this.value, required this.max, this.color = AppColors.text, this.height = 4});
  final num value;
  final num max;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final f = max <= 0 ? 0.0 : (value / max).clamp(0.0, 1.0).toDouble();
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: Stack(children: [
          Container(color: AppColors.surface3),
          AnimatedFractionallySizedBox(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutCubic,
            widthFactor: f,
            child: Container(color: color),
          ),
        ]),
      ),
    );
  }
}

/// Compact label/value statistic.
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value, this.sub});
  final String label;
  final String value;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
      // Scales down instead of overflowing in tight grid cells or with large text.
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(value, style: T.number(20), maxLines: 1),
            const SizedBox(height: 2),
            Text(label, style: T.caption(), maxLines: 1, textAlign: TextAlign.center),
            if (sub != null) Text(sub!, style: T.caption(), maxLines: 1),
          ]),
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
            child: Icon(icon, color: AppColors.textMuted),
          ),
          const SizedBox(height: 16),
          Text(title, style: T.h3(), textAlign: TextAlign.center),
          if (message != null) ...[const SizedBox(height: 6), Text(message!, style: T.small(), textAlign: TextAlign.center)],
          if (action != null) ...[const SizedBox(height: 20), action!],
        ]),
      ),
    );
  }
}

/// Large page title used at the top of tabs.
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: T.h1()),
            if (subtitle != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(subtitle!, style: T.small())),
          ]),
        ),
        ?trailing,
      ]),
    );
  }
}

/// Constrains content to a readable column on large screens.
class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child, this.maxWidth = 720});
  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Center(heightFactor: 1, child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child));
}

/// Subtle fade-in.
class FadeIn extends StatefulWidget {
  const FadeIn({super.key, required this.child, this.delay = Duration.zero});
  final Widget child;
  final Duration delay;

  @override
  State<FadeIn> createState() => _FadeInState();
}

class _FadeInState extends State<FadeIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 280));

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return widget.child;
    return FadeTransition(
      opacity: CurvedAnimation(parent: _c, curve: Curves.easeOut),
      child: SlideTransition(position: Tween(begin: const Offset(0, 0.02), end: Offset.zero).animate(CurvedAnimation(parent: _c, curve: Curves.easeOut)), child: widget.child),
    );
  }
}

Future<R?> showAppSheet<R>(BuildContext context, {required WidgetBuilder builder}) {
  return showModalBottomSheet<R>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: builder,
  );
}

/// Title row used at the top of bottom sheets.
class SheetTitle extends StatelessWidget {
  const SheetTitle(this.title, {super.key, this.subtitle});
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: T.h2()),
        if (subtitle != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(subtitle!, style: T.small())),
      ]),
    );
  }
}

void showToast(BuildContext context, String message, {IconData icon = Icons.check_circle_outline}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Row(children: [Icon(icon, color: AppColors.textMuted, size: 18), const SizedBox(width: 10), Expanded(child: Text(message))]),
      duration: const Duration(seconds: 3),
    ));
}

Future<bool> confirm(BuildContext context, {required String title, required String message, String action = 'Delete', bool danger = true}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel', style: T.h3(color: AppColors.textMuted))),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(action, style: T.h3(color: danger ? AppColors.danger : AppColors.text))),
      ],
    ),
  );
  return r == true;
}

/// Tighter chips: no 48px touch-target padding between rows of chips.
class CompactChips extends StatelessWidget {
  const CompactChips({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Theme(
      data: t.copyWith(
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        chipTheme: t.chipTheme.copyWith(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), labelPadding: const EdgeInsets.symmetric(horizontal: 4)),
      ),
      child: child,
    );
  }
}

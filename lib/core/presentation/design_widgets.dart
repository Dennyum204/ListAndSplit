import 'package:flutter/material.dart';

import '../theme/app_palette.dart';

/// Inset rounded header; it deliberately leaves the system status bar native.
class AppPageHeader extends StatelessWidget implements PreferredSizeWidget {
  const AppPageHeader({
    required this.title,
    this.leading,
    this.actions,
    this.bottom,
    this.automaticallyImplyLeading = true,
    super.key,
  });

  final Widget title;
  final Widget? leading;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final bool automaticallyImplyLeading;

  @override
  Size get preferredSize =>
      Size.fromHeight(72 + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) => SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: AppBar(
              primary: false,
              title: DefaultTextStyle.merge(
                  maxLines: 1, overflow: TextOverflow.ellipsis, child: title),
              leading: leading,
              actions: actions,
              bottom: bottom,
              automaticallyImplyLeading: automaticallyImplyLeading,
              titleSpacing: 16,
            ),
          ),
        ),
      );
}

class AppSectionCard extends StatelessWidget {
  const AppSectionCard(
      {required this.child,
      this.padding = const EdgeInsets.all(16),
      this.tonal = false,
      this.color,
      this.shape,
      super.key});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool tonal;
  final Color? color;
  final ShapeBorder? shape;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        color: color ??
            (tonal ? Theme.of(context).colorScheme.secondaryContainer : null),
        shape: shape,
        child: Padding(padding: padding, child: child),
      );
}

/// A decorative identity marker, not an uploaded image or online-status signal.
class IdentityBadge extends StatelessWidget {
  const IdentityBadge(
      {required this.label, this.size = 40, this.backgroundColor, super.key});
  final String label;
  final double size;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final value = label.trim();
    return ExcludeSemantics(
      child: CircleAvatar(
        radius: size / 2,
        backgroundColor: backgroundColor ?? AppPalette.inputCream,
        foregroundColor: AppPalette.navy,
        child: value.isEmpty
            ? Icon(Icons.person_outline_rounded, size: size * .5)
            : Padding(
                padding: EdgeInsets.all(size * .16),
                child: FittedBox(
                    child: Text(value.characters.first.toUpperCase(),
                        style: TextStyle(
                            fontSize: size * .46,
                            fontWeight: FontWeight.w600))),
              ),
      ),
    );
  }
}

/// Use with AlertDialog.titlePadding = EdgeInsets.zero for the reference strip.
class AppDialogTitle extends StatelessWidget {
  const AppDialogTitle(this.title, {super.key});
  final String title;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: const BoxDecoration(
          color: AppPalette.orange,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Text(title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppPalette.navy, fontWeight: FontWeight.w700)),
      );
}

/// Persistent, unfilled field caption, separate from the cream input surface.
///
/// The child keeps its editing/focus lifecycle and validation semantics. Omit
/// its InputDecoration.labelText: the outer semantics supplies the label once,
/// including when the field is filled, focused, disabled, or showing an error.
/// Dropdown children use isDense: false so scaled text retains its line height.
class AppDialogField extends StatelessWidget {
  const AppDialogField({required this.label, required this.child, super.key});

  /// Non-dense dropdowns retain their 48dp minimum and grow with scaled text.
  /// Only their surrounding padding shrinks; captions stay outside the fill.
  static const dropdownPadding =
      EdgeInsets.symmetric(horizontal: 16, vertical: 4);

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExcludeSemantics(
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
          const SizedBox(height: 8),
          Semantics(label: label, child: child),
        ],
      );
}

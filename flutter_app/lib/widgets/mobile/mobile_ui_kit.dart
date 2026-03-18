import 'package:flutter/material.dart';

import 'mobile_surface.dart';

class MobileSectionTitle extends StatelessWidget {
  const MobileSectionTitle({
    super.key,
    required this.title,
    this.trailing,
    this.topPadding = 0,
  });

  final String title;
  final Widget? trailing;
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: topPadding),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: Color(0xFF1C1917),
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class MobileSurfaceCard extends StatelessWidget {
  const MobileSurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF0EEEB)),
        boxShadow: const [MobileImmersiveBackground.cardShadow],
      ),
      child: child,
    );
  }
}

class MobilePillTag extends StatelessWidget {
  const MobilePillTag({
    super.key,
    required this.text,
    this.background = const Color(0xFFF5F5F4),
    this.foreground = const Color(0xFF57534E),
  });

  final String text;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: foreground,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class MobilePrimaryButton extends StatelessWidget {
  const MobilePrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFF4338CA),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(label),
    );
  }
}

class MobileOutlineButton extends StatelessWidget {
  const MobileOutlineButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final style = OutlinedButton.styleFrom(
      foregroundColor: const Color(0xFF4338CA),
      side: const BorderSide(color: Color(0xFFD8D6F7)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    );
    if (icon != null) {
      return OutlinedButton.icon(
        onPressed: onPressed,
        style: style,
        icon: Icon(icon, size: 18),
        label: Text(label),
      );
    }
    return OutlinedButton(
      onPressed: onPressed,
      style: style,
      child: Text(label),
    );
  }
}

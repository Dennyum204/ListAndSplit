import 'package:flutter/material.dart';

/// Shared snapshot/item presentation; quantities remain exact domain strings.
class TemplateItemTile extends StatelessWidget {
  const TemplateItemTile({
    required this.name,
    required this.quantity,
    this.onTap,
    this.actions,
    super.key,
  });

  final String name;
  final String quantity;
  final VoidCallback? onTap;
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 21;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: largeText
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name,
                                style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 4),
                            Text(quantity),
                          ],
                        )
                      : Row(
                          children: [
                            Expanded(
                              child: Text(name,
                                  style:
                                      Theme.of(context).textTheme.titleMedium),
                            ),
                            const SizedBox(width: 12),
                            Text(quantity),
                          ],
                        ),
                ),
              ),
              if (actions != null) ...[
                const SizedBox(width: 4),
                actions!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

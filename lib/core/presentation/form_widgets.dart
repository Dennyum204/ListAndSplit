import 'package:flutter/material.dart';

class FormPageFrame extends StatelessWidget {
  const FormPageFrame({
    required this.title,
    required this.description,
    required this.child,
    this.leading,
    this.actions,
    super.key,
  });

  final String title;
  final String description;
  final Widget child;
  final Widget? leading;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(leading: leading, actions: actions),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    description,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          height: 1.4,
                        ),
                  ),
                  const SizedBox(height: 28),
                  child,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SubmissionButton extends StatelessWidget {
  const SubmissionButton({
    required this.label,
    required this.isSubmitting,
    required this.onPressed,
    super.key,
  });

  final String label;
  final bool isSubmitting;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      button: true,
      child: FilledButton(
        onPressed: isSubmitting ? null : onPressed,
        child: isSubmitting
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(label),
      ),
    );
  }
}

class FormMessageBanner extends StatelessWidget {
  const FormMessageBanner({required this.message, super.key});

  final String? message;

  @override
  Widget build(BuildContext context) {
    if (message == null) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.secondaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          message!,
          style: TextStyle(color: colors.onSecondaryContainer),
        ),
      ),
    );
  }
}

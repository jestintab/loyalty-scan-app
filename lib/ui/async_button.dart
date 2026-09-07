import 'package:flutter/material.dart';

/// A filled button that shows a spinner in place of its label while [busy], and
/// refuses taps meanwhile. Every action in this app is a network call that must
/// not be fired twice.
class AsyncButton extends StatelessWidget {
  const AsyncButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.tonal = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final bool tonal;

  @override
  Widget build(BuildContext context) {
    final child = busy
        ? const SizedBox(
            height: 18,
            width: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Text(label);
    final onTap = busy ? null : onPressed;

    return tonal
        ? FilledButton.tonal(onPressed: onTap, child: child)
        : FilledButton(onPressed: onTap, child: child);
  }
}

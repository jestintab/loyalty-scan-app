import 'package:flutter/material.dart';

import 'theme.dart';

/// The Qwallet lockup, with the one adjustment dark mode needs.
///
/// The artwork is a gold mark beside a near-black wordmark, drawn for cream
/// paper. On a dark ground the wordmark disappears, so the whole lockup is
/// tinted to the surface's ink instead — a monochrome treatment, which is what
/// a brand does on dark rather than showing half a logo.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.height = 52});

  final double height;

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(
      'assets/qwallet-logo.png',
      height: height,
      alignment: Alignment.centerLeft,
      excludeFromSemantics: true,
    );

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Semantics(
      label: 'Qwallet',
      child: isDark
          ? ColorFiltered(
              colorFilter: const ColorFilter.mode(
                QwalletColors.nightInk,
                BlendMode.srcATop,
              ),
              child: image,
            )
          : image,
    );
  }
}

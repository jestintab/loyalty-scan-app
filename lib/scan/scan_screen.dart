import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../auth/auth_notifier.dart';
import '../ui/message_view.dart';
import 'card_result_view.dart';
import 'scan_notifier.dart';

class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  final _manualId = TextEditingController();

  @override
  void dispose() {
    _manualId.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(scanProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan'),
        actions: [
          IconButton(
            tooltip: 'Scan log',
            icon: const Icon(Icons.receipt_long),
            onPressed: () => context.push('/logs'),
          ),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authProvider.notifier).signOut(),
          ),
        ],
      ),
      body: switch (state) {
        ScanIdle() => _camera(),
        ScanLoading() => const Center(child: CircularProgressIndicator()),
        ScanFound() => CardResultView(card: state.card),
        ScanFailed() => MessageView(
            icon: Icons.error_outline,
            title: state.message,
            onRetry: () => ref.read(scanProvider.notifier).reset(),
          ),
      },
      bottomNavigationBar: state is ScanIdle
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.tonal(
                  onPressed: () => ref.read(scanProvider.notifier).reset(),
                  child: const Text('Scan next'),
                ),
              ),
            ),
    );
  }

  Widget _camera() {
    return Column(
      children: [
        Expanded(
          child: MobileScanner(
            onDetect: (capture) {
              final raw = capture.barcodes.firstOrNull?.rawValue;
              // The notifier's own guard stops repeats; this only skips frames
              // that decoded to nothing at all.
              if (raw != null) ref.read(scanProvider.notifier).lookUp(raw);
            },
            onDetectError: (error, _) {
              // A decode failure on one frame is not worth telling anyone
              // about; the next frame will try again.
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _manualId,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Or type the card ID',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (v) => ref.read(scanProvider.notifier).lookUp(v),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () =>
                    ref.read(scanProvider.notifier).lookUp(_manualId.text),
                child: const Text('Look up'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

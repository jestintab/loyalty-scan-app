import 'package:flutter/material.dart';

import '../api/models/scan_log_entry.dart';
import 'scan_log_format.dart';

/// One line of the scan log, written the same way wherever it appears — the
/// full log and the home screen's last-few list are the same rows at different
/// lengths, and they should not drift apart.
class ScanLogTile extends StatelessWidget {
  const ScanLogTile({super.key, required this.entry});

  final ScanLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final redeemed = entry.type == ScanLogType.redemption;
    return ListTile(
      leading: Icon(redeemed ? Icons.redeem : Icons.check_circle_outline),
      title: Text(entry.customerName ?? 'Customer'),
      subtitle: Text(
        '${redeemed ? 'Reward redeemed' : '+${entry.stampsAdded} stamps'}'
        ' · ${entry.stampsBefore} → ${entry.stampsAfter}'
        '${entry.staffName != null ? ' · ${entry.staffName}' : ''}',
      ),
      trailing: Text(formatTime(entry.loggedAt.toLocal())),
    );
  }
}

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
    final redeemed =
        entry.type == ScanLogType.redemption ||
        entry.type == ScanLogType.pointsRedeem;
    final checkedIn = entry.type == ScanLogType.checkIn;
    final staff = entry.staffName != null ? ' · ${entry.staffName}' : '';
    return ListTile(
      leading: Icon(
        redeemed
            ? Icons.redeem
            : checkedIn
            ? Icons.login
            : entry.isPoints
            ? Icons.stars_outlined
            : Icons.check_circle_outline,
      ),
      title: Text(entry.customerName ?? 'Customer'),
      subtitle: Text(
        entry.isPoints
            ? '${describePoints(entry)} · ${entry.stampsBefore} → ${entry.stampsAfter} pts$staff'
            : checkedIn
            ? 'Checked in${entry.staffName != null ? ' · ${entry.staffName}' : ''}'
            : '${redeemed ? 'Reward redeemed' : '+${entry.stampsAdded} stamps'}'
                  ' · ${entry.stampsBefore} → ${entry.stampsAfter}'
                  '${entry.staffName != null ? ' · ${entry.staffName}' : ''}',
      ),
      trailing: Text(formatTime(entry.loggedAt.toLocal())),
    );
  }
}

/// The wording the dashboard uses for points rows (lib/pointsProgram.ts
/// describePointsLog), so the two activity logs read alike.
String describePoints(ScanLogEntry e) {
  String signed(int n) =>
      '${n > 0
          ? '+'
          : n < 0
          ? '−'
          : ''}${n.abs()} point${n.abs() == 1 ? '' : 's'}';
  switch (e.type) {
    case ScanLogType.pointsEarn:
      final what =
          e.itemName ??
          (e.billAmount != null ? 'Purchase QAR ${e.billAmount}' : 'Purchase');
      return '$what · ${signed(e.stampsAdded)}${e.rewardName != null ? ' · ${e.rewardName} ready' : ''}';
    case ScanLogType.pointsRedeem:
      return 'Redeemed ${e.rewardName ?? 'a reward'}${e.stampsAdded != 0 ? ' · ${signed(e.stampsAdded)}' : ''}';
    case ScanLogType.pointsAdjust:
      return 'Adjusted ${signed(e.stampsAdded)}${e.rewardName != null ? ' · ${e.rewardName} ready' : ''}';
    default:
      return '';
  }
}

/// How a scan-log timestamp is written, in one place.
///
/// The log screen and the home summary both have to agree on where a day
/// starts, or the header can say "Today" over rows the tally on the previous
/// screen didn't count. Dates are compared in local time throughout, which is
/// what "today" means to the person holding the phone — the API sends UTC.
library;

bool isSameLocalDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String formatDay(DateTime d) {
  final now = DateTime.now();
  if (isSameLocalDay(d, now)) return 'Today';
  if (isSameLocalDay(d, now.subtract(const Duration(days: 1)))) {
    return 'Yesterday';
  }
  return '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';
}

String formatTime(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

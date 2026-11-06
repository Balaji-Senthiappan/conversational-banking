const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _monthsLong = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];
const _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

/// Indian digit grouping: 185000 -> ₹1,85,000.
String inr(num value) {
  final negative = value < 0;
  final digits = value.abs().round().toString();
  String grouped;
  if (digits.length <= 3) {
    grouped = digits;
  } else {
    final last3 = digits.substring(digits.length - 3);
    var rest = digits.substring(0, digits.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    grouped = '${parts.join(',')},$last3';
  }
  return '${negative ? '-' : ''}₹$grouped';
}

String ordinal(int n) {
  if (n >= 11 && n <= 13) return '${n}th';
  return switch (n % 10) { 1 => '${n}st', 2 => '${n}nd', 3 => '${n}rd', _ => '${n}th' };
}

String shortDate(DateTime d) => '${d.day} ${_months[d.month - 1]}';

String longDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

String monthName(DateTime d) => _monthsLong[d.month - 1];

String weekdayName(DateTime d) => _weekdays[d.weekday - 1];

String pct(double rate) => '${rate.toStringAsFixed(2)}%';

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

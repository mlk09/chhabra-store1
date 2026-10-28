import '../data/models/shop.dart';

/// India has no daylight saving, so shop time is always UTC+5:30. The
/// returned DateTime holds the shop's wall-clock time in UTC fields.
DateTime shopClock(DateTime now) => now.toUtc().add(const Duration(hours: 5, minutes: 30));

DateTime _day(DateTime d) => DateTime.utc(d.year, d.month, d.day);

final _slotRe = RegExp(r'^(\d{2}):(\d{2})-(\d{2}):(\d{2})$');

/// Same rule as the server's slot_ok(): a listed slot, today..+6 days, and a
/// slot today must start at least [Shop.slotLeadMinutes] from now.
bool slotOk(Shop shop, DateTime date, String slot, DateTime now) {
  final m = _slotRe.firstMatch(slot);
  if (m == null || !shop.timeSlots.contains(slot)) return false;
  final local = shopClock(now);
  final today = _day(local);
  final day = _day(date);
  if (day.isBefore(today) || day.isAfter(today.add(const Duration(days: 6)))) return false;
  final start = day.add(Duration(hours: int.parse(m[1]!), minutes: int.parse(m[2]!)));
  return !(day == today && start.difference(local).inMinutes < shop.slotLeadMinutes);
}

class SlotChoice {
  const SlotChoice(this.date, this.slot);
  final DateTime date;
  final String slot;

  @override
  bool operator ==(Object other) => other is SlotChoice && other.date == date && other.slot == slot;
  @override
  int get hashCode => Object.hash(date, slot);
}

/// Bookable slots for the next [days] days, earliest first.
List<SlotChoice> upcomingSlots(Shop shop, DateTime now, {int days = 3}) {
  final today = _day(shopClock(now));
  final slots = [...shop.timeSlots]..sort();
  return [
    for (var d = 0; d < days; d++)
      for (final s in slots)
        if (slotOk(shop, today.add(Duration(days: d)), s, now)) SlotChoice(today.add(Duration(days: d)), s),
  ];
}

/// "09:00-12:00" → "9 AM – 12 PM"
String prettySlot(String slot) {
  final m = _slotRe.firstMatch(slot);
  if (m == null) return slot;
  String t(String h, String min) {
    final hour = int.parse(h);
    final h12 = hour % 12 == 0 ? 12 : hour % 12;
    final suffix = hour < 12 ? 'AM' : 'PM';
    return min == '00' ? '$h12 $suffix' : '$h12:$min $suffix';
  }

  return '${t(m[1]!, m[2]!)} – ${t(m[3]!, m[4]!)}';
}

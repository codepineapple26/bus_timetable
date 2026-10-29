enum TripSort {
  travelDateNewest,
  departureEarliest,
  fromPlace,
  toPlace,
}

Map<String, dynamic> _scheduleOf(Map<String, dynamic> item) {
  final expand = item['expand'];
  if (expand is Map && expand['schedule'] is Map) {
    return Map<String, dynamic>.from(expand['schedule'] as Map);
  }

  if (item['schedule'] is Map) {
    return Map<String, dynamic>.from(item['schedule'] as Map);
  }

  return item;
}

String _text(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value != null && value.toString().trim().isNotEmpty) {
      return value.toString().trim();
    }
  }
  return '';
}

DateTime? _travelDate(Map<String, dynamic> item) {
  final value = _text(item, ['travel_date', 'visit_date', 'date','visit_time']);
  return DateTime.tryParse(value);
}

int? _departureMinutes(Map<String, dynamic> item) {
  final schedule = _scheduleOf(item);
  final value = _text(schedule, ['departure', 'departure_time', 'departureTime']);

  final match = RegExp(
    r'^\s*(\d{1,2}):(\d{2})\s*([AP]M)?\s*$',
    caseSensitive: false,
  ).firstMatch(value);

  if (match == null) return null;

  var hour = int.parse(match.group(1)!);
  final minute = int.parse(match.group(2)!);
  final amPm = match.group(3)?.toUpperCase();

  if (amPm == 'PM' && hour < 12) hour += 12;
  if (amPm == 'AM' && hour == 12) hour = 0;

  return hour * 60 + minute;
}

List<Map<String, dynamic>> sortTrips(
  List<Map<String, dynamic>> trips,
  TripSort sort,
) {
  final result = [...trips];

  result.sort((a, b) {
    final scheduleA = _scheduleOf(a);
    final scheduleB = _scheduleOf(b);

    switch (sort) {
      case TripSort.travelDateNewest:
        final dateA = _travelDate(a);
        final dateB = _travelDate(b);
        if (dateA == null) return dateB == null ? 0 : 1;
        if (dateB == null) return -1;
        return dateB.compareTo(dateA); // Newest first

      case TripSort.departureEarliest:
        final timeA = _departureMinutes(a);
        final timeB = _departureMinutes(b);
        if (timeA == null) return timeB == null ? 0 : 1;
        if (timeB == null) return -1;
        return timeA.compareTo(timeB);

      case TripSort.from:
        return _text(scheduleA, ['from_place', 'fromPlace'])
            .toLowerCase()
            .compareTo(_text(scheduleB, ['from_place', 'fromPlace']).toLowerCase());

      case TripSort.to:
        return _text(scheduleA, ['to_place', 'toPlace'])
            .toLowerCase()
            .compareTo(_text(scheduleB, ['to_place', 'toPlace']).toLowerCase());
    }
  });

  return result;
}

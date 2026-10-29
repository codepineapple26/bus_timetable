Map<String, dynamic> _scheduleOf(Map<String, dynamic> item) {
  final expand = item['expand'];
  if (expand is Map && expand['schedule'] is Map) {
    return Map<String, dynamic>.from(expand['schedule'] as Map);
  }

  final schedule = item['schedule'];
  if (schedule is Map) {
    return Map<String, dynamic>.from(schedule);
  }

  return item;
}

List<Map<String, dynamic>> filterTrips(
  List<Map<String, dynamic>> trips,
  String query,
) {
  final term = query.trim().toLowerCase();
  if (term.isEmpty) return trips;

  return trips.where((item) {
    final schedule = _scheduleOf(item);
    final searchableText = [
      item['travel_date'],
      item['visit_date'],
      schedule['from_place'],
      schedule['to_place'],
      schedule['via_places'],
      schedule['route'],
      schedule['service'],
      schedule['departure'],
    ].where((value) => value != null).join(' ').toLowerCase();

    return searchableText.contains(term);
  }).toList();
}

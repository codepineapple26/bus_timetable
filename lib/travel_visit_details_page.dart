import 'package:flutter/material.dart';

class TravelVisitDetailsPage extends StatelessWidget {
  const TravelVisitDetailsPage({
    super.key,
    required this.visit,
    this.schedule,
  });

  /// Accepts the map currently passed by your history screen:
  /// {'data': visit.data, 'id': visit.id}
  final Map<String, dynamic> visit;

  /// Pass the full bus_trips record here, not just its ID.
  final Map<String, dynamic>? schedule;

  Map<String, dynamic> get _visitData {
    final value = visit['data'];
    if (value is Map) return Map<String, dynamic>.from(value);
    return visit;
  }

  String _firstValue(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value == null) continue;

      final text = value.toString().trim();
      if (text.isNotEmpty && !_looksLikeId(text)) return text;
    }
    return '';
  }

  bool _looksLikeId(String value) =>
      RegExp(r'^[a-zA-Z0-9]{15}$').hasMatch(value);

  DateTime? _visitDateTime() {
    final value = _visitData['visit_time'];
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  String _formatRoute(Map<String, dynamic> trip) {
    final departure = _firstValue(
      trip,
      ['departure_time', 'departure', 'time'],
    );
    final from = _firstValue(
      trip,
      ['from_place', 'from', 'origin'],
    );
    final to = _firstValue(
      trip,
      ['to_place', 'to', 'destination'],
    );
    final type = _firstValue(
      trip,
      ['type_raw', 'type', 'bus_type'],
    );
    final via = _firstValue(
      trip,
      ['via_places', 'via', 'via_place'],
    );

    final route = [
      if (departure.isNotEmpty) departure,
      if (from.isNotEmpty && to.isNotEmpty) '$from → $to',
      if (type.isNotEmpty) type,
      if (via.isNotEmpty) 'Via $via',
    ];

    return route.isEmpty ? 'Route details unavailable' : route.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final data = _visitData;
    final trip = schedule ?? _expandedSchedule(data);
    final visitDate = _visitDateTime()?.toLocal();

    final formattedDate = visitDate == null
        ? 'Date unavailable'
        : MaterialLocalizations.of(context).formatMediumDate(visitDate);

    final formattedTime = visitDate == null
        ? ''
        : MaterialLocalizations.of(context).formatTimeOfDay(
            TimeOfDay.fromDateTime(visitDate),
          );

    return Scaffold(
      appBar: AppBar(title: const Text('Travel details')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _detail(
            'Route',
            _formatRoute(trip),
          ),
          _detail(
            'Date travelled',
            formattedTime.isEmpty
                ? formattedDate
                : '$formattedDate · $formattedTime',
          ),
          _detail(
            'Purpose',
            data['purpose']?.toString().trim().isNotEmpty == true
                ? data['purpose'].toString()
                : '—',
          ),
          _detail(
            'Notes',
            data['notes']?.toString().trim().isNotEmpty == true
                ? data['notes'].toString()
                : '—',
          ),
        ],
      ),
    );
  }

  Map<String, dynamic> _expandedSchedule(Map<String, dynamic> data) {
    final expand = data['expand'];
    if (expand is Map) {
      final expandedSchedule = expand['schedule'];
      if (expandedSchedule is Map) {
        return Map<String, dynamic>.from(expandedSchedule);
      }
    }

    final embeddedSchedule = data['schedule'];
    if (embeddedSchedule is Map) {
      return Map<String, dynamic>.from(embeddedSchedule);
    }

    return {};
  }

  Widget _detail(String title, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(color: Colors.black54)),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';
import 'utils/trip_search.dart';

import 'travel_visit_details_page.dart'; // Adjust this path if needed.

class ViewTravelHistoryPage extends StatefulWidget {
  const ViewTravelHistoryPage({
    super.key,
    required this.pb,
  });

  final PocketBase pb;

  @override
  State<ViewTravelHistoryPage> createState() =>
      _ViewTravelHistoryPageState();
}

class _ViewTravelHistoryPageState extends State<ViewTravelHistoryPage> {
  final List<RecordModel> _visits = [];

  int _nextPage = 1;
  bool _hasMore = true;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadVisits(reset: true);
  }

  Future<void> _loadVisits({bool reset = false}) async {
    if (_loading || (!reset && !_hasMore)) return;

    final page = reset ? 1 : _nextPage;

    setState(() {
      _loading = true;
      _error = null;

      if (reset) {
        _visits.clear();
        _nextPage = 1;
        _hasMore = true;
      }
    });

    try {
      final result = await widget.pb.collection('bus_visits').getList(
            page: page,
            perPage: 50,
            filter: 'schedule != ""',
            sort: '-visit_time',
            expand: 'schedule',
          );

      if (!mounted) return;

      setState(() {
        _visits.addAll(result.items);
        _nextPage = page + 1;
        _hasMore = page < result.totalPages;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Map<String, dynamic> _scheduleData(RecordModel visit) {
    final schedules = visit.expand['schedule'];

    if (schedules == null || schedules.isEmpty) {
      return {};
    }

    return schedules.first.data;
  }

  String _field(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key]?.toString().trim();

      if (value != null &&
          value.isNotEmpty &&
          !RegExp(r'^[a-zA-Z0-9]{15}$').hasMatch(value)) {
        return value;
      }
    }

    return '';
  }

  String _formatDeparture(BuildContext context, String rawDeparture) {
    final parsed = DateTime.tryParse(rawDeparture);

    if (parsed == null) {
      return rawDeparture;
    }

    return MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(parsed.toLocal()),
    );
  }

  String _formatTravelDate(BuildContext context, RecordModel visit) {
    final rawDate = visit.data['visit_time']?.toString();

    if (rawDate == null || rawDate.isEmpty) {
      return 'Date travelled unavailable';
    }

    final date = DateTime.tryParse(rawDate)?.toLocal();

    if (date == null) {
      return 'Date travelled unavailable';
    }

    final localizations = MaterialLocalizations.of(context);
    final dateText = localizations.formatMediumDate(date);
    final timeText = localizations.formatTimeOfDay(
      TimeOfDay.fromDateTime(date),
    );

    return '$dateText · $timeText';
  }

  void _openVisitDetails(BuildContext context, RecordModel visit) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TravelVisitDetailsPage(
          visit: {
            'data': visit.data,
            'id': visit.id,
          },
        ),
      ),
    );
  }

  Widget _buildVisitCard(BuildContext context, RecordModel visit) {
    final schedule = _scheduleData(visit);

    final from = _field(
      schedule,
      ['from_city', 'origin', 'source', 'from', 'from_place'],
    );

    final to = _field(
      schedule,
      ['to_city', 'destination', 'to', 'to_place'],
    );

    final route = _field(schedule, ['route_name', 'name']);

    final rawDeparture = _field(
      schedule,
      ['departure_time', 'depart_time', 'departure'],
    );

    final service = _field(
      schedule,
      ['service_type', 'bus_type', 'type_raw', 'type', 'bus_name'],
    );

    final via = _field(
      schedule,
      ['via_places', 'via_place', 'via', 'stops'],
    );

    final title = from.isNotEmpty && to.isNotEmpty
        ? '$from → $to'
        : route.isNotEmpty
            ? route
            : 'Bus trip';

    final departure = _formatDeparture(context, rawDeparture);

    final serviceText = [
      if (service.isNotEmpty) service,
      if (via.isNotEmpty) 'Via: $via',
    ].join(' · ');

    final travelDate = _formatTravelDate(context, visit);
    final notes = visit.data['notes']?.toString().trim() ?? '';

    return Card(
      color: const Color(0xFFC2B0AC),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openVisitDetails(context, visit),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 58,
                child: Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: Text(
                    departure,
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (serviceText.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        serviceText,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(
                          Icons.history,
                          size: 16,
                          color: Colors.teal,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            'Travelled: $travelDate',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                    if (notes.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        notes,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadMoreButton() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: _loading
            ? const CircularProgressIndicator()
            : TextButton(
                onPressed: _loadVisits,
                child: const Text('Load more'),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Travel history'),
        actions: [
          IconButton(
            onPressed: () => _loadVisits(reset: true),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadVisits(reset: true),
        child: _error != null && _visits.isEmpty
            ? ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Could not load travel history: $_error',
                    ),
                  ),
                ],
              )
            : _visits.isEmpty && !_loading
                ? ListView(
                    children: const [
                      Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('No travel history yet.'),
                      ),
                    ],
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _visits.length + (_hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _visits.length) {
                        return _buildLoadMoreButton();
                      }

                      return _buildVisitCard(context, _visits[index]);
                    },
                  ),
      ),
    );
  }
}

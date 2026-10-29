import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';

import 'travel_visit_details_page.dart'; // Adjust path if needed.
import 'utils/trip_search.dart';
import 'utils/trip_sorting.dart';

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
  final TextEditingController _searchController = TextEditingController();

  int _nextPage = 1;
  bool _hasMore = true;
  bool _loading = false;
  String? _error;

  String _searchText = '';
  TripSort _sort = TripSort.travelDateNewest;

  @override
  void initState() {
    super.initState();
    _loadVisits(reset: true);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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

  RecordModel? _scheduleRecord(RecordModel visit) {
    final schedules = visit.expand['schedule'];
    return schedules == null || schedules.isEmpty ? null : schedules.first;
  }

  Map<String, dynamic> _scheduleData(RecordModel visit) {
    return _scheduleRecord(visit)?.data ?? <String, dynamic>{};
  }

  String _field(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final raw = data[key];
      if (raw == null) continue;

      final value = raw.toString().trim();
      if (value.isEmpty || RegExp(r'^[a-zA-Z0-9]{15}$').hasMatch(value)) {
        continue;
      }
      return value;
    }

    return '';
  }

  /// Supplies common aliases so the shared search and sorting utilities can
  /// handle schedules that use different PocketBase field names.
  Map<String, dynamic> _tripForFiltering(RecordModel visit) {
    final schedule = _scheduleData(visit);
    final visitTime = visit.data['visit_time']?.toString() ?? '';

    final from = _field(
      schedule,
      ['from_city', 'origin', 'source', 'from', 'from_place'],
    );
    final to = _field(
      schedule,
      ['to_city', 'destination', 'to', 'to_place'],
    );
    final route = _field(schedule, ['route_name', 'name']);
    final departure = _field(
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

    return {
      ...schedule,
      'from': from,
      'from_place': from,
      'origin': from,
      'to': to,
      'to_place': to,
      'destination': to,
      'route': route,
      'route_name': route,
      'departure': departure,
      'departure_time': departure,
      'service': service,
      'service_type': service,
      'via': via,
      'via_places': via,
      'travel_date': visitTime,
      'visit_time': visitTime,
      'date': visitTime,
    };
  }

  String _formatDeparture(BuildContext context, String rawDeparture) {
    final parsed = DateTime.tryParse(rawDeparture);
    if (parsed == null) return rawDeparture;

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
    if (date == null) return 'Date travelled unavailable';

    final localizations = MaterialLocalizations.of(context);
    final dateText = localizations.formatMediumDate(date);
    final timeText = localizations.formatTimeOfDay(TimeOfDay.fromDateTime(date));

    return '$dateText · $timeText';
  }

  String _tripTitle(Map<String, dynamic> schedule) {
    final from = _field(
      schedule,
      ['from_city', 'origin', 'source', 'from', 'from_place'],
    );
    final to = _field(
      schedule,
      ['to_city', 'destination', 'to', 'to_place'],
    );
    final route = _field(schedule, ['route_name', 'name']);

    if (from.isNotEmpty && to.isNotEmpty) return '$from → $to';
    if (route.isNotEmpty) return route;
    return 'Bus trip';
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
    final trip = _tripForFiltering(visit);

    final departure = _formatDeparture(
      context,
      trip['departure']?.toString() ?? '',
    );

    final service = trip['service']?.toString() ?? '';
    final via = trip['via']?.toString() ?? '';
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
                      _tripTitle(schedule),
                      style: const TextStyle(fontWeight: FontWeight.w600),
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
                      Text(notes, style: const TextStyle(fontSize: 12)),
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

  String _sortLabel(TripSort sort) {
    switch (sort) {
      case TripSort.travelDateNewest:
        return 'Travel date (newest)';
      case TripSort.departureEarliest:
        return 'Departure (earliest)';
      case TripSort.fromPlace:
        return 'From place';
      case TripSort.toPlace:
        return 'To place';
    }
  }

  Widget _buildSearchAndSort() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search travel history',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchText.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchText = '');
                      },
                      icon: const Icon(Icons.clear),
                    ),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (value) => setState(() => _searchText = value),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<TripSort>(
            value: _sort,
            decoration: const InputDecoration(
              labelText: 'Sort by',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: TripSort.values
                .map(
                  (sort) => DropdownMenuItem(
                    value: sort,
                    child: Text(_sortLabel(sort)),
                  ),
                )
                .toList(),
            onChanged: (sort) {
              if (sort != null) setState(() => _sort = sort);
            },
          ),
        ],
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
                onPressed: () => _loadVisits(),
                child: const Text('Load more'),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredVisits = filterTrips(
      _visits.map(_tripForFiltering).toList(),
      _searchText,
    );
    final sortedTrips = sortTrips(filteredVisits, _sort);

    // Map each sorted trip back to its visit using its visit_time and schedule
    // fields. The original visit list is retained for opening visit details.
    final sortedVisits = <RecordModel>[];
    final usedVisitIds = <String>{};

    for (final trip in sortedTrips) {
      for (final visit in _visits) {
        if (usedVisitIds.contains(visit.id)) continue;

        final visitTrip = _tripForFiltering(visit);
        if (visitTrip['visit_time'] == trip['visit_time'] &&
            visitTrip['from'] == trip['from'] &&
            visitTrip['to'] == trip['to'] &&
            visitTrip['departure'] == trip['departure']) {
          sortedVisits.add(visit);
          usedVisitIds.add(visit.id);
          break;
        }
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Travel history'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => _loadVisits(reset: true),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSearchAndSort(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Text(
                'Could not load travel history: $_error',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _loadVisits(reset: true),
              child: sortedVisits.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _visits.isEmpty
                                ? (_loading
                                    ? 'Loading travel history…'
                                    : 'No travel history yet.')
                                : 'No trips match your search.',
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: sortedVisits.length + (_hasMore ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == sortedVisits.length) {
                          return _buildLoadMoreButton();
                        }
                        return _buildVisitCard(context, sortedVisits[index]);
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

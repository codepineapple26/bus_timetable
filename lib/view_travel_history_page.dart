import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';

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
 bool _isHiddenField(String key) {
    final normalized = key.toLowerCase().replaceAll(RegExp(r'[_\s-]'), '');
    return {
      'id',
      'created',
      'updated',
      'collectionid',
      'collectionname',
      'serialno',
    }.contains(normalized) ||
        normalized.endsWith('id');
  }
  
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

  
  String _scheduleDescription(RecordModel visit) {
  final expandedSchedules = visit.expand['schedule'];

  if (expandedSchedules != null && expandedSchedules.isNotEmpty) {
    final data = expandedSchedules.first.data;

    final entries = data.entries.where((entry) {
      return !_isHiddenField(entry.key) &&
          entry.value != null &&
          entry.value.toString().isNotEmpty;
    }).take(5);

    final description = entries
        .map((entry) => '${entry.key}: ${entry.value}')
        .join(' • ');

    if (description.isNotEmpty) return description;
  }

  return 'Schedule';
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
                    child: Text('Could not load travel history: $_error'),
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
                    itemCount: _visits.length + (_hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _visits.length) {
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

                      final visit = _visits[index];
                      final routeLabel = _scheduleDescription(visit);
                      final rawDate =
                          visit.data['visit_time']?.toString();
                      final date = rawDate == null
                          ? null
                          : DateTime.tryParse(rawDate)?.toLocal();
                      final notes =
                          visit.data['notes']?.toString() ?? '';

                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: ListTile(
                          title: Text(routeLabel),
                          subtitle: Text(
                            [
                              if (date != null)
                                MaterialLocalizations.of(context)
                                    .formatMediumDate(date),
                              if (notes.isNotEmpty) notes,
                            ].join('\n'),
                          ),
                          isThreeLine: notes.isNotEmpty,
                          onTap: () {
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
                          },
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}

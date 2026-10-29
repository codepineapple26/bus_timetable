import 'package:flutter/material.dart';

import 'utils/trip_search.dart';
import 'utils/trip_sorting.dart';

typedef FavoriteTripBuilder = Widget Function(
  BuildContext context,
  Map<String, dynamic> trip, {
  required bool isFavorite,
  required VoidCallback onFavoriteTap,
  required VoidCallback onMarkTravelled,
});

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({
    super.key,
    required this.loadFavoriteIds,
    required this.loadTrips,
    required this.tripBuilder,
    required this.onRemoveFavorite,
    required this.onMarkTravelled,
  });

  final Future<Set<String>> Function() loadFavoriteIds;
  final Future<List<Map<String, dynamic>>> Function() loadTrips;
  final FavoriteTripBuilder tripBuilder;

  /// Persist removal from favorites storage.
  final Future<void> Function(Map<String, dynamic> trip) onRemoveFavorite;

  /// Open the shared travel-details form and report whether it was saved.
  final Future<bool> Function(Map<String, dynamic> trip) onMarkTravelled;

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  late Future<List<Map<String, dynamic>>> _favoritesFuture;

  final TextEditingController _searchController = TextEditingController();
  String _searchText = '';
  TripSort _sort = TripSort.departureEarliest;

  @override
  void initState() {
    super.initState();
    _favoritesFuture = _loadFavorites();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _loadFavorites() async {
    final favoriteIds = await widget.loadFavoriteIds();
    final trips = await widget.loadTrips();

    return trips.where((trip) {
      final id = (trip['id'] ?? trip['schedule_id'])?.toString();
      return id != null && favoriteIds.contains(id);
    }).toList();
  }

  Future<void> _refresh() async {
    final future = _loadFavorites();
    setState(() => _favoritesFuture = future);
    await future;
  }

  Future<void> _removeFavorite(Map<String, dynamic> trip) async {
    try {
      await widget.onRemoveFavorite(trip);
      await _refresh();
      _showMessage('Removed from favorites.');
    } catch (error) {
      _showMessage('Could not remove favorite: $error');
    }
  }

  Future<void> _markTravelled(Map<String, dynamic> trip) async {
    try {
      final saved = await widget.onMarkTravelled(trip);
      if (saved) {
        _showMessage('Travel logged. You can find it in Travel History.');
      }
    } catch (error) {
      _showMessage('Could not log travel: $error');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
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
              hintText: 'Search favorites',
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Favorites')),
      body: Column(
        children: [
          _buildSearchAndSort(),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _favoritesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text('Could not load favorites: ${snapshot.error}'),
                  );
                }

                final trips = snapshot.data ?? [];

                if (trips.isEmpty) {
                  return const Center(child: Text('No favorite trips yet.'));
                }

                final filteredTrips = filterTrips(trips, _searchText);
                final visibleTrips = sortTrips(filteredTrips, _sort);

                if (visibleTrips.isEmpty) {
                  return const Center(
                    child: Text('No trips match your search.'),
                  );
                }

                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: visibleTrips.length,
                    itemBuilder: (context, index) {
                      final trip = visibleTrips[index];
                      return widget.tripBuilder(
                        context,
                        trip,
                        isFavorite: true,
                        onFavoriteTap: () => _removeFavorite(trip),
                        onMarkTravelled: () => _markTravelled(trip),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

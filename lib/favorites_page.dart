import 'package:flutter/material.dart';
import 'utils/trip_search.dart';

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

  /// Persist the removal from your favorites storage.
  final Future<void> Function(Map<String, dynamic> trip) onRemoveFavorite;

  /// Create the bus_visits record in your PocketBase logic.
final Future<bool> Function(Map<String, dynamic> trip) onMarkTravelled;



  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  late Future<List<Map<String, dynamic>>> _favoritesFuture;

  @override
  void initState() {
    super.initState();
    _favoritesFuture = _loadFavorites();
  }

  Future<List<Map<String, dynamic>>> _loadFavorites() async {
    final favoriteIds = await widget.loadFavoriteIds();
    final trips = await widget.loadTrips();

    return trips
        .where((trip) => favoriteIds.contains(trip['id']?.toString()))
        .toList();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Favorites')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
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
          final filteredTrips = filterTrips(trips, _tripSearch);
          final visibleTrips = sortTrips(filteredTrips, _tripSort);

          if (trips.isEmpty) {
            return const Center(child: Text('No favorite trips yet.'));
          }

          if (visibleTrips.isEmpty) {
  return const Center(child: Text('No trips match your search.'));
}

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: trips.length,
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
    );
  }
}

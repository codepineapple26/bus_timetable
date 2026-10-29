import 'package:flutter/material.dart';

typedef FavoriteTripBuilder = Widget Function(
  BuildContext context,
  Map<String, dynamic> trip, {
  required bool isFavorite,
});

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({
    super.key,
    required this.loadFavoriteIds,
    required this.loadTrips,
    required this.tripBuilder,
  });

  final Future<Set<String>> Function() loadFavoriteIds;
  final Future<List<Map<String, dynamic>>> Function() loadTrips;
  final FavoriteTripBuilder tripBuilder;

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

          if (trips.isEmpty) {
            return const Center(child: Text('No favorite trips yet.'));
          }

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: trips.length,
              itemBuilder: (context, index) {
                return widget.tripBuilder(
                  context,
                  trips[index],
                  isFavorite: true,
                );
              },
            ),
          );
        },
      ),
    );
  }
}

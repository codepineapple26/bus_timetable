import 'package:flutter/material.dart';

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({
    super.key,
    required this.loadFavoriteIds,
    required this.loadTrips,
  });

  final Future<Set<String>> Function() loadFavoriteIds;
  final Future<List<Map<String, dynamic>>> Function() loadTrips;

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
    final ids = await widget.loadFavoriteIds();
    final trips = await widget.loadTrips();

    return trips
        .where((trip) => ids.contains(trip['id']?.toString()))
        .toList();
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
            return Center(child: Text('Could not load favorites: ${snapshot.error}'));
          }

          final trips = snapshot.data ?? [];
          if (trips.isEmpty) {
            return const Center(child: Text('No favorite trips yet.'));
          }

          return ListView.builder(
            itemCount: trips.length,
            itemBuilder: (context, index) {
              final trip = trips[index];
              final title = trip['route_name'] ??
                  trip['name'] ??
                  trip['id'] ??
                  'Favorite trip';

              return ListTile(title: Text(title.toString()));
            },
          );
        },
      ),
    );
  }
}

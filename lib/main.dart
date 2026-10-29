import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';
import 'favorites_page.dart';


// Change this path to the location of your travel-record form.
import 'add_visit_page.dart';
import 'view_travel_history_page.dart';
import 'travel_visit_details_page.dart';

const pbUrl = 'http://10.163.138.218:8090';
final pb = PocketBase(pbUrl);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BusTimetableApp());
}

class BusTimetableApp extends StatelessWidget {
  const BusTimetableApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bus Timetable',
      theme: ThemeData(
        colorSchemeSeed: Colors.teal,
        useMaterial3: true,
      ),
      home: const TimetablePage(),
    );
  }
}


class LocalCache {
  late final Database db;

  Future<void> init() async {
    final directory = await getDatabasesPath();

    db = await openDatabase(
      p.join(directory, 'bus_timetable.db'),
      version: 3,
      onCreate: (database, version) async {
        await database.execute('''
          CREATE TABLE IF NOT EXISTS cached_records (
            collection_name TEXT NOT NULL,
            record_id TEXT NOT NULL,
            json TEXT NOT NULL,
            PRIMARY KEY (collection_name, record_id)
          )
        ''');

        await _createFavoritesTable(database);
        await _createTravelOutboxTable(database);
      },
      onUpgrade: (database, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createFavoritesTable(database);
        }
        if (oldVersion < 3) {
          await _createTravelOutboxTable(database);
        }
      },
    );
  }

  Future<void> _createFavoritesTable(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS bus_favorites (
        schedule_id TEXT PRIMARY KEY,
        created_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> _createTravelOutboxTable(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS bus_visits_outbox (
        local_id TEXT PRIMARY KEY,
        schedule_id TEXT,
        visit_time TEXT NOT NULL,
        purpose TEXT NOT NULL,
        notes TEXT,
        photo_path TEXT,
        attachments_json TEXT,
        sync_status TEXT NOT NULL DEFAULT 'pending',
        pocketbase_id TEXT
      )
    ''');
  }

  // Favorites

  Future<Set<String>> getFavoriteScheduleIds() async {
  final rows = await db.query('bus_favorites');
  return rows.map((row) => row['schedule_id'] as String).toSet();
}

  Future<void> addFavorite(String scheduleId) async {
    await db.insert(
      'bus_favorites',
      {
        'schedule_id': scheduleId,
        'created_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> removeFavorite(String scheduleId) async {
    await db.delete(
      'bus_favorites',
      where: 'schedule_id = ?',
      whereArgs: [scheduleId],
    );
  }

  // Cached PocketBase collections

  Future<List<Map<String, dynamic>>> getRecords(String collection) async {
    final rows = await db.query(
      'cached_records',
      where: 'collection_name = ?',
      whereArgs: [collection],
    );

    return rows.map((row) {
      return Map<String, dynamic>.from(
        jsonDecode(row['json'] as String) as Map,
      );
    }).toList();
  }

  Future<void> replaceCollection(
    String collection,
    List<dynamic> records,
  ) async {
    await db.transaction((txn) async {
      await txn.delete(
        'cached_records',
        where: 'collection_name = ?',
        whereArgs: [collection],
      );

      for (final record in records) {
        final Map<String, dynamic> json = _recordToMap(record);
        final String? id = json['id']?.toString();

        if (id == null || id.isEmpty) {
          continue;
        }

        await txn.insert(
          'cached_records',
          {
            'collection_name': collection,
            'record_id': id,
            'json': jsonEncode(json),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Map<String, dynamic> _recordToMap(dynamic record) {
    if (record is Map<String, dynamic>) {
      return record;
    }
    if (record is Map) {
      return Map<String, dynamic>.from(record);
    }

    // Supports PocketBase RecordModel objects.
    final converted = record.toJson();
    return Map<String, dynamic>.from(converted as Map);
  }

  // Offline travel history

  Future<void> saveTravelVisit({
    required String localId,
    String? scheduleId,
    required String visitTime,
    required String purpose,
    String? notes,
    String? photoPath,
    List<String> attachmentPaths = const [],
  }) async {
    await db.insert(
      'bus_visits_outbox',
      {
        'local_id': localId,
        'schedule_id': scheduleId,
        'visit_time': visitTime,
        'purpose': purpose,
        'notes': notes,
        'photo_path': photoPath,
        'attachments_json': jsonEncode(attachmentPaths),
        'sync_status': 'pending',
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getTravelHistory() {
    return db.query(
      'bus_visits_outbox',
      orderBy: 'visit_time DESC',
    );
  }

  Future<List<Map<String, dynamic>>> getPendingTravelVisits() {
    return db.query(
      'bus_visits_outbox',
      where: 'sync_status = ?',
      whereArgs: ['pending'],
      orderBy: 'visit_time ASC',
    );
  }

  Future<void> markTravelVisitSynced({
    required String localId,
    required String pocketBaseId,
  }) async {
    await db.update(
      'bus_visits_outbox',
      {
        'sync_status': 'synced',
        'pocketbase_id': pocketBaseId,
      },
      where: 'local_id = ?',
      whereArgs: [localId],
    );
  }
}

class TimetablePage extends StatefulWidget {
  const TimetablePage({super.key});

  @override
  State<TimetablePage> createState() => _TimetablePageState();
}

class _TimetablePageState extends State<TimetablePage> {
  final LocalCache cache = LocalCache();
  final TextEditingController _tripSearchController = TextEditingController();
  final Map<String, List<Map<String, dynamic>>> records = {};

  Timer? _clockTimer;
  String _tripSearch = '';

  String? cityId;
  String? stationId;
  Set<String> favoriteScheduleIds = {};

  TimeOfDay? _departuresAfter;

  bool syncing = false;
  String syncMessage = 'Loading saved timetables…';

  static const _locationCollections = [
    'bus_cities',
    'bus_stations',
  ];

  static const _allCollections = [
    'bus_districts',
    'bus_taluks',
    'bus_cities',
    'bus_stations',
    'bus_timetables',
    'bus_trips',
  ];

  @override
  void initState() {
    super.initState();

    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });

    _start();
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _tripSearchController.dispose();
    super.dispose();
  }

  void _clearTripSearch() {
    _tripSearchController.clear();
    _tripSearch = '';
  }

  Future<void> _start() async {
    try {
      await cache.init();
      favoriteScheduleIds = await cache.getFavoriteScheduleIds();
      await _loadCache();
      await _sync();
    } catch (e) {
      debugPrint('App initialization failed: $e');
      if (mounted) {
        setState(() {
          syncMessage = 'Could not open local cache: $e';
        });
      }
    }
  }

  Future<void> _loadCache() async {
    for (final collection in _allCollections) {
      records[collection] = await cache.getRecords(collection);
    }

    if (!mounted) return;

    setState(() {
      if (!_containsId(cities, cityId)) {
        cityId = null;
        stationId = null;
      } else if (!_containsId(stations, stationId)) {
        stationId = null;
      }
    });
  }

  bool _containsId(List<Map<String, dynamic>> list, String? id) {
    return id != null && list.any((item) => item['id']?.toString() == id);
  }

  Future<bool> _ensureLocalNetworkAccess() async {
    if (!Platform.isAndroid) return true;

    final androidInfo = await DeviceInfoPlugin().androidInfo;
    if (androidInfo.version.sdkInt < 37) return true;

    final status = await Permission.accessLocalNetwork.request();
    if (status.isGranted) return true;

    if (status.isPermanentlyDenied) {
      await openAppSettings();
    }

    return false;
  }

  Future<void> _sync() async {
    if (syncing || !mounted) return;

    final hasLocalNetworkAccess = await _ensureLocalNetworkAccess();
    if (!hasLocalNetworkAccess) {
      if (mounted) {
        setState(() {
          syncMessage = 'Allow local network access to sync timetables.';
        });
      }
      return;
    }

    if (!mounted) return;

    setState(() {
      syncing = true;
      syncMessage = 'Syncing timetables…';
    });

    try {
      for (final collection in _locationCollections) {
        final fetched = await pb.collection(collection).getFullList();
        await cache.replaceCollection(collection, fetched);
      }

      final timetables = await pb.collection('bus_timetables').getFullList();
      await cache.replaceCollection('bus_timetables', timetables);

      final trips = await pb.collection('bus_trips').getFullList();
      await cache.replaceCollection('bus_trips', trips);

      await _loadCache();

      if (mounted) {
        setState(() {
          syncMessage = 'Timetables synced';
        });
      }
    } catch (e, stackTrace) {
      debugPrint('PocketBase sync failed: $e');
      debugPrintStack(stackTrace: stackTrace);

      if (mounted) {
        setState(() {
          syncMessage = 'Sync failed: $e. Showing saved data if available.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          syncing = false;
        });
      }
    }
  }

  Future<void> _toggleFavorite(String scheduleId) async {
    if (favoriteScheduleIds.contains(scheduleId)) {
      await cache.removeFavorite(scheduleId);
      favoriteScheduleIds.remove(scheduleId);
    } else {
      await cache.addFavorite(scheduleId);
      favoriteScheduleIds.add(scheduleId);
    }

    if (mounted) setState(() {});
  }

  Future<void> _markTravelled(
    Map<String, dynamic> trip,
    String routeLabel,
  ) async {
    final scheduleId = trip['id']?.toString();
    if (scheduleId == null || scheduleId.isEmpty) return;

    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddVisitPage(
          pb: pb,
          scheduleId: scheduleId,
          scheduleLabel: routeLabel,
        ),
      ),
    );

    if (!mounted) return;

    if (saved == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Travel recorded')),
      );
    }
  }

  List<Map<String, dynamic>> _records(String collection) {
    return records[collection] ?? const [];
  }

  String _getRelationId(dynamic fieldValue) {
    if (fieldValue == null) return '';

    if (fieldValue is String || fieldValue is num) {
      return fieldValue.toString();
    }

    if (fieldValue is Map) {
      return fieldValue['id']?.toString() ?? '';
    }

    if (fieldValue is List && fieldValue.isNotEmpty) {
      return _getRelationId(fieldValue.first);
    }

    return '';
  }

  String _recordRelationId(
    Map<String, dynamic> record,
    String fieldName,
  ) {
    return _getRelationId(
      record[fieldName] ?? record['${fieldName}_id'],
    );
  }

  String _name(Map<String, dynamic> record) {
    return record['name']?.toString() ??
        record['title']?.toString() ??
        record['city_name']?.toString() ??
        record['station_name']?.toString() ??
        'Unnamed';
  }

  List<Map<String, dynamic>> get cities {
    final result = [..._records('bus_cities')];
    result.sort((a, b) => _name(a).compareTo(_name(b)));
    return result;
  }

  List<Map<String, dynamic>> get stations {
    if (cityId == null) return [];

    final result = _records('bus_stations')
        .where((record) => _recordRelationId(record, 'city') == cityId)
        .toList();

    result.sort((a, b) => _name(a).compareTo(_name(b)));
    return result;
  }

  Widget _selector({
    required String label,
    required String? selectedId,
    required List<Map<String, dynamic>> options,
    required ValueChanged<String?> onChanged,
  }) {
    final isValidSelection = options.any(
      (option) => option['id']?.toString() == selectedId,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        initialValue: isValidSelection ? selectedId : null,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        items: options
            .map((record) {
              final id = record['id']?.toString();
              if (id == null) return null;

              return DropdownMenuItem<String>(
                value: id,
                child: Text(_name(record)),
              );
            })
            .whereType<DropdownMenuItem<String>>()
            .toList(),
        onChanged: options.isEmpty ? null : onChanged,
      ),
    );
  }

  bool _isPublished(Map<String, dynamic> record) {
    final status = record['status']?.toString().toLowerCase().trim() ?? '';
    return status.isEmpty || status == 'published';
  }

  int _departureMinutes(dynamic value) {
    final time = (value ?? '').toString().trim().toUpperCase();
    final match =
        RegExp(r'^(\d{1,2}):?(\d{2})\s*(AM|PM)?$').firstMatch(time);

    if (match == null) return 1 << 30;

    var hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    final meridiem = match.group(3);

    if (minute > 59) return 1 << 30;

    if (meridiem != null) {
      if (hour < 1 || hour > 12) return 1 << 30;
      if (meridiem == 'PM' && hour < 12) hour += 12;
      if (meridiem == 'AM' && hour == 12) hour = 0;
    } else if (hour > 23) {
      return 1 << 30;
    }

    return hour * 60 + minute;
  }

  Map<String, dynamic>? get selectedTimetable {
    final matches = _records('bus_timetables')
        .where(
          (record) =>
              _isPublished(record) &&
              _recordRelationId(record, 'station') == stationId,
        )
        .toList()
      ..sort((a, b) {
        final aVersion = (a['version'] as num?)?.toInt() ?? 0;
        final bVersion = (b['version'] as num?)?.toInt() ?? 0;
        return bVersion.compareTo(aVersion);
      });

    return matches.isEmpty ? null : matches.first;
  }

  List<Map<String, dynamic>> get trips {
    final timetable = selectedTimetable;
    if (timetable == null) return [];

    final timetableId = timetable['id']?.toString() ?? '';

    final result = _records('bus_trips')
        .where(
          (record) => _recordRelationId(record, 'timetable') == timetableId,
        )
        .toList()
      ..sort(
        (a, b) => _departureMinutes(a['departure_time'])
            .compareTo(_departureMinutes(b['departure_time'])),
      );

    return result;
  }

  List<Map<String, dynamic>> get filteredTrips {
    final query = _tripSearch.trim().toLowerCase();
    final allTrips = trips;

    final afterMinutes = _departuresAfter == null
        ? null
        : _departuresAfter!.hour * 60 + _departuresAfter!.minute;

    return allTrips.where((trip) {
      final departureMinutes = _departureMinutes(trip['departure_time']);

      if (afterMinutes != null &&
          (departureMinutes >= 24 * 60 || departureMinutes < afterMinutes)) {
        return false;
      }

      if (query.isEmpty) return true;

      final destination = (trip['to_place'] ?? '').toString().toLowerCase();
      final dynamic viaValue = trip['via_places'];
      final List<String> viaPlaces;

      if (viaValue is List) {
        viaPlaces = viaValue.map((place) => place.toString()).toList();
      } else {
        viaPlaces = (viaValue ?? '').toString().split(RegExp(r'[,;]'));
      }

      return destination.contains(query) ||
          viaPlaces.any(
            (place) => place.trim().toLowerCase().contains(query),
          );
    }).toList();
  }

  String _formatViaPlaces(dynamic value) {
    if (value == null) return '';
    if (value is List) return value.join(', ');
    return value.toString();
  }

  Future<void> _shareOriginalPdf(
    BuildContext buttonContext,
    Map<String, dynamic> timetable,
  ) async {
    final filename = timetable['source_pdf']?.toString() ?? '';

    if (filename.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No original PDF is attached.')),
      );
      return;
    }

    try {
      final record = RecordModel(timetable);
      final url = pb.files.getURL(record, filename);
      final response = await http.get(url);

      if (response.statusCode != 200) {
        throw Exception('PDF request returned ${response.statusCode}');
      }

      final tempDir = await getTemporaryDirectory();
      final safeFilename = p.basename(filename);
      final file = File(p.join(tempDir.path, safeFilename));
      await file.writeAsBytes(response.bodyBytes, flush: true);

      final renderObject = buttonContext.findRenderObject();
      final box = renderObject is RenderBox ? renderObject : null;
      final origin =
          box == null ? null : box.localToGlobal(Offset.zero) & box.size;

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: 'Original bus timetable',
          sharePositionOrigin: origin,
        ),
      );
    } catch (e) {
      debugPrint('Could not share timetable PDF: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not share PDF: $e')),
        );
      }
    }
  }

  Future<void> _chooseDeparturesAfter() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: _departuresAfter ?? TimeOfDay.now(),
      helpText: 'Show departures at or after this time',
    );

    if (selected != null && mounted) {
      setState(() => _departuresAfter = selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final timetable = selectedTimetable;
    final now = DateTime.now();
    final currentMinutes = now.hour * 60 + now.minute;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bus Timetable'),
        actions: [
          if (timetable != null)
            Builder(
              builder: (buttonContext) => IconButton(
                tooltip: 'Share original PDF',
                icon: const Icon(Icons.share),
                onPressed: () => _shareOriginalPdf(buttonContext, timetable),
              ),
            ),
          IconButton(
            tooltip: 'Sync',
            onPressed: syncing ? null : _sync,
            icon: const Icon(Icons.sync),
          ),
          
      IconButton(
  icon: const Icon(Icons.history),
  tooltip: 'Travel history',
  onPressed: () {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ViewTravelHistoryPage(pb: pb),
      ),
    );
  },
),
     IconButton(
  tooltip: 'Favorites',
  icon: const Icon(Icons.favorite),
  onPressed: () {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FavoritesPage(
          loadFavoriteIds: cache.getFavoriteScheduleIds,
          loadTrips: () => cache.getRecords('bus_trips'),
          tripBuilder: (context, trip) => _buildTripCard(
  trip,
  isFavorite: true,
  onFavoriteTap: () => yourFavoriteToggleFunction(trip),
  onMarkTravelled: () => yourMarkTravelledFunction(trip),
),

        ),
      ),
    );
  },

    ),
        ],
      ),


      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(syncMessage),
          const SizedBox(height: 16),

          _selector(
            label: 'City',
            selectedId: cityId,
            options: cities,
            onChanged: (value) {
              setState(() {
                cityId = value;
                stationId = null;
                _clearTripSearch();
              });
            },
          ),
          _selector(
            label: 'Station',
            selectedId: stationId,
            options: stations,
            onChanged: (value) {
              setState(() {
                stationId = value;
                _clearTripSearch();
              });
            },
          ),

          if (stationId == null)
            const Text('Select a city and station to view its timetable.')
          else if (timetable == null)
            const Text('No published timetable is available for this station.')
          else ...[
            Text(
              'Departure timetable · Version ${timetable['version'] ?? ''}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _tripSearchController,
              decoration: InputDecoration(
                labelText: 'Search destination or via place',
                hintText: 'For example: Chikkamagalur or Magadi',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _tripSearch.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(_clearTripSearch),
                      ),
                border: const OutlineInputBorder(),
              ),
              onChanged: (value) {
                setState(() {
                  _tripSearch = value;
                });
              },
            ),
            const SizedBox(height: 8),

            OutlinedButton.icon(
              onPressed: _chooseDeparturesAfter,
              icon: const Icon(Icons.schedule),
              label: Text(
                _departuresAfter == null
                    ? 'Departures after (optional)'
                    : 'Departures after ${_departuresAfter!.format(context)}',
              ),
            ),
            if (_departuresAfter != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => setState(() => _departuresAfter = null),
                  child: const Text('Clear time filter'),
                ),
              ),
            const SizedBox(height: 8),

            if (trips.isEmpty)
              const Text('No trips are saved for this timetable.')
            else if (filteredTrips.isEmpty)
              const Text('No trips match your search or time filter.')
            else
              ...filteredTrips.map((trip) {
                final time = trip['departure_time']?.toString() ?? '';
                final departureMinutes = _departureMinutes(time);
                final isUpcoming = departureMinutes >= currentMinutes &&
                    departureMinutes < 24 * 60;

                final type = trip['type_raw']?.toString() ?? '';
                final via = _formatViaPlaces(trip['via_places']);
                final routeLabel =
                    '${trip['from_place'] ?? ''} → ${trip['to_place'] ?? ''}';
                final scheduleId = trip['id']?.toString() ?? '';
                final isFavorite =
                    favoriteScheduleIds.contains(scheduleId);

                return Card(
                  color: isUpcoming
                      ? Colors.green.withOpacity(0.12)
                      : Colors.red.withOpacity(0.12),
                  child: Column(
                    children: [
                      ListTile(
                        leading: Text(
                          time,
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color:
                                        isUpcoming ? Colors.green : Colors.red,
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                        title: Text(routeLabel),
                        subtitle: Text([
                          if (type.isNotEmpty) type,
                          if (via.isNotEmpty) 'Via: $via',
                        ].join(' · ')),
                        trailing: IconButton(
                          tooltip: isFavorite
                              ? 'Remove favorite'
                              : 'Add favorite',
                          icon: Icon(
                            isFavorite ? Icons.star : Icons.star_border,
                            color: isFavorite ? Colors.amber : null,
                          ),
                          onPressed: scheduleId.isEmpty
                              ? null
                              : () => _toggleFavorite(scheduleId),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: const EdgeInsets.only(
                            right: 12,
                            bottom: 8,
                          ),
                          child: TextButton.icon(
                            onPressed: () => _markTravelled(trip, routeLabel),
                            icon: const Icon(Icons.directions_bus),
                            label: const Text('Mark travelled'),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ],
      ),
    );
  }
Widget _buildTripCard(
  Map<String, dynamic> trip, {
  bool isFavorite = false,
  VoidCallback? onFavoriteTap,
  VoidCallback? onMarkTravelled,
}) {
  String field(List<String> keys) {
    for (final key in keys) {
      final value = trip[key]?.toString().trim();

      if (value != null &&
          value.isNotEmpty &&
          !RegExp(r'^[a-zA-Z0-9]{15}$').hasMatch(value)) {
        return value;
      }
    }
    return '';
  }

  final from = field(['from_city', 'origin', 'source', 'from', 'from_place']);
  final to = field(['to_city', 'destination', 'to', 'to_place']);
  final route = field(['route_name', 'name']);
  final departure = field(['departure_time', 'depart_time', 'departure']);

  // Prefer the service/type fields so this can show values like EV or EXP.
  final service = field([
    'type_raw',
    'service_type',
    'bus_type',
    'type',
    'bus_name',
    'bus_number',
    'bus',
  ]);

  final via = field(['via_places', 'via_place', 'via', 'stops']);

  final title = from.isNotEmpty && to.isNotEmpty
      ? '$from → $to'
      : route.isNotEmpty
          ? route
          : 'Bus trip';

  final serviceText = [
    if (service.isNotEmpty) service,
    if (via.isNotEmpty) 'Via: $via',
  ].join(' · ');

  return Card(
    color: const Color(0xFFC2B0AC),
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
      child: Column(
        children: [
          Row(
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
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (serviceText.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          serviceText,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              IconButton(
                onPressed: onFavoriteTap,
                icon: Icon(
                  isFavorite ? Icons.star : Icons.star_border,
                  color: Colors.black54,
                ),
              ),
            ],
          ),
          if (onMarkTravelled != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onMarkTravelled,
                icon: const Icon(Icons.directions_bus, color: Colors.teal),
                label: const Text(
                  'Mark travelled',
                  style: TextStyle(color: Colors.teal),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}



}

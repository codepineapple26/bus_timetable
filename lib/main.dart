import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';

const pbUrl = 'http://10.253.154.218:8090';
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
      version: 1,
      onCreate: (database, version) async {
        await database.execute('''
          CREATE TABLE cached_records (
            collection_name TEXT NOT NULL,
            record_id TEXT NOT NULL,
            json TEXT NOT NULL,
            PRIMARY KEY (collection_name, record_id)
          )
        ''');
      },
    );
  }

  Future<void> replaceCollection(
    String collection,
    List<RecordModel> records,
  ) async {
    await db.transaction((txn) async {
      await txn.delete(
        'cached_records',
        where: 'collection_name = ?',
        whereArgs: [collection],
      );

      final batch = txn.batch();
      for (final record in records) {
        batch.insert(
          'cached_records',
          {
            'collection_name': collection,
            'record_id': record.id,
            'json': jsonEncode(record.toJson()),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      await batch.commit(noResult: true);
    });
  }

  Future<List<Map<String, dynamic>>> getRecords(String collection) async {
    final rows = await db.query(
      'cached_records',
      where: 'collection_name = ?',
      whereArgs: [collection],
    );

    return rows
        .map(
          (row) => Map<String, dynamic>.from(
            jsonDecode(row['json'] as String) as Map,
          ),
        )
        .toList();
  }
}

class TimetablePage extends StatefulWidget {
  const TimetablePage({super.key});

  @override
  State<TimetablePage> createState() => _TimetablePageState();
}

class _TimetablePageState extends State<TimetablePage> {
  final LocalCache cache = LocalCache();
  final TextEditingController _tripSearchController =
      TextEditingController();

  final Map<String, List<Map<String, dynamic>>> records = {};

  String _tripSearch = '';

  String? districtId;
  String? talukId;
  String? cityId;
  String? stationId;

  bool syncing = false;
  String syncMessage = 'Loading saved timetables…';

  static const _locationCollections = [
    'bus_districts',
    'bus_taluks',
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
    _start();
  }

  @override
  void dispose() {
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
      if (!_containsId(districts, districtId)) districtId = null;
      if (!_containsId(taluks, talukId)) talukId = null;
      if (!_containsId(cities, cityId)) cityId = null;
      if (!_containsId(stations, stationId)) stationId = null;
    });
  }

  bool _containsId(List<Map<String, dynamic>> list, String? id) {
    return id != null && list.any((item) => item['id']?.toString() == id);
  }

  Future<void> _sync() async {
    if (syncing || !mounted) return;

    setState(() {
      syncing = true;
      syncMessage = 'Syncing timetables…';
    });

    try {
      for (final collection in _locationCollections) {
        final fetched = await pb.collection(collection).getFullList();
        await cache.replaceCollection(collection, fetched);
      }

      final timetables =
          await pb.collection('bus_timetables').getFullList();
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

  List<Map<String, dynamic>> _records(String collection) {
    return records[collection] ?? const [];
  }

  String _getRelationId(dynamic fieldValue) {
    if (fieldValue == null) return '';

    if (fieldValue is String || fieldValue is num) {
      return fieldValue.toString();
    }

    if (fieldValue is Map) {
      final id = fieldValue['id'];
      return id?.toString() ?? '';
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

  List<Map<String, dynamic>> get districts => _records('bus_districts');

  List<Map<String, dynamic>> get taluks => _records('bus_taluks')
      .where(
        (record) =>
            _recordRelationId(record, 'district') == districtId,
      )
      .toList();

  List<Map<String, dynamic>> get cities => _records('bus_cities')
      .where(
        (record) => _recordRelationId(record, 'taluk') == talukId,
      )
      .toList();

  List<Map<String, dynamic>> get stations => _records('bus_stations')
      .where(
        (record) => _recordRelationId(record, 'city') == cityId,
      )
      .toList();

  bool _isPublished(Map<String, dynamic> record) {
    final status = record['status']?.toString().toLowerCase().trim() ?? '';
    return status.isEmpty || status == 'published';
  }

  int _departureMinutes(dynamic value) {
  final time = (value ?? '').toString().trim().toUpperCase();
  final match = RegExp(
    r'^(\d{1,2}):?(\d{2})\s*(AM|PM)?$',
  ).firstMatch(time);

  if (match == null) return 1 << 30; // Invalid or empty times sort last.

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

  return _records('bus_trips')
      .where(
        (record) =>
            _recordRelationId(record, 'timetable') == timetableId,
      )
      .toList()
    ..sort((a, b) => _departureMinutes(a['departure_time'])
        .compareTo(_departureMinutes(b['departure_time'])));
}


  List<Map<String, dynamic>> get filteredTrips {
    final query = _tripSearch.trim().toLowerCase();
    final allTrips = trips;

    if (query.isEmpty) return allTrips;

    return allTrips.where((trip) {
      final destination =
          (trip['to_place'] ?? '').toString().toLowerCase();

      final dynamic viaValue = trip['via_places'];
      final List<String> viaPlaces;

      if (viaValue is List) {
        viaPlaces = viaValue.map((place) => place.toString()).toList();
      } else {
        viaPlaces = (viaValue ?? '')
            .toString()
            .split(RegExp(r'[,;]'));
      }

      return destination.contains(query) ||
          viaPlaces.any(
            (place) => place.trim().toLowerCase().contains(query),
          );
    }).toList();
  }

  String _name(Map<String, dynamic> record) {
    return record['name']?.toString() ??
        record['title']?.toString() ??
        record['station_name']?.toString() ??
        'Unnamed';
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
        value: isValidSelection ? selectedId : null,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        items: options.map((record) {
          final id = record['id']?.toString();
          if (id == null) return null;

          return DropdownMenuItem<String>(
            value: id,
            child: Text(_name(record)),
          );
        }).whereType<DropdownMenuItem<String>>().toList(),
        onChanged: onChanged,
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    final timetable = selectedTimetable;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bus Timetable'),
        actions: [
          if (timetable != null)
            Builder(
              builder: (buttonContext) => IconButton(
                tooltip: 'Share original PDF',
                icon: const Icon(Icons.share),
                onPressed: () =>
                    _shareOriginalPdf(buttonContext, timetable),
              ),
            ),
          IconButton(
            tooltip: 'Sync',
            onPressed: syncing ? null : _sync,
            icon: const Icon(Icons.sync),
          ),
        ],
      ),
    body: ListView(
  padding: const EdgeInsets.all(16),
  children: [
    Text(syncMessage),
    const SizedBox(height: 16),

    SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          SizedBox(
            width: 150,
            child: _selector(
              label: 'Dist',
              selectedId: districtId,
              options: districts,
              onChanged: (value) {
                setState(() {
                  _clearTripSearch();
                  districtId = value;
                  talukId = null;
                  cityId = null;
                  stationId = null;
                });
              },
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 150,
            child: _selector(
              label: 'Taluk',
              selectedId: talukId,
              options: taluks,
              onChanged: (value) {
                setState(() {
                  _clearTripSearch();
                  talukId = value;
                  cityId = null;
                  stationId = null;
                });
              },
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 150,
            child: _selector(
              label: 'City',
              selectedId: cityId,
              options: cities,
              onChanged: (value) {
                setState(() {
                  _clearTripSearch();
                  cityId = value;
                  stationId = null;
                });
              },
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 150,
            child: _selector(
              label: 'Station',
              selectedId: stationId,
              options: stations,
              onChanged: (value) {
                setState(() {
                  _clearTripSearch();
                  stationId = value;
                });
              },
            ),
          ),
        ],
      ),
    ),

    const SizedBox(height: 16),

    if (stationId == null)
      const Text('Select a station to view its timetable.')
    else if (timetable == null)
      const Text('No published timetable is available for this station.')
    else ...[
      Text(
        'Departure timetable · Version ${timetable['version'] ?? ''}',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 8),
      TextField(
        controller: _tripSearchController,
        decoration: InputDecoration(
          labelText: 'Search Destination or via Place',
          hintText: 'For example: Chikkamagalur or Magadi',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _tripSearch.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    setState(_clearTripSearch);
                  },
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
      if (trips.isEmpty)
        const Text('No trips are saved for this timetable.')
      else if (filteredTrips.isEmpty)
        const Text('No trips match your search.')
      else
        ...filteredTrips.map((trip) {
          final time = trip['departure_time']?.toString() ?? '';
          final type = trip['type_raw']?.toString() ?? '';
          final via = trip['via_places']?.toString() ?? '';

          return Card(
            child: ListTile(
              leading: Text(
                time,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              title: Text(
                '${trip['from_place'] ?? ''} → ${trip['to_place'] ?? ''}',
              ),
              subtitle: Text([
                if (type.isNotEmpty) type,
                if (via.isNotEmpty) 'Via: $via',
              ].join(' · ')),
            ),
          );
        }),
    ],
  ],
),

    );
  }
}

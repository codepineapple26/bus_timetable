import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
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

  final Map<String, List<Map<String, dynamic>>> records = {};
  String? districtId;
  String? talukId;
  String? cityId;
  String? stationId;

  bool syncing = false;
  String syncMessage = 'Loading saved timetables…';

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      await cache.init();
      await _loadCache();
      await _sync();
    } catch (e) {
      if (mounted) {
        setState(() => syncMessage = 'Could not open local cache: $e');
      }
    }
  }

  Future<void> _loadCache() async {
    // 🛠️ FIX: Updated to your collection names matching the bus_ prefix
    const collections = [
      'bus_districts',
      'bus_taluks',
      'bus_cities',
      'bus_stations',
      'bus_timetables',
      'bus_trips',
    ];

    for (final collection in collections) {
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

  bool _containsId(List<Map<String, dynamic>> list, String? id) =>
      id != null && list.any((item) => item['id'] == id);

  Future<void> _sync() async {
    if (syncing) return;
    setState(() {
      syncing = true;
      syncMessage = 'Syncing published timetables…';
    });

    try {
      // 🛠️ FIX: Appending bus_ prefix to all core collections
      const collections = ['bus_districts', 'bus_taluks', 'bus_cities', 'bus_stations'];

      for (final collection in collections) {
        final fetched = await pb.collection(collection).getFullList(sort: 'name');
        await cache.replaceCollection(collection, fetched);
      }

      // 🛠️ FIX: Querying 'bus_timetables' collection
      final timetables = await pb.collection('bus_timetables').getFullList(
            filter: 'status = "published"',
            sort: '-version',
          );
      await cache.replaceCollection('bus_timetables', timetables);

      // 🛠️ FIX: Querying 'bus_trips' collection
      final trips = await pb.collection('bus_trips').getFullList(
            filter: 'timetable.status = "published"',
            sort: 'serial_no',
          );
      await cache.replaceCollection('bus_trips', trips);

      await _loadCache();
      if (mounted) setState(() => syncMessage = 'Timetables synced');
    } catch (e) {
      if (mounted) {
        setState(() => syncMessage = 'Offline: showing saved timetables');
      }
      print("Sync error details: $e");
    } finally {
      if (mounted) setState(() => syncing = false);
    }
  }

  List<Map<String, dynamic>> _records(String collection) =>
      records[collection] ?? const [];

  String _getRelationId(dynamic fieldValue) {
    if (fieldValue == null) return '';
    if (fieldValue is String) return fieldValue;
    if (fieldValue is List && fieldValue.isNotEmpty) return fieldValue.first.toString();
    return fieldValue.toString();
  }

  // 🛠️ FIX: Directing getters to read from the updated bus_ prefixes
  List<Map<String, dynamic>> get districts => _records('bus_districts');

  List<Map<String, dynamic>> get taluks => _records('bus_taluks')
      .where((record) => _getRelationId(record['district']) == districtId)
      .toList();

  List<Map<String, dynamic>> get cities => _records('bus_cities')
      .where((record) => _getRelationId(record['taluk']) == talukId)
      .toList();

  List<Map<String, dynamic>> get stations => _records('bus_stations')
      .where((record) => _getRelationId(record['city']) == cityId)
      .toList();

  Map<String, dynamic>? get selectedTimetable {
    final matches = _records('bus_timetables')
        .where((record) => _getRelationId(record['station']) == stationId)
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

    return _records('bus_trips')
        .where((record) => _getRelationId(record['timetable']) == timetable['id'])
        .toList()
      ..sort((a, b) {
        final aNo = (a['serial_no'] as num?)?.toInt() ?? 0;
        final bNo = (b['serial_no'] as num?)?.toInt() ?? 0;
        return aNo.compareTo(bNo);
      });
  }

  String _name(Map<String, dynamic> record) =>
      record['name']?.toString() ?? 'Unnamed';

  Widget _selector({
    required String label,
    required String? selectedId,
    required List<Map<String, dynamic>> options,
    required ValueChanged<String?> onChanged,
  }) {
    final isValidSelection = options.any((opt) => opt['id'] == selectedId);
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        value: isValidSelection ? selectedId : null,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        items: options
            .map(
              (record) => DropdownMenuItem<String>(
                value: record['id'] as String,
                child: Text(_name(record)),
              ),
            )
            .toList(),
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
      final origin = box == null
          ? null
          : box.localToGlobal(Offset.zero) & box.size;

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: 'Original bus timetable',
          sharePositionOrigin: origin,
        ),
      );
    } catch (e) {
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
onPressed: () => _shareOriginalPdf(buttonContext, timetable),
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
_selector(
label: 'District',
selectedId: districtId,
options: districts,
onChanged: (value) => setState(() {
districtId = value;
talukId = null;
cityId = null;
stationId = null;
}),
),
_selector(
label: 'Taluk',
selectedId: talukId,
options: taluks,
onChanged: (value) => setState(() {
talukId = value;
cityId = null;
stationId = null;
}),
),
_selector(
label: 'City / Town',
selectedId: cityId,
options: cities,
onChanged: (value) => setState(() {
cityId = value;
stationId = null;
}),
),
_selector(
label: 'Bus Station',
selectedId: stationId,
options: stations,
onChanged: (value) => setState(() => stationId = value),
),
const SizedBox(height: 8),
if (stationId == null)
const Text('Select a station to view its timetable.')
else if (timetable == null)
const Text('No published timetable is available for this station.')
else if (trips.isEmpty)
const Text('No trips are saved for this timetable.')
else ...[
Text(
'Departure timetable · Version ${timetable['version'] ?? ''}',
style: Theme.of(context).textTheme.titleMedium,
),
const SizedBox(height: 8),
...trips.map((trip) {
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
trailing: Text('${trip['serial_no'] ?? ''}'),
),
);
}),
],
],
),
);
}
}

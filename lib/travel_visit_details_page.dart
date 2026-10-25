import 'dart:io';

import 'package:flutter/material.dart';

class TravelVisitDetailsPage extends StatelessWidget {
  const TravelVisitDetailsPage({
    super.key,
    required this.visit,
    this.routeLabel,
  });

  final Map<String, dynamic> visit;
  final String? routeLabel;

  @override
  Widget build(BuildContext context) {
    final photoPath = visit['photo_path']?.toString();
    final visitTime = visit['visit_time']?.toString() ?? '';
    final rawAttachments = visit['attachments_json'];
    final attachments =
        rawAttachments is List ? rawAttachments : const <dynamic>[];

    return Scaffold(
      appBar: AppBar(title: const Text('Travel details')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (routeLabel != null && routeLabel!.isNotEmpty)
            _detail('Route', routeLabel!),
          _detail('Date and time', visitTime),
          _detail('Purpose', visit['purpose']?.toString() ?? ''),
          if ((visit['notes']?.toString() ?? '').isNotEmpty)
            _detail('Notes', visit['notes'].toString()),
          if (photoPath != null &&
              photoPath.isNotEmpty &&
              File(photoPath).existsSync()) ...[
            const SizedBox(height: 16),
            const Text('Photo'),
            const SizedBox(height: 8),
            Image.file(File(photoPath)),
          ],
          if (attachments.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('Attachments'),
            ...attachments.map(
              (path) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.attach_file),
                title: Text(
                  path.toString().split(Platform.pathSeparator).last,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _detail(String label, String value) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text(value.isEmpty ? '—' : value),
    );
  }
}

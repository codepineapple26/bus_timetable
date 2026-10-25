import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:pocketbase/pocketbase.dart';

class AddVisitPage extends StatefulWidget {
  const AddVisitPage({
    super.key,
    required this.pb,
    required this.scheduleId,
    required this.scheduleLabel,
  });

  final PocketBase pb;
  final String scheduleId;
  final String scheduleLabel;

  @override
  State<AddVisitPage> createState() => _AddVisitPageState();
}

class _AddVisitPageState extends State<AddVisitPage> {
  final _notesController = TextEditingController();
  DateTime _travelDate = DateTime.now();
  List<PlatformFile> _attachments = [];
  bool _saving = false;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _travelDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );

    if (picked != null && mounted) {
      setState(() => _travelDate = picked);
    }
  }

  Future<void> _pickAttachments() async {
    final picked = await FilePicker.pickFiles();

    if (!mounted || picked.isEmpty) return;

    setState(() {
      // Your bus_visits collection currently allows up to 2 attachments.
      _attachments = picked.take(2).toList();
    });
  }

  Future<void> _saveVisit() async {
    setState(() => _saving = true);

    try {
      final files = <http.MultipartFile>[];

      for (final attachment in _attachments) {
        files.add(
          http.MultipartFile.fromBytes(
            'attachments',
            await attachment.readAsBytes(),
            filename: attachment.name,
          ),
        );
      }

      final selectedDate = DateTime(
        _travelDate.year,
        _travelDate.month,
        _travelDate.day,
      );

      await widget.pb.collection('bus_visits').create(
        body: {
          'schedule': widget.scheduleId,
          'visit_time': selectedDate.toUtc().toIso8601String(),
          'purpose': 'Travelled',
          'notes': _notesController.text.trim(),
        },
        files: files,
      );

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save travel record: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel =
        MaterialLocalizations.of(context).formatMediumDate(_travelDate);

    return Scaffold(
      appBar: AppBar(title: const Text('Mark as travelled')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(widget.scheduleLabel),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Travel date'),
            subtitle: Text(dateLabel),
            trailing: const Icon(Icons.calendar_month),
            onTap: _selectDate,
          ),
          TextField(
            controller: _notesController,
            decoration: const InputDecoration(
              labelText: 'Notes',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _pickAttachments,
            icon: const Icon(Icons.attach_file),
            label: const Text('Add attachments'),
          ),
          for (final attachment in _attachments)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(attachment.name),
              trailing: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  setState(() => _attachments.remove(attachment));
                },
              ),
            ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving ? null : _saveVisit,
            child: Text(_saving ? 'Saving…' : 'Save travel record'),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import '../models/journal_entry.dart';
import '../services/data_service.dart';

class JournalDetailPage extends StatefulWidget {
  final String entryId;
  final Box<JournalEntry> journalBox;
  final DataService dataService;

  const JournalDetailPage({
    super.key,
    required this.entryId,
    required this.journalBox,
    required this.dataService,
  });

  @override
  State<JournalDetailPage> createState() => _JournalDetailPageState();
}

class _JournalDetailPageState extends State<JournalDetailPage> {
  late Box<JournalEntry> journalBox;
  late JournalEntry entry;
  late TextEditingController controller;

  @override
  void initState() {
    super.initState();
    journalBox = widget.journalBox;
    entry = journalBox.get(widget.entryId)!;
    controller = TextEditingController(text: entry.text);
  }

  Future<void> _save() async {
    entry.text = controller.text.trim();
    entry.date = DateTime.now(); // update modified date
    await entry.save();
    await widget.dataService.syncJournalEntryToCloud(entry);
    Navigator.pop(context);
  }

  Future<void> _delete() async {
    await widget.dataService.deleteJournalEntry(entry);
    await journalBox.delete(entry.id);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Edit Entry"),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: _delete,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Expanded(
            child: TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.multiline,
              maxLines: null,
              expands: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: "Edit your entry...",
               ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _save,
                child: const Text("Save Changes"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

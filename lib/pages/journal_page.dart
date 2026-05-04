import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/journal_entry.dart';
import '../pages/journal_detail_page.dart';
import '../services/sentiment_service.dart';
import '../services/ml_export_services.dart';
import '../services/data_service.dart';

class JournalPage extends StatefulWidget {
  final DataService dataService;

  const JournalPage({super.key, required this.dataService});

  @override
  State<JournalPage> createState() => _JournalPageState();
}

class _JournalPageState extends State<JournalPage> {
  bool _isLoading = false;
  String? _error;

  final TextEditingController _controller = TextEditingController();
  late Box<JournalEntry> journalBox;

  @override
  void initState() {
    super.initState();
    _initBox();
  }

  Future<void> _initBox() async {
    journalBox = await widget.dataService.getJournalBox();
    setState(() {});
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _addEntry() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final sentiment = await SentimentService.analyze(text);

      final entry = JournalEntry(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        date: DateTime.now(),
        text: text,
        sentimentScore: (sentiment["compound"] as num).toDouble(),
        sentimentLabel: sentiment["label"] as String,
      );

      await journalBox.put(entry.id, entry);
      
      // Sync to cloud
      await widget.dataService.syncJournalEntryToCloud(entry);
      
      _controller.clear();
    } catch (e) {
      setState(() {
        _error = "Failed to analyze sentiment.";
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Color _sentimentColor(String label) {
    switch (label.toLowerCase()) {
      case 'positive':
        return Colors.green.shade600;
      case 'negative':
        return Colors.red.shade600;
      case 'neutral':
      default:
        return Colors.blueGrey.shade500;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Journal")),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _controller,
              maxLines: null,
              minLines: 3,
              decoration: const InputDecoration(
                hintText: "Write your thoughts…",
                border: OutlineInputBorder(),
              ),
            ),
          ),

          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.red),
              ),
            ),

          const SizedBox(height: 8),

          ElevatedButton(
            onPressed: _isLoading
                ? null
                : () async {
                    setState(() => _isLoading = true);

                    await _addEntry(); // ✅ ACTUALLY CALL IT

                    final file = await MLExportService.exportDailyFeatures();
                    debugPrint('ML export saved to: ${file.path}');

                    setState(() => _isLoading = false);
                  },
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text("Save Entry"),
          ),
          const Divider(),

          Expanded(
            child: ValueListenableBuilder<Box<JournalEntry>>(
              valueListenable: journalBox.listenable(),
              builder: (context, box, _) {
                final entries = box.values.toList().reversed.toList();

                if (entries.isEmpty) {
                  return const Center(child: Text("No journal entries yet."));
                }

                return ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];

                    return ListTile(
                      title: Text(
                        entry.text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(entry.date.toLocal().toString()),
                     trailing: entry.sentimentLabel != null
                      ? Chip(
                          label: Text(
                            entry.sentimentLabel!,
                            style: const TextStyle(color: Colors.white),
                          ),
                          backgroundColor:
                              _sentimentColor(entry.sentimentLabel!),
                        )
                      : null,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                JournalDetailPage(entryId: entry.id),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

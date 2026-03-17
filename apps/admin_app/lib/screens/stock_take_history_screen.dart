import 'package:flutter/material.dart';

import '../services/stock_take_session_service.dart';

class StockTakeHistoryScreen extends StatefulWidget {
  const StockTakeHistoryScreen({
    super.key,
    required this.sessionService,
  });

  final StockTakeSessionService sessionService;

  @override
  State<StockTakeHistoryScreen> createState() => _StockTakeHistoryScreenState();
}

class _StockTakeHistoryScreenState extends State<StockTakeHistoryScreen> {
  bool _isLoading = true;
  List<StockTakeHistoryEntry> _entries = <StockTakeHistoryEntry>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
    });

    final entries = await widget.sessionService.loadHistory();
    if (!mounted) return;

    setState(() {
      _entries = entries;
      _isLoading = false;
    });
  }

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Clear Stock Take History'),
            content: const Text(
              'This will remove all locally saved stock take history on this device.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Clear'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    await widget.sessionService.clearHistory();
    await _load();
  }

  void _showEntryDetails(StockTakeHistoryEntry entry) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.78,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.sessionName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text('Started: ${_formatDate(entry.startedAtIso)}'),
                      Text('Applied: ${_formatDate(entry.appliedAtIso)}'),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _pill(
                            'Counted ${entry.countedItems}',
                            Colors.green,
                          ),
                          _pill(
                            'Discrepancies ${entry.discrepancyItems}',
                            Colors.orange,
                          ),
                          _pill(
                            'Applied ${entry.appliedItems}',
                            Colors.blue,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: entry.lines.isEmpty
                      ? const Center(
                          child: Text('No discrepancy details saved.'),
                        )
                      : ListView.separated(
                          itemCount: entry.lines.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final line = entry.lines[index];
                            final diff = line.difference;
                            final diffText = diff > 0 ? '+$diff' : diff.toString();

                            return ListTile(
                              title: Text(
                                line.productName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                'Barcode: ${line.barcode}\n'
                                'System: ${line.systemStock} • Counted: ${line.countedStock}',
                              ),
                              isThreeLine: true,
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    diffText,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: diff == 0
                                          ? Colors.green
                                          : (diff > 0
                                              ? Colors.blue
                                              : Colors.orange),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    line.applied ? 'Applied' : 'Failed',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: line.applied
                                          ? Colors.green
                                          : Colors.red,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock Take History'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
          if (_entries.isNotEmpty)
            IconButton(
              tooltip: 'Clear History',
              onPressed: _clearHistory,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No stock take history saved yet.\n'
                      'Applied sessions will appear here.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount: _entries.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final entry = _entries[index];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      title: Text(
                        entry.sessionName,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        '${_formatDate(entry.appliedAtIso)}\n'
                        'Counted ${entry.countedItems} • '
                        'Discrepancies ${entry.discrepancyItems} • '
                        'Applied ${entry.appliedItems}',
                      ),
                      isThreeLine: true,
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _showEntryDetails(entry),
                    );
                  },
                ),
    );
  }

  Widget _pill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }

  String _formatDate(String raw) {
    if (raw.isEmpty) return '—';
    try {
      final date = DateTime.parse(raw).toLocal();
      String twoDigits(int value) => value.toString().padLeft(2, '0');
      return '${twoDigits(date.day)}/${twoDigits(date.month)}/${date.year} '
          '${twoDigits(date.hour)}:${twoDigits(date.minute)}';
    } catch (_) {
      return raw;
    }
  }
}

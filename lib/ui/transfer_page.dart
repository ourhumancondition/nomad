import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../engine/csv_codec.dart';
import '../platform/csv_file.dart';
import '../state/app_controller.dart';

class TransferPage extends StatefulWidget {
  const TransferPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<TransferPage> createState() => _TransferPageState();
}

class _TransferPageState extends State<TransferPage> {
  final _csv = TextEditingController();
  CsvImportPreview? _preview;
  bool _allowExample = false;
  String? _message;

  @override
  void dispose() {
    _csv.dispose();
    super.dispose();
  }

  void _parse(String raw) {
    setState(() {
      _preview = raw.trim().isEmpty ? null : CsvCodec.parse(raw);
      _message = null;
      _allowExample = false;
    });
  }

  Future<void> _import() async {
    final preview = _preview;
    if (preview == null) return;
    final failure = await widget.controller.importRows(
      preview,
      allowExampleIntoConnected: _allowExample,
    );
    if (!mounted) return;
    setState(() => _message = failure ?? 'Import finished.');
  }

  Future<void> _export() async {
    final contents = widget.controller.exportCsv();
    if (kIsWeb) {
      await downloadTextFile(widget.controller.exportFilename(), contents);
      return;
    }
    setState(() {
      _csv.text = contents;
      _message = 'The export is in the text box.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Text(
          'Import and export',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text(
          'The sheet uses one header and includes every year in the file, not only the year on screen. record_type is stay, flight, or meta. Import adds rows and updates a row only when its external id already exists. It does not delete anything.',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(onPressed: _export, child: const Text('Export CSV')),
            if (kIsWeb)
              OutlinedButton(
                onPressed: () async {
                  final text = await pickTextFile();
                  if (text == null) return;
                  _csv.text = text;
                  _parse(text);
                },
                child: const Text('Choose a file'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _csv,
          minLines: 8,
          maxLines: 16,
          decoration: const InputDecoration(
            labelText: 'CSV',
            alignLabelWithHint: true,
          ),
          onChanged: _parse,
        ),
        const SizedBox(height: 12),
        if (preview != null) ...[
          Text(
            '${preview.stays.length} stays, ${preview.flights.length} flights, ${preview.errors.length} row errors.',
          ),
          if (preview.exampleDataset)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _allowExample,
              onChanged: widget.controller.isConnected
                  ? (value) => setState(() => _allowExample = value ?? false)
                  : null,
              title: const Text('This file is labeled EXAMPLE DATASET'),
              subtitle: Text(
                widget.controller.isConnected
                    ? 'Check this to copy those fictional rows into the connected database.'
                    : 'Example mode can import it without copying it to PocketBase.',
              ),
            ),
          for (final error in preview.errors.take(8))
            Text(
              error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const Text(
            'Import does not accept flight proposals and does not change rows that are absent from the file. If it stops, the message lists what was saved. Importing the same file again continues the rest.',
          ),
          FilledButton(
            onPressed: preview.hasRows ? _import : null,
            child: const Text('Import valid rows'),
          ),
        ],
        if (_message != null) ...[const SizedBox(height: 12), Text(_message!)],
      ],
    );
  }
}

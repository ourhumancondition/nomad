import 'package:flutter/material.dart';

import '../data/countries.dart';
import '../engine/models.dart';
import '../state/app_controller.dart';
import 'format.dart';

/// Saves [country] for today, asking first when that takes today out of a
/// counting stay elsewhere, then shows a 5-second undo.
///
/// Shared by the Days banner and the connection offer in the top bar.
/// Returns true when something was written.
Future<bool> saveTodayWithUndo(
  BuildContext context,
  AppController controller,
  String country, {
  String note = '',
}) async {
  final messenger = ScaffoldMessenger.of(context);
  var result = await controller.saveTodayStay(country, note: note);
  if (result.needsConfirmation) {
    if (!context.mounted) return false;
    final ok = await _confirmReplace(context, country, result.staysElsewhere);
    if (ok != true) return false;
    result = await controller.saveTodayStay(
      country,
      note: note,
      replaceOthers: true,
    );
  }
  messenger.clearSnackBars();
  if (result.failure != null) {
    messenger.showSnackBar(
      SnackBar(content: Text('Couldn\'t save today. ${result.failure}')),
    );
    return false;
  }
  if (result.alreadySaved) {
    messenger.showSnackBar(
      SnackBar(
        content: Text('Today is already confirmed in ${countryName(country)}.'),
      ),
    );
    return false;
  }
  final undo = result.undo;
  final name = countryName(country);
  messenger.showSnackBar(
    SnackBar(
      key: const Key('today-saved'),
      duration: const Duration(seconds: 5),
      // An action would otherwise keep the snackbar up until tapped.
      persist: false,
      content: Text(
        result.extended
            ? 'Added today to your $name stay.'
            : 'Saved today as $name.',
      ),
      action: undo == null
          ? null
          : SnackBarAction(
              key: const Key('today-undo'),
              label: 'Undo',
              onPressed: () async {
                final failure = await undo();
                if (failure != null) {
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Couldn\'t undo that.')),
                  );
                }
              },
            ),
    ),
  );
  return true;
}

Future<bool?> _confirmReplace(
  BuildContext context,
  String country,
  List<Stay> elsewhere,
) {
  final name = countryName(country);
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: const Key('today-replace-dialog'),
      title: Text('Set today to $name?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Today is already counted in:'),
          const SizedBox(height: 8),
          for (final stay in elsewhere)
            Text(
              '${countryFlag(stay.countryCode)} ${countryName(stay.countryCode)}: '
              '${shortRange(stay.start, stay.end)}',
            ),
          const SizedBox(height: 12),
          Text(
            'Today will be taken out of ${elsewhere.length == 1 ? 'that stay' : 'those stays'}. '
            'The other days stay as they are. You can undo this.',
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('today-replace-confirm'),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text('Set today to $name'),
        ),
      ],
    ),
  );
}

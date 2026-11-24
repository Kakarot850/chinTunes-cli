import 'dart:io';
import 'dart:isolate';

import 'package:chintunes_core/chintunes_core.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';

/// Picks a Google Takeout `watch-history.json` and merges it into history.
/// Parsing runs in a background isolate (Takeout files can be tens of MB).
Future<void> importTakeoutHistory(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  final store = ref.read(libraryStoreProvider);

  void say(String message) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  final FilePickerResult? picked;
  try {
    picked = await FilePicker.platform.pickFiles(
      dialogTitle: 'Choose watch-history.json',
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
  } catch (_) {
    say('Couldn\'t open the file picker. Try again.');
    return;
  }
  final path = picked?.files.single.path;
  if (path == null) return;

  say('Importing watch history…');
  try {
    final text = await File(path).readAsString();
    final entries = await Isolate.run(() => TakeoutHistoryParser.parse(text));
    final added = await store.importHistory(entries);
    say(added == 0 ? 'No new plays found in that file.' : 'Imported $added plays from Google Takeout.');
  } on FormatException {
    say('That file isn\'t a YouTube watch-history.json. In Google Takeout, choose JSON as the history format.');
  } catch (_) {
    say('Couldn\'t read that file. Export it again from Google Takeout and retry.');
  }
}

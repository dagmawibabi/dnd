import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/adventure.dart';
import '../../models/tale.dart';
import '../../services/export.dart';
import '../../services/settings.dart';
import '../screens/adventure/adventure_screen.dart';
import '../screens/adventure/new_adventure_screen.dart';
import '../screens/adventure/text_adventure_screen.dart';
import '../screens/tales/tales_hub.dart';

class ImportAdventureButton extends StatefulWidget {
  const ImportAdventureButton({super.key});

  @override
  State<ImportAdventureButton> createState() => _ImportAdventureButtonState();
}

class _ImportAdventureButtonState extends State<ImportAdventureButton> {
  bool _busy = false;

  Future<void> _import() async {
    setState(() => _busy = true);
    try {
      final record = await importStory(context);
      if (!mounted || record == null) return;
      if (record is Map<String, dynamic>) {
        // A shared D&D adventure: choose a hero, then begin it fresh.
        context.read<SettingsController>().update((s) => s.homeMode = 'dnd');
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => NewAdventureScreen(template: record)));
        return;
      }
      context.read<SettingsController>().update((s) => s.homeMode = record is Tale ? 'tales' : 'dnd');
      final Route<void> route;
      if (record is Tale) {
        route = taleRoute(record);
      } else {
        final adventure = record as Adventure;
        route = MaterialPageRoute(
          builder: (_) => adventure.textMode ? TextAdventureScreen(adventure: adventure) : AdventureScreen(adventure: adventure),
        );
      }
      Navigator.of(context).pushReplacement(route);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Import adventure',
    onPressed: _busy ? null : _import,
    icon: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.file_upload_outlined),
  );
}

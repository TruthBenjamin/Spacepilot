import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/app/spacepilot_app.dart';
import 'features/auto_clean/data/services/automation_workmanager_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AutomationWorkmanagerService().initialize();
  runApp(const ProviderScope(child: SpacePilotApp()));
}

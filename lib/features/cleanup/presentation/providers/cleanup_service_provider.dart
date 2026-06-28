import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/cleanup_service.dart';

final cleanupServiceProvider = Provider<CleanupService>(
  (ref) => const CleanupService(),
);

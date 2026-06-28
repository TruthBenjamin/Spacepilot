import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/permission_service.dart';

final permissionServiceProvider = Provider<PermissionService>(
  (ref) => PermissionService(),
);

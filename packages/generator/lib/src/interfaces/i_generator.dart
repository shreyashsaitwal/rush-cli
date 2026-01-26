import 'dart:async';

import 'package:generator/src/models/workspace.dart';

abstract interface class IGenerator {
  FutureOr<void> generate(Workspace workspace);
}

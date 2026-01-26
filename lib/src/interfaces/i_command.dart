import 'package:args/command_runner.dart';
import 'package:triangle/triangle.dart';

class ICommand extends Command {
  @override
  late String description;

  @override
  late String name;

  TriangleProject get rush => TriangleProject('rush');
}

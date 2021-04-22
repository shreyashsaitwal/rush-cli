import 'package:process_run/shell.dart';
import 'package:rush_cli/installer/installer.dart';
import 'package:rush_prompt/rush_prompt.dart';

Future<void> main(List<String> args) async {
  PrintArt();
  await Installer().install();
  // print(whichSync('rush'));
}

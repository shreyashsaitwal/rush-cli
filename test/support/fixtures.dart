import 'dart:io';

import 'project.dart';

const _helperEnum = '''
package {package}.helpers;

import com.google.appinventor.components.common.OptionList;

public enum Mode implements OptionList<String> {
  /** Moves quickly. */
  FAST("fast"),
  /** Moves carefully. */
  SLOW("slow");

  private final String value;

  Mode(String value) {
    this.value = value;
  }

  public String toUnderlyingValue() {
    return value;
  }
}
''';

const _javaExtension = '''
package {package};

import com.google.appinventor.components.annotations.Extension;
import com.google.appinventor.components.annotations.SimpleFunction;
import com.google.appinventor.components.runtime.AndroidNonvisibleComponent;
import com.google.appinventor.components.runtime.ComponentContainer;
import com.google.appinventor.components.runtime.util.Continuation;

@Extension(description = "Test extension", icon = "icon.png")
public class {className} extends AndroidNonvisibleComponent {
  public {className}(ComponentContainer container) {
    super(container.\$form());
  }

{functions}
}
''';

extension Fixtures on TestProject {
  String fill(String template) => template
      .replaceAll('{package}', package)
      .replaceAll('{className}', className);

  void writeSource(String relativePath, String template) => source(relativePath)
    ..createSync(recursive: true)
    ..writeAsStringSync(fill(template));

  void writeHelperEnum() => writeSource('helpers/Mode.java', _helperEnum);

  String get helperEnum => fill(_helperEnum);

  void writeJavaExtension(String functions) => writeSource(
      '$className.java', _javaExtension.replaceFirst('{functions}', functions));

  String javaExtension(String functions) =>
      fill(_javaExtension).replaceFirst('{functions}', functions);

  void editSource(String relativePath, Pattern from, String to) =>
      _edit(source(relativePath), from, to);

  void editConfig(Pattern from, String to) => _edit(file('rush.yml'), from, to);

  void _edit(File file, Pattern from, String to) =>
      file.writeAsStringSync(file.readAsStringSync().replaceFirst(from, to));
}

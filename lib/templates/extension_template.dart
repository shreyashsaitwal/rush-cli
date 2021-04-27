String getExtensionTemp(String name, String org) {
  return '''
package $org;

import com.google.appinventor.components.annotations.SimpleFunction;
import com.google.appinventor.components.runtime.AndroidNonvisibleComponent;
import com.google.appinventor.components.runtime.ComponentContainer;
import com.google.appinventor.components.runtime.errors.YailRuntimeError;
import com.google.appinventor.components.runtime.util.YailList;

public class $name extends AndroidNonvisibleComponent {

  public $name(ComponentContainer container) {
    super(container.\$form());
  }

  @SimpleFunction(description = "Returns the sum of the given two integers.")
  public int Sum(int a, int b) {
    return a + b;
  }
}
''';
}

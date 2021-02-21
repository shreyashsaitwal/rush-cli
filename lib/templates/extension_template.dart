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

  @SimpleFunction(description = "Returns the sum of all integers from the given list.")
  public int SumAllIntegers(YailList intList) {
    int sum = 0;
    for (Object i : intList) {
      if (i instanceof Integer) {
        sum += (int) i;
      } else {
        throw new YailRuntimeError("Invalid value " + i + " in list 'intList' of method 'SumAllIntegers'.", "InvalidValue");
      }
    }
    return sum;
  }
}
''';
}

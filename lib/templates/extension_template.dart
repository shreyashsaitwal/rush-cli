String getExtensionTemp(String name, String org) {
  return '''
package $org;

import com.google.appinventor.components.annotations.*;
import com.google.appinventor.components.common.*;
import com.google.appinventor.components.runtime.*;

import java.util.List;

public class $name extends AndroidNonvisibleComponent {

  public $name(ComponentContainer container) {
    super(container.\$form());
  }

  @SimpleFunction(description = "Returns the sum of all numbers from the given list.")
  public int SumAll(List<Integer> list) {
    int sum = 0;
    for (int i : list) {
      sum += i;
    }
    return sum;
  }
}
''';
}

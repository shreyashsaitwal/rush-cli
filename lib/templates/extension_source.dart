String getExtensionTempJava(String name, String org) {
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

  @SimpleFunction(description = "Returns the sum of the given list of integers.")
  public int SumAll(YailList integers) {
    int sum = 0;

    for (final Object o : integers.toArray()) {
      try {
        sum += Integer.parseInt(o.toString());
      } catch (NumberFormatException e) {
        throw new YailRuntimeError(e.toString(), "NumberFormatException");
      }
    }

    return sum;
  }
}
''';
}

String getExtensionTempKt(String name, String org) {
  return '''
package $org

import com.google.appinventor.components.annotations.SimpleFunction
import com.google.appinventor.components.runtime.AndroidNonvisibleComponent
import com.google.appinventor.components.runtime.ComponentContainer
import com.google.appinventor.components.runtime.util.YailList

class $name(container: ComponentContainer) : AndroidNonvisibleComponent(container.`\$form`()) {

  @SimpleFunction(description = "Returns the sum of the given list of integers.")
  fun SumAll(integers: YailList): Int {
    return integers.sumBy {
      it.toString().toIntOrNull() ?: 0
    }
  }
}
''';
}

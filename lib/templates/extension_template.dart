String getExtensionTemp(String name, String org) {
  return '''
package $org;

import com.google.appinventor.components.annotations.DesignerComponent;
import com.google.appinventor.components.annotations.SimpleObject;
import com.google.appinventor.components.common.ComponentCategory;
import com.google.appinventor.components.runtime.AndroidNonvisibleComponent;
import com.google.appinventor.components.runtime.AndroidViewComponent;
import com.google.appinventor.components.runtime.ComponentContainer;

@SimpleObject(external = true)
public class $name extends AndroidNonvisibleComponent {

  public $name(ComponentContainer container) {
    super(container.\$form());
  }

  // @SimpleFunction(description = "A method that returns the sum of all digits in a list.")
  // public int GetSumFromList(YailList list) {
  //   int sum = 0;
  //   for (int i : list) {
  //     sum += i;
  //   }
  //   return sum;
  // }

}''';
}

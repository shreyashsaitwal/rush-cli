package com.example.fonts;

import android.graphics.Typeface;
import android.util.Log;
import android.view.LayoutInflater;
import android.widget.TextView;
import androidx.core.content.res.ResourcesCompat;
import com.google.appinventor.components.annotations.Extension;
import com.google.appinventor.components.runtime.AndroidNonvisibleComponent;
import com.google.appinventor.components.runtime.ComponentContainer;

@Extension(description = "Loads fonts from its own resources.", icon = "icon.png")
public class Fonts extends AndroidNonvisibleComponent {
  public Fonts(ComponentContainer container) {
    super(container.$form());
    Typeface numbers = ResourcesCompat.getFont(form, R.font.com_example_fonts_numbers);
    Typeface family = ResourcesCompat.getFont(form, R.font.com_example_fonts_family);
    TextView label = (TextView) LayoutInflater.from(form).inflate(R.layout.com_example_fonts_label, null);
    Log.i("RushE2E", "Fonts ready: numbers=" + (numbers != null)
        + " family=" + (family != null)
        + " style=" + !Typeface.DEFAULT.equals(label.getTypeface()));
  }
}

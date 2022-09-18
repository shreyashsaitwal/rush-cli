package io.shreyash.rush.processor.util

import io.shreyash.rush.processor.block.HelperType
import javax.lang.model.element.Element
import javax.lang.model.element.ExecutableElement

private val componentTypes = listOf(
    "com.google.appinventor.components.runtime.AccelerometerSensor",
    "com.google.appinventor.components.runtime.ActivityStarter",
    "com.google.appinventor.components.runtime.AndroidNonvisibleComponent",
    "com.google.appinventor.components.runtime.AndroidViewComponent",
    "com.google.appinventor.components.runtime.Ball",
    "com.google.appinventor.components.runtime.BarcodeScanner",
    "com.google.appinventor.components.runtime.Barometer",
    "com.google.appinventor.components.runtime.BluetoothClient",
    "com.google.appinventor.components.runtime.BluetoothConnectionBase",
    "com.google.appinventor.components.runtime.BluetoothServer",
    "com.google.appinventor.components.runtime.BufferedSingleValueSensor",
    "com.google.appinventor.components.runtime.Button",
    "com.google.appinventor.components.runtime.ButtonBase",
    "com.google.appinventor.components.runtime.Camcorder",
    "com.google.appinventor.components.runtime.Camera",
    "com.google.appinventor.components.runtime.Canvas",
    "com.google.appinventor.components.runtime.CheckBox",
    "com.google.appinventor.components.runtime.Circle",
    "com.google.appinventor.components.runtime.Clock",
    "com.google.appinventor.components.runtime.Component",
    "com.google.appinventor.components.runtime.ContactPicker",
    "com.google.appinventor.components.runtime.DatePicker",
    "com.google.appinventor.components.runtime.EmailPicker",
    "com.google.appinventor.components.runtime.Ev3ColorSensor",
    "com.google.appinventor.components.runtime.Ev3Commands",
    "com.google.appinventor.components.runtime.Ev3GyroSensor",
    "com.google.appinventor.components.runtime.Ev3Motors",
    "com.google.appinventor.components.runtime.Ev3Sound",
    "com.google.appinventor.components.runtime.Ev3TouchSensor",
    "com.google.appinventor.components.runtime.Ev3UI",
    "com.google.appinventor.components.runtime.Ev3UltrasonicSensor",
    "com.google.appinventor.components.runtime.FeatureCollection",
    "com.google.appinventor.components.runtime.File",
    "com.google.appinventor.components.runtime.FirebaseDB",
    "com.google.appinventor.components.runtime.Form",
    "com.google.appinventor.components.runtime.FusiontablesControl",
    "com.google.appinventor.components.runtime.GameClient",
    "com.google.appinventor.components.runtime.GyroscopeSensor",
    "com.google.appinventor.components.runtime.HorizontalArrangement",
    "com.google.appinventor.components.runtime.HorizontalScrollArrangement",
    "com.google.appinventor.components.runtime.HVArrangement",
    "com.google.appinventor.components.runtime.Hygrometer",
    "com.google.appinventor.components.runtime.Image",
    "com.google.appinventor.components.runtime.ImagePicker",
    "com.google.appinventor.components.runtime.ImageSprite",
    "com.google.appinventor.components.runtime.Label",
    "com.google.appinventor.components.runtime.LegoMindstormsEv3Base",
    "com.google.appinventor.components.runtime.LegoMindstormsEv3Sensor",
    "com.google.appinventor.components.runtime.LegoMindstormsNxtBase",
    "com.google.appinventor.components.runtime.LegoMindstormsNxtSensor",
    "com.google.appinventor.components.runtime.LightSensor",
    "com.google.appinventor.components.runtime.LinearLayout",
    "com.google.appinventor.components.runtime.LineString",
    "com.google.appinventor.components.runtime.ListPicker",
    "com.google.appinventor.components.runtime.ListView",
    "com.google.appinventor.components.runtime.LocationSensor",
    "com.google.appinventor.components.runtime.MagneticFieldSensor",
    "com.google.appinventor.components.runtime.Map",
    "com.google.appinventor.components.runtime.MapFeatureBase",
    "com.google.appinventor.components.runtime.MapFeatureBaseWithFill",
    "com.google.appinventor.components.runtime.MapFeatureContainerBase",
    "com.google.appinventor.components.runtime.Marker",
    "com.google.appinventor.components.runtime.MediaStore",
    "com.google.appinventor.components.runtime.Navigation",
    "com.google.appinventor.components.runtime.NearField",
    "com.google.appinventor.components.runtime.Notifier",
    "com.google.appinventor.components.runtime.NxtColorSensor",
    "com.google.appinventor.components.runtime.NxtDirectCommands",
    "com.google.appinventor.components.runtime.NxtDrive",
    "com.google.appinventor.components.runtime.NxtLightSensor",
    "com.google.appinventor.components.runtime.NxtSoundSensor",
    "com.google.appinventor.components.runtime.NxtTouchSensor",
    "com.google.appinventor.components.runtime.NxtUltrasonicSensor",
    "com.google.appinventor.components.runtime.OrientationSensor",
    "com.google.appinventor.components.runtime.PasswordTextBox",
    "com.google.appinventor.components.runtime.Pedometer",
    "com.google.appinventor.components.runtime.PhoneCall",
    "com.google.appinventor.components.runtime.PhoneNumberPicker",
    "com.google.appinventor.components.runtime.PhoneStatus",
    "com.google.appinventor.components.runtime.Picker",
    "com.google.appinventor.components.runtime.Player",
    "com.google.appinventor.components.runtime.Polygon",
    "com.google.appinventor.components.runtime.PolygonBase",
    "com.google.appinventor.components.runtime.ProximitySensor",
    "com.google.appinventor.components.runtime.Rectangle",
    "com.google.appinventor.components.runtime.SensorComponent",
    "com.google.appinventor.components.runtime.Serial",
    "com.google.appinventor.components.runtime.Sharing",
    "com.google.appinventor.components.runtime.SingleValueSensor",
    "com.google.appinventor.components.runtime.Slider",
    "com.google.appinventor.components.runtime.Sound",
    "com.google.appinventor.components.runtime.SoundRecorder",
    "com.google.appinventor.components.runtime.SpeechRecognizer",
    "com.google.appinventor.components.runtime.Spinner",
    "com.google.appinventor.components.runtime.Sprite",
    "com.google.appinventor.components.runtime.Switch",
    "com.google.appinventor.components.runtime.TableArrangement",
    "com.google.appinventor.components.runtime.TableLayout",
    "com.google.appinventor.components.runtime.TextBox",
    "com.google.appinventor.components.runtime.TextBoxBase",
    "com.google.appinventor.components.runtime.Texting",
    "com.google.appinventor.components.runtime.TextToSpeech",
    "com.google.appinventor.components.runtime.Thermometer",
    "com.google.appinventor.components.runtime.TimePicker",
    "com.google.appinventor.components.runtime.TinyDB",
    "com.google.appinventor.components.runtime.TinyWebDB",
    "com.google.appinventor.components.runtime.ToggleBase",
    "com.google.appinventor.components.runtime.Twitter",
    "com.google.appinventor.components.runtime.VerticalArrangement",
    "com.google.appinventor.components.runtime.VerticalScrollArrangement",
    "com.google.appinventor.components.runtime.VideoPlayer",
    "com.google.appinventor.components.runtime.VisibleComponent",
    "com.google.appinventor.components.runtime.Voting",
    "com.google.appinventor.components.runtime.Web",
    "com.google.appinventor.components.runtime.WebViewer",
    "com.google.appinventor.components.runtime.YandexTranslate"
)

/**
 * Returns a YAIL type from given [name] of a type.
 */
@Throws(IllegalStateException::class)
fun yailTypeOf(name: String, isHelper: Boolean): String {
    if (name.startsWith("java.util.List")) {
        return "list"
    } else if (componentTypes.contains(name)) {
        return "component"
    }

    return when (name) {
        "boolean" -> "boolean"
        "java.lang.Object" -> "any"
        "java.lang.String" -> "text"
        "java.util.Calendar" -> "InstantInTime"
        "float", "int", "double", "byte", "long", "short" -> "number"
        "com.google.appinventor.components.runtime.util.YailList" -> "list"
        "com.google.appinventor.components.runtime.util.YailObject" -> "yailobject"
        "com.google.appinventor.components.runtime.util.YailDictionary" -> "dictionary"
        else -> if (isHelper) {
            name + "Enum"
        } else {
            throw Exception("Can't convert type $name to YAIL type")
        }
    }
}

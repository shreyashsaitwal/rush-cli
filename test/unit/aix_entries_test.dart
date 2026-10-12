import 'package:rush/src/commands/build/aix.dart';
import 'package:test/test.dart';

Map<String, dynamic> _component(
        {String icon = 'images/extension.png', String license = ''}) =>
    {'iconName': icon, 'licenseName': license};

Map<String, dynamic> _buildInfo(
        {List<String> assets = const [], List<String> libraries = const []}) =>
    {'assets': assets, 'libraries': libraries};

void main() {
  const files = {
    'components.json',
    'classes.jar',
    'files/AndroidRuntime.jar',
    'files/component_build_infos.json',
  };

  test('lists the descriptors, the runtime and the dex', () {
    expect(aixEntries([_component()], [_buildInfo()]), files);
  });

  test('adds the shipped icon, license, assets and libraries', () {
    expect(
        aixEntries([
          _component(icon: 'aiwebres/logo.png', license: 'aiwebres/LICENSE')
        ], [
          _buildInfo(assets: ['data.json'], libraries: ['com.example.aar'])
        ]),
        {
          ...files,
          'aiwebres/logo.png',
          'aiwebres/LICENSE',
          'assets/data.json',
          'aars/com.example.aar',
        });
  });

  test('leaves out icons and licenses given as URLs', () {
    expect(
        aixEntries([
          _component(
              icon: 'https://example.com/icon.png',
              license: 'https://example.com/LICENSE')
        ], [
          _buildInfo()
        ]),
        files);
  });

  test('lists each entry once for several components', () {
    final component = _component(icon: 'aiwebres/icon.png');
    final info =
        _buildInfo(assets: ['data.json'], libraries: ['com.example.aar']);
    expect(aixEntries([component, component], [info, info]), hasLength(7));
  });
}

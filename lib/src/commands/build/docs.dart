String markdownDocs(List<dynamic> components) =>
    components.map((el) => _component(el as Map<String, dynamic>)).join('\n');

String _component(Map<String, dynamic> component) {
  final events = _visible(component['events']);
  final methods = _visible(component['methods']);
  final properties = _visible(component['blockProperties']);
  final designerDefaults = {
    for (final property in component['properties'] as List)
      property['name']: property['defaultValue'],
  };
  final dropdowns = {
    for (final item in [
      ...events.expand(_params),
      ...methods.expand((el) => [el, ..._params(el)]),
      ...properties,
    ])
      if (_dropdown(item) case final dropdown?) dropdown['key']: dropdown,
  };
  return '${_paragraphs([
        '# ${component['name']}',
        component['helpString'] as String,
        _section('Events', events.map(_block)),
        _section('Methods', methods.map(_block)),
        _section(
            'Properties',
            properties
                .map((el) => _property(el, designerDefaults[el['name']]))),
        _section('Dropdowns', dropdowns.values.map(_options)),
      ])}\n';
}

List<Map<String, dynamic>> _visible(dynamic items) => (items as List)
    .cast<Map<String, dynamic>>()
    .where((el) => el['deprecated'] != 'true')
    .toList();

List<Map<String, dynamic>> _params(Map<String, dynamic> block) =>
    (block['params'] as List).cast<Map<String, dynamic>>();

Map<String, dynamic>? _dropdown(Map<String, dynamic> item) {
  final helper = item['helper'];
  return helper?['type'] == 'OPTION_LIST' ? helper['data'] : null;
}

String? _type(Map<String, dynamic> item, [String typeKey = 'type']) =>
    _dropdown(item)?['key'] ?? item[typeKey];

String _section(String title, Iterable<String> entries) =>
    entries.isEmpty ? '' : _paragraphs(['## $title', ...entries]);

String _block(Map<String, dynamic> block) {
  final params = _params(block);
  final returnType = _type(block, 'returnType');
  return _paragraphs([
    '### ${block['name']}(${params.map((el) => el['name']).join(', ')})',
    block['description'] as String,
    if (params.isNotEmpty)
      [
        '| Parameter | Type |',
        '|---|---|',
        for (final param in params) '| ${param['name']} | ${_type(param)} |',
      ].join('\n'),
    if (returnType != null) 'Returns `$returnType`.',
  ]);
}

String _property(Map<String, dynamic> property, String? designerDefault) =>
    _paragraphs([
      '### ${property['name']}',
      property['description'] as String,
      '${[
        '`${_type(property)}`',
        property['rw'],
        if (designerDefault != null) 'designer default `$designerDefault`',
      ].join(', ')}.',
    ]);

String _options(Map<String, dynamic> dropdown) => _paragraphs([
      '### ${dropdown['key']}',
      [
        '| Option | Value | Description |',
        '|---|---|---|',
        for (final option in _visible(dropdown['options']))
          '| ${option['name']} | `${option['value']}` | ${option['description']} |',
      ].join('\n'),
    ]);

String _paragraphs(List<String> parts) =>
    parts.map((el) => el.trim()).where((el) => el.isNotEmpty).join('\n\n');

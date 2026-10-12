const _shippedResourceDir = 'aiwebres/';

Set<String> aixEntries(List<Map<String, dynamic>> components,
        List<Map<String, dynamic>> buildInfos) =>
    {
      'components.json',
      'classes.jar',
      'files/AndroidRuntime.jar',
      'files/component_build_infos.json',
      for (final component in components)
        for (final name in [component['iconName'], component['licenseName']])
          if (name is String && name.startsWith(_shippedResourceDir)) name,
      for (final info in buildInfos) ...[
        for (final asset in info['assets'] as List) 'assets/$asset',
        for (final library in info['libraries'] as List) 'aars/$library',
      ],
    };

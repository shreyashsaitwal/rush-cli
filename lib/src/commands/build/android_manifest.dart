final _package = RegExp(r'<manifest[^>]*\spackage\s*=\s*"([^"]+)"');

String? manifestPackage(String manifest) =>
    _package.firstMatch(manifest)?.group(1);

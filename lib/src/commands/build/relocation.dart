import 'package:path/path.dart' as p;

const _desugarHelperPackages = ['com/android/tools/r8/', r'j$/'];

Iterable<String> relocatableClasses(Iterable<String> entries) => entries
    .where((el) => !el.startsWith('META-INF') && _isClass(el))
    .map(p.posix.withoutExtension);

Iterable<String> desugarHelpers(Iterable<String> entries) => entries
    .where((el) => _desugarHelperPackages.any(el.startsWith) && _isClass(el))
    .map(p.posix.withoutExtension);

bool _isClass(String entry) => p.posix.extension(entry) == '.class';

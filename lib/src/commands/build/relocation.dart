import 'package:path/path.dart' as p;

const _desugarHelperPackages = ['com/android/tools/r8/', r'j$/'];

Iterable<String> relocatableClasses(Iterable<String> entries) => entries
    .where((el) => !el.startsWith('META-INF') && _isClass(el))
    .map(p.posix.withoutExtension);

Iterable<String> desugarHelpers(Iterable<String> entries) => entries
    .where((el) => _desugarHelperPackages.any(el.startsWith) && _isClass(el))
    .map(p.posix.withoutExtension);

typedef RenamedMember = ({String owner, String name, String to});

String relocationSpec(String prefix, Iterable<String> classes,
        {Iterable<RenamedMember> fields = const []}) =>
    [
      'prefix $prefix',
      for (final name in classes) 'class $name',
      for (final field in fields)
        'field ${field.owner} ${field.name} ${field.to}',
    ].map((line) => '$line\n').join();

bool _isClass(String entry) => p.posix.extension(entry) == '.class';

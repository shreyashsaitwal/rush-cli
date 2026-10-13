import 'package:path/path.dart' as p;

String keepClassesRules(Iterable<String> classFiles) => classFiles
    .where((el) =>
        !el.startsWith('META-INF/') && p.posix.extension(el) == '.class')
    .map((el) => p.posix.withoutExtension(el).replaceAll('/', '.'))
    .map((el) => '-keep class $el { *; }')
    .join('\n');

package io.github.shreyashsaitwal.rush.relocator;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Set;
import java.util.stream.Collectors;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;
import java.util.zip.ZipOutputStream;
import org.objectweb.asm.ClassReader;
import org.objectweb.asm.ClassWriter;
import org.objectweb.asm.commons.ClassRemapper;
import org.objectweb.asm.commons.Remapper;

public final class Relocator extends Remapper {
  private static final String CLASS_SUFFIX = ".class";

  private final String prefix;
  private final Set<String> classes;

  Relocator(String prefix, Set<String> classes) {
    this.prefix = prefix;
    this.classes = classes;
  }

  @Override
  public String map(String internalName) {
    return classes.contains(internalName) ? prefix + internalName : internalName;
  }

  @Override
  public Object mapValue(Object value) {
    if (value instanceof String name) {
      if (classes.contains(name)) {
        return map(name);
      }
      String internalName = name.replace('.', '/');
      if (classes.contains(internalName)) {
        return map(internalName).replace('/', '.');
      }
    }
    return super.mapValue(value);
  }

  void relocate(Path input, Path output) throws IOException {
    try (var in = new ZipInputStream(Files.newInputStream(input));
        var out = new ZipOutputStream(Files.newOutputStream(output))) {
      for (ZipEntry entry; (entry = in.getNextEntry()) != null; ) {
        if (entry.isDirectory()) {
          continue;
        }
        byte[] content = in.readAllBytes();
        String name = entry.getName();
        if (name.endsWith(CLASS_SUFFIX)) {
          content = relocateClass(content);
          name = map(name.substring(0, name.length() - CLASS_SUFFIX.length())) + CLASS_SUFFIX;
        }
        out.putNextEntry(new ZipEntry(name));
        out.write(content);
        out.closeEntry();
      }
    }
  }

  private byte[] relocateClass(byte[] content) {
    var writer = new ClassWriter(0);
    new ClassReader(content).accept(new ClassRemapper(writer, this), 0);
    return writer.toByteArray();
  }

  public static void main(String[] args) throws IOException {
    if (args.length != 4) {
      System.err.println("usage: relocator <input.jar> <output.jar> <prefix> <classes.txt>");
      System.exit(2);
    }
    Set<String> classes;
    try (var lines = Files.lines(Path.of(args[3]))) {
      classes = lines.filter(line -> !line.isBlank()).collect(Collectors.toSet());
    }
    new Relocator(args[2], classes).relocate(Path.of(args[0]), Path.of(args[1]));
  }
}

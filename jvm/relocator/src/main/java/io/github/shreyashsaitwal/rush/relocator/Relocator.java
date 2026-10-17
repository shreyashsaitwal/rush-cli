package io.github.shreyashsaitwal.rush.relocator;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
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
  private static final String SERVICES = "META-INF/services/";

  private final RelocationSpec spec;

  Relocator(RelocationSpec spec) {
    this.spec = spec;
  }

  @Override
  public String map(String internalName) {
    return spec.classes().contains(internalName) ? spec.prefix() + internalName : internalName;
  }

  @Override
  public String mapFieldName(String owner, String name, String descriptor) {
    return spec.fields().getOrDefault(RelocationSpec.fieldKey(owner, name), name);
  }

  @Override
  public Object mapValue(Object value) {
    if (value instanceof String name && !spec.keptStrings().contains(name)) {
      if (spec.classes().contains(name)) {
        return map(name);
      }
      String internalName = name.replace('.', '/');
      if (spec.classes().contains(internalName)) {
        return mapClassName(name);
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
        } else if (name.startsWith(SERVICES)) {
          content = relocateServices(content);
          name = SERVICES + mapClassName(name.substring(SERVICES.length()));
        }
        var relocated = new ZipEntry(name);
        relocated.setTime(entry.getTime());
        out.putNextEntry(relocated);
        out.write(content);
        out.closeEntry();
      }
    }
  }

  private String mapClassName(String className) {
    return map(className.replace('.', '/')).replace('/', '.');
  }

  private byte[] relocateClass(byte[] content) {
    var writer = new ClassWriter(0);
    new ClassReader(content).accept(new ClassRemapper(writer, this), 0);
    return writer.toByteArray();
  }

  private byte[] relocateServices(byte[] content) {
    return new String(content, StandardCharsets.UTF_8)
        .lines()
        .map(line -> line.isBlank() || line.strip().startsWith("#") ? line : mapClassName(line.strip()))
        .collect(Collectors.joining("\n", "", "\n"))
        .getBytes(StandardCharsets.UTF_8);
  }

  public static void main(String[] args) throws IOException {
    if (args.length != 3) {
      System.err.println("usage: relocator <input.jar> <output.jar> <spec.txt>");
      System.exit(2);
    }
    new Relocator(RelocationSpec.read(Path.of(args[2]))).relocate(Path.of(args[0]), Path.of(args[1]));
  }
}

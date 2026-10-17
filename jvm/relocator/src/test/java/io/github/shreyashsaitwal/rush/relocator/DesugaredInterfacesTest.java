package io.github.shreyashsaitwal.rush.relocator;

import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.objectweb.asm.Opcodes.ACC_ABSTRACT;
import static org.objectweb.asm.Opcodes.ACC_FINAL;
import static org.objectweb.asm.Opcodes.ACC_INTERFACE;
import static org.objectweb.asm.Opcodes.ACC_PUBLIC;
import static org.objectweb.asm.Opcodes.ACC_STATIC;
import static org.objectweb.asm.Opcodes.ACC_SYNTHETIC;
import static org.objectweb.asm.Opcodes.V1_8;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.HashMap;
import java.util.Map;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;
import java.util.zip.ZipOutputStream;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.objectweb.asm.ClassReader;
import org.objectweb.asm.ClassVisitor;
import org.objectweb.asm.ClassWriter;
import org.objectweb.asm.FieldVisitor;
import org.objectweb.asm.Opcodes;

class DesugaredInterfacesTest {
  interface Shape {
    String NAME = String.valueOf(Shape.class);

    int sides();
  }

  @TempDir Path dir;

  @Test
  void makesInterfaceInitTriggersPublicStaticFinal() throws IOException {
    var input = dir.resolve("in.jar");
    byte[] shape;
    try (var compiled = Shape.class.getResourceAsStream("DesugaredInterfacesTest$Shape.class")) {
      shape = compiled.readAllBytes();
    }
    write(input, Map.of(
        "lib/Factory.class", type("lib/Factory", ACC_PUBLIC | ACC_INTERFACE | ACC_ABSTRACT,
            "$desugar$clinit", ACC_STATIC | ACC_SYNTHETIC),
        "lib/Holder.class", type("lib/Holder", ACC_PUBLIC, "$desugar$clinit", ACC_STATIC | ACC_SYNTHETIC),
        "lib/Shape.class", shape,
        "lib/notes.txt", "notes".getBytes(StandardCharsets.UTF_8)));
    var output = dir.resolve("out.jar");

    DesugaredInterfaces.fix(input, output);

    var entries = read(output);
    assertEquals(ACC_PUBLIC | ACC_STATIC | ACC_FINAL | ACC_SYNTHETIC,
        fieldAccess(entries.get("lib/Factory.class")));
    assertEquals(ACC_STATIC | ACC_SYNTHETIC, fieldAccess(entries.get("lib/Holder.class")));
    assertArrayEquals(shape, entries.get("lib/Shape.class"));
    assertEquals("notes", new String(entries.get("lib/notes.txt"), StandardCharsets.UTF_8));
  }

  private static byte[] type(String name, int access, String field, int fieldAccess) {
    var writer = new ClassWriter(0);
    writer.visit(V1_8, access, name, null, "java/lang/Object", null);
    writer.visitField(fieldAccess, field, "I", null, null).visitEnd();
    writer.visitEnd();
    return writer.toByteArray();
  }

  private static int fieldAccess(byte[] classFile) {
    var access = new int[1];
    new ClassReader(classFile).accept(new ClassVisitor(Opcodes.ASM9) {
      @Override
      public FieldVisitor visitField(int fieldAccess, String name, String descriptor,
          String signature, Object value) {
        access[0] = fieldAccess;
        return null;
      }
    }, 0);
    return access[0];
  }

  private static void write(Path jar, Map<String, byte[]> entries) throws IOException {
    try (var out = new ZipOutputStream(Files.newOutputStream(jar))) {
      for (var entry : entries.entrySet()) {
        out.putNextEntry(new ZipEntry(entry.getKey()));
        out.write(entry.getValue());
        out.closeEntry();
      }
    }
  }

  private static Map<String, byte[]> read(Path jar) throws IOException {
    var entries = new HashMap<String, byte[]>();
    try (var in = new ZipInputStream(Files.newInputStream(jar))) {
      for (ZipEntry entry; (entry = in.getNextEntry()) != null; ) {
        entries.put(entry.getName(), in.readAllBytes());
      }
    }
    return entries;
  }
}

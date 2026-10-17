package io.github.shreyashsaitwal.rush.relocator;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.objectweb.asm.Opcodes.ACC_PUBLIC;
import static org.objectweb.asm.Opcodes.ACC_STATIC;
import static org.objectweb.asm.Opcodes.ARETURN;
import static org.objectweb.asm.Opcodes.GETSTATIC;
import static org.objectweb.asm.Opcodes.V1_8;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;
import java.util.zip.ZipOutputStream;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.objectweb.asm.ClassReader;
import org.objectweb.asm.ClassVisitor;
import org.objectweb.asm.ClassWriter;
import org.objectweb.asm.MethodVisitor;
import org.objectweb.asm.Opcodes;

class RelocatorTest {
  private static final String PREFIX = "com/example/repacked/";

  @TempDir Path dir;

  @Test
  void movesListedClassesAndTheirReferences() throws IOException {
    var relocated = relocate(
        Map.of("lib/Widget.class", widgetUser("lib/Widget", "lib/R$id", "label", "")),
        "prefix " + PREFIX, "class lib/Widget");

    assertEquals(List.of(PREFIX + "lib/Widget.class"), new ArrayList<>(relocated.keySet()));
    assertEquals(List.of(PREFIX + "lib/Widget", "lib/R$id"), references(relocated.get(PREFIX + "lib/Widget.class")).owners);
  }

  @Test
  void renamesListedFieldsOfTheirOwner() throws IOException {
    var relocated = relocate(
        Map.of("lib/Widget.class", widgetUser("lib/Widget", "lib/R$id", "label", "")),
        "prefix " + PREFIX, "class lib/R$id", "field lib/R$id label com_example_label");

    var references = references(relocated.get("lib/Widget.class"));
    assertEquals(List.of("lib/Widget", PREFIX + "lib/R$id"), references.owners);
    assertEquals(List.of("com_example_label"), references.fields);
  }

  @Test
  void rewritesClassNameStringsExceptKeptOnes() throws IOException {
    var renamed = relocate(
        Map.of("lib/Widget.class", widgetUser("lib/Widget", "lib/R$id", "label", "lib.Service")),
        "prefix " + PREFIX, "class lib/Service");
    var kept = relocate(
        Map.of("lib/Widget.class", widgetUser("lib/Widget", "lib/R$id", "label", "lib.Service")),
        "prefix " + PREFIX, "class lib/Service", "keep-string lib.Service");

    assertEquals(List.of("com.example.repacked.lib.Service"), references(renamed.get("lib/Widget.class")).strings);
    assertEquals(List.of("lib.Service"), references(kept.get("lib/Widget.class")).strings);
  }

  @Test
  void renamesServiceFilesAndTheirProviders() throws IOException {
    var relocated = relocate(
        Map.of("META-INF/services/lib.Plugin", "# providers\nlib.DefaultPlugin\nother.Plugin\n".getBytes(StandardCharsets.UTF_8)),
        "prefix " + PREFIX, "class lib/Plugin", "class lib/DefaultPlugin");

    assertEquals(
        "# providers\ncom.example.repacked.lib.DefaultPlugin\nother.Plugin\n",
        new String(relocated.get("META-INF/services/com.example.repacked.lib.Plugin"), StandardCharsets.UTF_8));
  }

  @Test
  void rejectsUnknownDirectives() {
    assertThrows(IllegalArgumentException.class, () -> RelocationSpec.parse(List.of("rename lib/Widget")));
  }

  private Map<String, byte[]> relocate(Map<String, byte[]> entries, String... spec) throws IOException {
    Path input = dir.resolve("in.jar");
    Path output = dir.resolve("out.jar");
    try (var out = new ZipOutputStream(Files.newOutputStream(input))) {
      for (var entry : entries.entrySet()) {
        out.putNextEntry(new ZipEntry(entry.getKey()));
        out.write(entry.getValue());
        out.closeEntry();
      }
    }
    new Relocator(RelocationSpec.parse(List.of(spec))).relocate(input, output);
    var relocated = new TreeMap<String, byte[]>();
    try (var in = new ZipInputStream(Files.newInputStream(output))) {
      for (ZipEntry entry; (entry = in.getNextEntry()) != null; ) {
        relocated.put(entry.getName(), in.readAllBytes());
      }
    }
    return relocated;
  }

  private static byte[] widgetUser(String name, String rOwner, String rField, String constant) {
    var writer = new ClassWriter(ClassWriter.COMPUTE_MAXS);
    writer.visit(V1_8, ACC_PUBLIC, name, null, "java/lang/Object", null);
    MethodVisitor method = writer.visitMethod(ACC_PUBLIC | ACC_STATIC, "use", "()Ljava/lang/Object;", null, null);
    method.visitCode();
    method.visitFieldInsn(GETSTATIC, rOwner, rField, "I");
    method.visitInsn(Opcodes.POP);
    method.visitLdcInsn(constant);
    method.visitInsn(ARETURN);
    method.visitMaxs(0, 0);
    method.visitEnd();
    writer.visitEnd();
    return writer.toByteArray();
  }

  private static References references(byte[] bytes) {
    var references = new References();
    new ClassReader(bytes).accept(new ClassVisitor(Opcodes.ASM9) {
      @Override
      public void visit(int version, int access, String name, String signature, String superName, String[] interfaces) {
        references.owners.add(name);
      }

      @Override
      public MethodVisitor visitMethod(int access, String name, String descriptor, String signature, String[] exceptions) {
        return new MethodVisitor(Opcodes.ASM9) {
          @Override
          public void visitFieldInsn(int opcode, String owner, String field, String fieldDescriptor) {
            references.owners.add(owner);
            references.fields.add(field);
          }

          @Override
          public void visitLdcInsn(Object value) {
            if (value instanceof String string && !string.isEmpty()) {
              references.strings.add(string);
            }
          }
        };
      }
    }, 0);
    return references;
  }

  private static final class References {
    final List<String> owners = new ArrayList<>();
    final List<String> fields = new ArrayList<>();
    final List<String> strings = new ArrayList<>();
  }
}

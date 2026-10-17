package io.github.shreyashsaitwal.rush.relocator;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;
import java.util.zip.ZipOutputStream;
import org.objectweb.asm.ClassReader;
import org.objectweb.asm.ClassVisitor;
import org.objectweb.asm.ClassWriter;
import org.objectweb.asm.FieldVisitor;
import org.objectweb.asm.Opcodes;

public final class DesugaredInterfaces {
  private static final String INIT_TRIGGER = "$desugar$clinit";
  private static final int INTERFACE_FIELD = Opcodes.ACC_PUBLIC | Opcodes.ACC_STATIC | Opcodes.ACC_FINAL;

  private DesugaredInterfaces() {}

  static void fix(Path input, Path output) throws IOException {
    try (var in = new ZipInputStream(Files.newInputStream(input));
        var out = new ZipOutputStream(Files.newOutputStream(output))) {
      for (ZipEntry entry; (entry = in.getNextEntry()) != null; ) {
        if (entry.isDirectory()) {
          continue;
        }
        byte[] content = in.readAllBytes();
        var fixed = new ZipEntry(entry.getName());
        fixed.setTime(entry.getTime());
        out.putNextEntry(fixed);
        out.write(entry.getName().endsWith(".class") ? withValidInitTriggers(content) : content);
        out.closeEntry();
      }
    }
  }

  private static byte[] withValidInitTriggers(byte[] content) {
    var reader = new ClassReader(content);
    if ((reader.getAccess() & Opcodes.ACC_INTERFACE) == 0 || !hasInitTrigger(reader)) {
      return content;
    }
    var writer = new ClassWriter(0);
    reader.accept(new ClassVisitor(Opcodes.ASM9, writer) {
      @Override
      public FieldVisitor visitField(int access, String name, String descriptor, String signature,
          Object value) {
        return super.visitField(isInitTrigger(access, name) ? access | INTERFACE_FIELD : access,
            name, descriptor, signature, value);
      }
    }, 0);
    return writer.toByteArray();
  }

  private static boolean hasInitTrigger(ClassReader reader) {
    var found = new boolean[1];
    reader.accept(new ClassVisitor(Opcodes.ASM9) {
      @Override
      public FieldVisitor visitField(int access, String name, String descriptor, String signature,
          Object value) {
        found[0] |= isInitTrigger(access, name);
        return null;
      }
    }, ClassReader.SKIP_CODE | ClassReader.SKIP_DEBUG | ClassReader.SKIP_FRAMES);
    return found[0];
  }

  private static boolean isInitTrigger(int access, String name) {
    return (access & Opcodes.ACC_SYNTHETIC) != 0 && name.startsWith(INIT_TRIGGER);
  }

  public static void main(String[] args) throws IOException {
    if (args.length != 2) {
      System.err.println("usage: desugared-interfaces <input.jar> <output.jar>");
      System.exit(2);
    }
    fix(Path.of(args[0]), Path.of(args[1]));
  }
}

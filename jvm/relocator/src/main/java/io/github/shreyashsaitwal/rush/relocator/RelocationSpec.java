package io.github.shreyashsaitwal.rush.relocator;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

record RelocationSpec(String prefix, Set<String> classes, Map<String, String> fields, Set<String> keptStrings) {

  static RelocationSpec read(Path spec) throws IOException {
    return parse(Files.readAllLines(spec));
  }

  static RelocationSpec parse(List<String> lines) {
    String prefix = "";
    var classes = new HashSet<String>();
    var fields = new HashMap<String, String>();
    var keptStrings = new HashSet<String>();
    for (String line : lines) {
      if (line.isBlank()) {
        continue;
      }
      String[] parts = line.split(" ", 2);
      String value = parts.length == 2 ? parts[1] : "";
      switch (parts[0]) {
        case "prefix" -> prefix = value;
        case "class" -> classes.add(value);
        case "field" -> {
          String[] field = value.split(" ");
          if (field.length != 3) {
            throw new IllegalArgumentException("Expected `field <owner> <name> <new name>`: " + line);
          }
          fields.put(fieldKey(field[0], field[1]), field[2]);
        }
        case "keep-string" -> keptStrings.add(value);
        default -> throw new IllegalArgumentException("Unknown relocation directive: " + line);
      }
    }
    return new RelocationSpec(prefix, Set.copyOf(classes), Map.copyOf(fields), Set.copyOf(keptStrings));
  }

  static String fieldKey(String owner, String name) {
    return owner + "." + name;
  }
}

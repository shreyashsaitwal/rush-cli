String listed(List<String> items) => items.length == 1
    ? items.single
    : '${items.take(items.length - 1).join(', ')} and ${items.last}';

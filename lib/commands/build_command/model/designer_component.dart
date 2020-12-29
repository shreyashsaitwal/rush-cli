class DesignerComponent {
  int version;
  String versionName;
  int minSdk;
  bool nonVisible;
  String desc;
  String iconName;
  String category;
  String helpUrl;
  String dateBuilt;
  // String license;

  DesignerComponent(
      {this.version,
      this.versionName,
      this.minSdk,
      this.nonVisible,
      this.desc,
      this.iconName,
      this.category,
      this.helpUrl,
      // this.license,
      this.dateBuilt,});

  @override
  String toString() { // TODO: Add: , license="${license ?? ''}"
    return '@DesignerComponent(version=${version}, versionName="${versionName ?? ''}", androidMinSdk=${minSdk}, nonVisible=${nonVisible ?? true}, description="${desc ?? ''}", iconName="${iconName ?? ''}", category=${category ?? 'ComponentCategory.UNINITIALIZED'}, helpUrl="${helpUrl ?? ''}", dateBuilt="${dateBuilt ?? ''}")';
  }
}

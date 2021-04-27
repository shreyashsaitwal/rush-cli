class DownloadData {
  final List<DataObject> _data = [];

  List<DataObject> get data => _data;

  DownloadData.fromJson(List json) {
    json.forEach((element) {
      _data.add(DataObject.fromJson(element as Map<String, dynamic>));
    });
  }
}

class DataObject {
  final String _name;
  final String _path;
  final String _url;

  DataObject(this._name, this._url, this._path);

  String get name => _name;
  String get url => _url;
  String get path => _path;

  DataObject.fromJson(Map<String, dynamic> json)
      : _name = json['name'],
        _url = json['url'],
        _path = json['path'];

  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{};
    data['name'] = _name;
    data['url'] = _url;
    data['path'] = _path;
    return data;
  }
}

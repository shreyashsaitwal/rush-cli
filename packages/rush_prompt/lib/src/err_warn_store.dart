class ErrWarnStore {
  factory ErrWarnStore() {
    return _store;
  }

  static final ErrWarnStore _store = ErrWarnStore._internal();

  ErrWarnStore._internal();

  var _errors = 0;
  int get getErrors => _errors;
  void incErrors() => _errors++;

  var _warnings = 0;
  int get getWarnings => _warnings;
  void incWarnings() => _warnings++;
}

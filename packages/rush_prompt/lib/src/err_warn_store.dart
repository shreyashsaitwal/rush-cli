class ErrWarnStore {
  ErrWarnStore._internal();

  static final ErrWarnStore _store = ErrWarnStore._internal();

  factory ErrWarnStore() {
    return _store;
  }

  var _errors = 0;
  int get getErrors => _errors;
  void incErrors([int? val]) {
    if (val != null) {
      _errors += val;
    } else {
      _errors++;
    }
  }

  var _warnings = 0;
  int get getWarnings => _warnings;
  void incWarnings([int? val]) {
    if (val != null) {
      _warnings += val;
    } else {
      _warnings++;
    }
  }
}

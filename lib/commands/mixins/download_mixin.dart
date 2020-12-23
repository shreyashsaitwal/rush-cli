import 'package:dio/dio.dart';
import 'package:rush_prompt/rush_prompt.dart';
import 'package:path/path.dart' as path;

mixin DownloadMixin {
  void download(ProgressBar progressBar, String downloadUrl,
      String packageDir) async {
    try {
      var prev = 0;
      await Dio().download(
        downloadUrl,
        path.join(packageDir, 'packages.zip'),
        deleteOnError: true,
        cancelToken: CancelToken(),
        onReceiveProgress: (count, total) {
          if (progressBar.totalProgress != null) {
            if (total != -1 && _isSignificantIncrease(total, count, prev)) {
              prev = count;
              progressBar.update(count);
            }
          } else {
            progressBar.totalProgress = total;
          }
        },
      );
    } catch (e) {
      ThrowError(message: e.toString());
    }
  }

  bool _isSignificantIncrease(int total, int cur, int prev) {
    if (prev < 1) {
      return true;
    }
    var prevPer = (prev / total) * 100;
    var curPer = (cur / total) * 100;
    if ((curPer - prevPer) >= 1) {
      return true;
    }
    return false;
  }
}

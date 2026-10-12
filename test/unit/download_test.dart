import 'dart:async';
import 'dart:io';

import 'package:rush/src/utils/download.dart';
import 'package:test/test.dart';

void main() {
  late HttpServer server;

  Future<Uri> serve(
      Future<void> Function(HttpResponse response) respond) async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) => respond(request.response..bufferOutput = false));
    return Uri.parse('http://${server.address.host}:${server.port}/');
  }

  tearDown(() => server.close(force: true));

  test('fails when the download stalls', () async {
    final url = await serve((response) async {
      response.contentLength = 10;
      response.add([1, 2, 3]);
      await response.flush();
    });

    await expectLater(
      download(url, stallTimeout: const Duration(milliseconds: 300)),
      throwsA(isA<TimeoutException>()
          .having((e) => e.message, 'message', contains('$url'))),
    );
  });

  test('keeps waiting for a slow download that makes progress', () async {
    final url = await serve((response) async {
      for (var i = 0; i < 5; i++) {
        response.add([i]);
        await response.flush();
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      await response.close();
    });

    final response =
        await download(url, stallTimeout: const Duration(milliseconds: 300));
    expect(response.bodyBytes, [0, 1, 2, 3, 4]);
  });
}

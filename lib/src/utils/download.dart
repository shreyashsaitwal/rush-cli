import 'dart:async';

import 'package:http/http.dart' as http;

Future<http.Response> download(
  Uri url, {
  Duration stallTimeout = const Duration(seconds: 30),
}) async {
  final client = http.Client();
  try {
    final response =
        await client.send(http.Request('GET', url)).timeout(stallTimeout);
    final body =
        await http.ByteStream(response.stream.timeout(stallTimeout)).toBytes();
    return http.Response.bytes(
      body,
      response.statusCode,
      reasonPhrase: response.reasonPhrase,
    );
  } on TimeoutException {
    throw TimeoutException('Downloading $url stalled', stallTimeout);
  } finally {
    client.close();
  }
}

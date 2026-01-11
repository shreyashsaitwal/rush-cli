import 'dart:typed_data';

import 'package:maven_resolver/maven_resolver.dart';
import 'package:test/test.dart';

void main() {
  group('ChecksumAlgorithm', () {
    test('sha1 computes correct hash', () {
      final data = Uint8List.fromList('hello world'.codeUnits);
      final hash = ChecksumAlgorithm.sha1.compute(data);
      expect(hash, '2aae6c35c94fcfb415dbe95f408b9ce91ee846ed');
    });

    test('md5 computes correct hash', () {
      final data = Uint8List.fromList('hello world'.codeUnits);
      final hash = ChecksumAlgorithm.md5.compute(data);
      expect(hash, '5eb63bbbe01eeed093cb22bb8f5acdc3');
    });

    test('sha256 computes correct hash', () {
      final data = Uint8List.fromList('hello world'.codeUnits);
      final hash = ChecksumAlgorithm.sha256.compute(data);
      expect(
        hash,
        'b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9',
      );
    });
  });

  group('ChecksumVerifier', () {
    late ChecksumVerifier verifier;

    setUp(() {
      verifier = const ChecksumVerifier();
    });

    test('verify returns ChecksumValid when hash matches', () async {
      final content = Uint8List.fromList('hello world'.codeUnits);
      const sha1Hash = '2aae6c35c94fcfb415dbe95f408b9ce91ee846ed';

      final result = await verifier.verify(
        content: content,
        basePath: 'test/file.jar',
        fetchChecksum: (path) async {
          if (path == 'test/file.jar.sha1') {
            return FetchResult(
              content: Uint8List.fromList(sha1Hash.codeUnits),
            );
          }
          return null;
        },
      );

      expect(result, isA<ChecksumValid>());
      final valid = result as ChecksumValid;
      expect(valid.algorithm, ChecksumAlgorithm.sha1);
      expect(valid.checksum, sha1Hash);
    });

    test('verify returns ChecksumInvalid when hash mismatches', () async {
      final content = Uint8List.fromList('hello world'.codeUnits);
      const wrongHash = 'wrong_hash_value';

      final result = await verifier.verify(
        content: content,
        basePath: 'test/file.jar',
        fetchChecksum: (path) async {
          if (path == 'test/file.jar.sha1') {
            return FetchResult(
              content: Uint8List.fromList(wrongHash.codeUnits),
            );
          }
          return null;
        },
      );

      expect(result, isA<ChecksumInvalid>());
      final invalid = result as ChecksumInvalid;
      expect(invalid.expected, wrongHash);
      expect(invalid.actual, isNot(wrongHash));
    });

    test('verify returns ChecksumMissing when no checksum file exists',
        () async {
      final content = Uint8List.fromList('hello world'.codeUnits);

      final result = await verifier.verify(
        content: content,
        basePath: 'test/file.jar',
        fetchChecksum: (path) async => null,
      );

      expect(result, isA<ChecksumMissing>());
    });

    test('verify handles checksum file with filename', () async {
      // Some checksum files contain "hash  filename"
      final content = Uint8List.fromList('hello world'.codeUnits);
      const sha1Hash = '2aae6c35c94fcfb415dbe95f408b9ce91ee846ed';
      const checksumWithFilename = '$sha1Hash  file.jar';

      final result = await verifier.verify(
        content: content,
        basePath: 'test/file.jar',
        fetchChecksum: (path) async {
          if (path == 'test/file.jar.sha1') {
            return FetchResult(
              content: Uint8List.fromList(checksumWithFilename.codeUnits),
            );
          }
          return null;
        },
      );

      expect(result, isA<ChecksumValid>());
    });

    test('verify is case insensitive', () async {
      final content = Uint8List.fromList('hello world'.codeUnits);
      const sha1Hash = '2AAE6C35C94FCFB415DBE95F408B9CE91EE846ED'; // uppercase

      final result = await verifier.verify(
        content: content,
        basePath: 'test/file.jar',
        fetchChecksum: (path) async {
          if (path == 'test/file.jar.sha1') {
            return FetchResult(
              content: Uint8List.fromList(sha1Hash.codeUnits),
            );
          }
          return null;
        },
      );

      expect(result, isA<ChecksumValid>());
    });

    test('applyPolicy throws on ChecksumInvalid with fail policy', () {
      final content = Uint8List.fromList('test'.codeUnits);
      const result =
          ChecksumInvalid(ChecksumAlgorithm.sha1, 'expected', 'actual');

      expect(
        () => verifier.applyPolicy(
          content: content,
          result: result,
          policy: ChecksumPolicy.fail,
          path: 'test/file.jar',
          warn: (_) {},
        ),
        throwsA(isA<ChecksumVerificationException>()),
      );
    });

    test('applyPolicy returns content on ChecksumInvalid with warn policy', () {
      final content = Uint8List.fromList('test'.codeUnits);
      const result =
          ChecksumInvalid(ChecksumAlgorithm.sha1, 'expected', 'actual');
      var warned = false;

      final returned = verifier.applyPolicy(
        content: content,
        result: result,
        policy: ChecksumPolicy.warn,
        path: 'test/file.jar',
        warn: (_) => warned = true,
      );

      expect(returned, content);
      expect(warned, isTrue);
    });

    test('applyPolicy throws on ChecksumMissing with fail policy', () {
      final content = Uint8List.fromList('test'.codeUnits);
      const result = ChecksumMissing(ChecksumAlgorithm.values);

      expect(
        () => verifier.applyPolicy(
          content: content,
          result: result,
          policy: ChecksumPolicy.fail,
          path: 'test/file.jar',
          warn: (_) {},
        ),
        throwsA(isA<ChecksumMissingException>()),
      );
    });
  });
}

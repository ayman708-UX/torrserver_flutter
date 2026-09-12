import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:torrserver_flutter/torrserver_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BinaryLocator', () {
    test(
        'throws TorrServerBinaryNotFoundException for non-existent custom path',
        () async {
      expect(
        () => BinaryLocator.locateBinary(
            customBinaryPath: '/non/existent/path/to/torrserver'),
        throwsA(isA<TorrServerBinaryNotFoundException>()),
      );
    });

    test('successfully resolves existing custom binary path', () async {
      final tempDir = await Directory.systemTemp.createTemp('ts_test_');
      final dummyBin = File('${tempDir.path}/torrserver.dummy');
      await dummyBin.writeAsString('dummy binary content');

      final resolved =
          await BinaryLocator.locateBinary(customBinaryPath: dummyBin.path);
      expect(resolved, isNotEmpty);
      expect(File(resolved).existsSync(), isTrue);

      await tempDir.delete(recursive: true);
    });

    test('successfully resolves TorrServer-darwin-arm64 candidate in directory',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('ts_mac_test_');
      final macBin = File('${tempDir.path}/TorrServer-darwin-arm64');
      await macBin.writeAsString('binary mock');

      // Test custom path resolution
      final resolved =
          await BinaryLocator.locateBinary(customBinaryPath: macBin.path);
      expect(resolved, equals(macBin.path));

      await tempDir.delete(recursive: true);
    });
  });
}

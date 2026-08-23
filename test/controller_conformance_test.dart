import 'package:flutter_test/flutter_test.dart';
import 'package:torrserver_flutter/src/torrserver_controller_ios.dart';
import 'package:torrserver_flutter/src/torrserver_controller_subprocess.dart';
import 'package:torrserver_flutter/torrserver_flutter.dart';

void main() {
  group('Controller Interface Conformance', () {
    test(
        'createTorrServerController factory produces valid controller instance',
        () {
      final controller = createTorrServerController();
      expect(controller, isA<TorrServerController>());
      expect(controller.isRunning, isFalse);
      expect(controller.baseUrl, isNull);
    });

    test(
        'TorrServerControllerSubprocess throws when calling methods before start',
        () async {
      final controller = TorrServerControllerSubprocess();

      expect(controller.isRunning, isFalse);
      expect(controller.baseUrl, isNull);

      expect(() => controller.listTorrents(),
          throwsA(isA<TorrServerProcessException>()));
      expect(() => controller.getSettings(),
          throwsA(isA<TorrServerProcessException>()));
      expect(() => controller.streamUrl('hash'),
          throwsA(isA<TorrServerProcessException>()));
    });

    test('TorrServerControllerIos throws when calling methods before start',
        () async {
      final controller = TorrServerControllerIos();

      expect(controller.isRunning, isFalse);
      expect(controller.baseUrl, isNull);

      expect(() => controller.listTorrents(),
          throwsA(isA<TorrServerFfiException>()));
      expect(() => controller.getSettings(),
          throwsA(isA<TorrServerFfiException>()));
      expect(() => controller.streamUrl('hash'),
          throwsA(isA<TorrServerFfiException>()));
    });
  });
}

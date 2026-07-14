import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_connectivity_garmin/watch_connectivity_garmin.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const methodChannel = MethodChannel('watch_connectivity_garmin/methods');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, (call) async {
          calls.add(call);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, null);
  });

  test('initialize includes additional application ids', () async {
    final watch = WatchConnectivityGarmin();

    await watch.initialize(
      const GarminInitializationOptions(
        applicationId: 'primary',
        additionalApplicationIds: ['data-field'],
        urlScheme: 'test',
      ),
    );

    expect(calls.single.method, 'initialize');
    expect(
      calls.single.arguments,
      containsPair('additionalApplicationIds', ['data-field']),
    );
  });

  test('targeted send includes application id and original message', () async {
    final watch = WatchConnectivityGarmin();
    final payload = <String, dynamic>{'type': 'request'};

    await watch.sendMessageToApplication('data-field', payload);

    expect(calls.single.method, 'sendMessageToApplication');
    expect(calls.single.arguments, {
      'applicationId': 'data-field',
      'message': payload,
    });
  });

  test('application message retains source id and payload', () {
    final event = GarminApplicationMessage.fromMap(const {
      'applicationId': 'data-field',
      'message': {'type': 'request'},
    });

    expect(event.applicationId, 'data-field');
    expect(event.message, const {'type': 'request'});
  });
}

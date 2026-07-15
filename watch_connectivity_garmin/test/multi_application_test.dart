import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_connectivity_garmin/watch_connectivity_garmin.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const methodChannel = MethodChannel('watch_connectivity_garmin/methods');
  const connectionChannel =
      MethodChannel('watch_connectivity_garmin/device_connections');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, (call) async {
      calls.add(call);
      return null;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(connectionChannel, (_) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(connectionChannel, null);
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

  test('device connection stream exposes native connection changes', () async {
    final watch = WatchConnectivityGarmin();
    final connected = expectLater(watch.deviceConnectionStream, emits(true));

    await Future<void>.delayed(Duration.zero);
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      'watch_connectivity_garmin/device_connections',
      const StandardMethodCodec().encodeSuccessEnvelope(true),
      (_) {},
    );

    await connected;
  });
}

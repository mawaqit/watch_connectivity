import 'package:flutter/services.dart';
import 'package:meta/meta.dart';
import 'package:watch_connectivity_garmin/watch_connectivity_garmin.dart';

/// A Garmin message together with the Connect IQ application that sent it.
@immutable
class GarminApplicationMessage {
  /// Source Connect IQ application id
  final String applicationId;

  /// Message payload
  final Map<String, dynamic> message;

  /// Constructor
  const GarminApplicationMessage({
    required this.applicationId,
    required this.message,
  });

  /// Create an event from the platform channel envelope.
  factory GarminApplicationMessage.fromMap(Map<dynamic, dynamic> value) {
    return GarminApplicationMessage(
      applicationId: value['applicationId'] as String,
      message: Map<String, dynamic>.from(value['message'] as Map),
    );
  }
}

/// Plugin to communicate with Garmin watches
class WatchConnectivityGarmin extends WatchConnectivityBase {
  final _applicationMessageChannel = const EventChannel(
    'watch_connectivity_garmin/application_messages',
  );

  @override
  Stream<Map<String, dynamic>> get contextStream =>
      throw UnsupportedError('Unsupported by Garmin watches');

  /// Constructor
  WatchConnectivityGarmin() : super(pluginName: 'watch_connectivity_garmin');

  /// Messages received from any registered Connect IQ application.
  late final Stream<GarminApplicationMessage> applicationMessageStream =
      _applicationMessageChannel
          .receiveBroadcastStream(
            'applicationMessages-${identityHashCode(this)}',
          )
          .map((event) => GarminApplicationMessage.fromMap(event as Map));

  /// Initialize the platform SDK
  Future<void> initialize(GarminInitializationOptions options) {
    return methodChannel.invokeMethod('initialize', options.toJson());
  }

  /// Send [message] to a specific registered Connect IQ application.
  Future<void> sendMessageToApplication(
    String applicationId,
    Map<String, dynamic> message,
  ) {
    return methodChannel.invokeMethod('sendMessageToApplication', {
      'applicationId': applicationId,
      'message': message,
    });
  }

  /// Launches Garmin Connect Mobile for the purpose of retrieving a list of
  /// ConnectIQ-compatible devices. Note that by launching GCM, this method
  /// causes the companion app to go into the background, possibly resulting in
  /// the app being suspended. The companion app should expect to be suspended
  /// when calling this method.
  ///
  /// Returned devices are cached natively in UserDefaults
  ///
  /// iOS only
  Future<void> showDeviceSelection() {
    return methodChannel.invokeMethod('showDeviceSelection');
  }

  /// If the Garmin Connect app is installed
  @override
  Future<bool> get isSupported => super.isSupported;

  /// If the companion app is installed on any accessible watches
  @override
  Future<bool> get isReachable => super.isReachable;

  @override
  Future<Map<String, dynamic>> get applicationContext =>
      throw UnsupportedError('Unsupported by Garmin watches');

  @override
  Future<List<Map<String, dynamic>>> get receivedApplicationContexts =>
      throw UnsupportedError('Unsupported by Garmin watches');

  @override
  Future<void> updateApplicationContext(Map<String, dynamic> context) =>
      throw UnsupportedError('Unsupported by Garmin watches');
}

import 'package:recase/recase.dart';
import 'package:meta/meta.dart';

/// Initialization options for the Garmin SDK

@immutable
class GarminInitializationOptions {
  /// The id of the companion application to communicate with
  final String applicationId;

  /// Other Connect IQ application ids to register alongside [applicationId]
  final List<String> additionalApplicationIds;

  /// URL scheme of the iOS companion application
  final String urlScheme;

  /// Show UI to help the user resolve issues with Garmin Connect
  final bool autoUI;

  /// IQConnectType for connection type
  ///
  /// Android only
  final GarminIqConnectionType connectType;

  /// ADB Port for connection in tethered mode
  ///
  /// Android only
  final int adbPort;

  /// Constructor
  const GarminInitializationOptions({
    required this.applicationId,
    this.additionalApplicationIds = const [],
    required this.urlScheme,
    this.autoUI = false,
    this.connectType = GarminIqConnectionType.wireless,
    this.adbPort = 7381,
  });

  /// Convert to JSON
  Map<String, dynamic> toJson() => {
    'applicationId': applicationId,
    'additionalApplicationIds': additionalApplicationIds,
    'urlScheme': urlScheme,
    'autoUI': autoUI,
    'connectType': connectType.name.constantCase,
    'adbPort': adbPort,
  };
}

/// Enum for type of Garmin connection to establish
enum GarminIqConnectionType {
  /// Tethered connection
  tethered,

  /// Wireless connection
  wireless,
}

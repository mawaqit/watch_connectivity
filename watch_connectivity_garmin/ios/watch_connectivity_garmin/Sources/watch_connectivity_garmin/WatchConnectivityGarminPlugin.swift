import ConnectIQ
import Flutter
import UIKit

public class WatchConnectivityGarminPlugin: NSObject, FlutterPlugin, IQDeviceEventDelegate, IQAppMessageDelegate {
  private static let deviceIdsKey = "watch_connectivity_garmin/deviceIds"
  private static let appStatusTimeout: TimeInterval = 10
  private static let sendMessageTimeout: TimeInterval = 60

  let connectIQ = ConnectIQ.sharedInstance()!
  let defaults = UserDefaults.standard
  let messageHandler = StreamHandler()
  let applicationMessageHandler = StreamHandler()
  let deviceConnectionHandler = StreamHandler()
  let contextHandler = StreamHandler()
  var applicationId: String?
  var applicationIds = [String]()
  var urlScheme: String?

  init(messageChannel: FlutterEventChannel, applicationMessageChannel: FlutterEventChannel, deviceConnectionChannel: FlutterEventChannel, contextChannel: FlutterEventChannel) {
    messageChannel.setStreamHandler(messageHandler)
    applicationMessageChannel.setStreamHandler(applicationMessageHandler)
    deviceConnectionChannel.setStreamHandler(deviceConnectionHandler)
    contextChannel.setStreamHandler(contextHandler)

    super.init()
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let methodChannel = FlutterMethodChannel(name: "watch_connectivity_garmin/methods", binaryMessenger: registrar.messenger())
    let messageChannel = FlutterEventChannel(name: "watch_connectivity_garmin/messages", binaryMessenger: registrar.messenger())
    let applicationMessageChannel = FlutterEventChannel(name: "watch_connectivity_garmin/application_messages", binaryMessenger: registrar.messenger())
    let deviceConnectionChannel = FlutterEventChannel(name: "watch_connectivity_garmin/device_connections", binaryMessenger: registrar.messenger())
    let contextChannel = FlutterEventChannel(name: "watch_connectivity_garmin/context", binaryMessenger: registrar.messenger())
    let instance = WatchConnectivityGarminPlugin(messageChannel: messageChannel, applicationMessageChannel: applicationMessageChannel, deviceConnectionChannel: deviceConnectionChannel, contextChannel: contextChannel)
    registrar.addMethodCallDelegate(instance, channel: methodChannel)
    registrar.addApplicationDelegate(instance)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    // Getters
    case "isSupported":
      isSupported(result)
    case "isPaired":
      isPaired(result)
    case "isReachable":
      isReachable(result)
    // Methods
    case "initialize":
      initialize(call, result)
    case "showDeviceSelection":
      showDeviceSelection(result)
    case "sendMessage":
      sendMessage(call, result)
    case "sendMessageToApplication":
      sendMessageToApplication(call, result)
    // Not implemented
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  public func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    guard url.scheme == urlScheme else {
      return false
    }

    let devices = connectIQ.parseDeviceSelectionResponse(from: url) as? [IQDevice]
    guard devices != nil else {
      return false
    }

    defaults.set(devices!.map { $0.uuid.uuidString }, forKey: Self.deviceIdsKey)
    registerForEvents()

    return true
  }

  private func getCachedDevices() -> [IQDevice] {
    return defaults.stringArray(forKey: Self.deviceIdsKey)?.compactMap {
      guard let uuid = UUID(uuidString: $0) else { return nil }
      return IQDevice(id: uuid, modelName: "", friendlyName: "")
    } ?? []
  }

  private func createApps(applicationId targetApplicationId: String? = nil) -> [IQApp] {
    let targetIds = targetApplicationId.map { [$0] } ?? applicationIds
    return getCachedDevices().flatMap { device in
      targetIds.map { IQApp(uuid: UUID(uuidString: $0)!, store: UUID(), device: device) }
    }
  }

  private func registerForEvents() {
    connectIQ.unregister(forAllAppMessages: self)
    connectIQ.unregister(forAllDeviceEvents: self)

    let apps = createApps()
    for app in apps {
      connectIQ.register(forDeviceEvents: app.device, delegate: self)
      connectIQ.register(forAppMessages: app, delegate: self)
    }
  }

  private func initialize(_ call: FlutterMethodCall, _ result: FlutterResult) {
    let args = call.arguments as! [String: Any]
    applicationId = args["applicationId"] as? String
    let additionalApplicationIds = args["additionalApplicationIds"] as? [String] ?? []
    applicationIds = [applicationId!]
    for id in additionalApplicationIds where !applicationIds.contains(id) {
      applicationIds.append(id)
    }
    urlScheme = args["urlScheme"] as? String

    let autoUI = args["autoUI"] as? Bool ?? false

    connectIQ.initialize(withUrlScheme: urlScheme, uiOverrideDelegate: autoUI ? nil : IQUIOverrideDelegateStub())

    registerForEvents()

    result(nil)
  }

  private func showDeviceSelection(_ result: FlutterResult) {
    connectIQ.showDeviceSelection()
    result(nil)
  }

  private func isSupported(_ result: FlutterResult) {
    result(UIApplication.shared.canOpenURL(URL(string: "gcm-ciq://stub")!))
  }

  private func isPaired(_ result: FlutterResult) {
    result(getCachedDevices().isEmpty == false)
  }

  private func isReachable(_ result: @escaping FlutterResult) {
    Task { @MainActor in await isReachableAsync(result) }
  }

  @MainActor
  private func isReachableAsync(_ result: FlutterResult) async {
    let apps = createApps(applicationId: applicationId)
    for app in apps {
      let installed = await awaitFirstCallback(timeout: Self.appStatusTimeout, fallback: false) { done in
        connectIQ.getAppStatus(app) { status in
          done(status?.isInstalled == true)
        }
      }
      if installed {
        result(true)
        return
      }
    }

    result(false)
  }

  private func sendMessage(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    Task { @MainActor in await sendMessageAsync(applicationId: applicationId, message: call.arguments, result) }
  }

  private func sendMessageToApplication(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as! [String: Any]
    let targetApplicationId = args["applicationId"] as? String
    guard let targetApplicationId, applicationIds.contains(targetApplicationId) else {
      result(FlutterError(code: "Unknown application", message: nil, details: targetApplicationId))
      return
    }

    Task { @MainActor in await sendMessageAsync(applicationId: targetApplicationId, message: args["message"], result) }
  }

  @MainActor
  private func sendMessageAsync(applicationId targetApplicationId: String?, message: Any?, _ result: FlutterResult) async {
    guard let targetApplicationId else {
      result(FlutterError(code: "Not Initialized", message: nil, details: nil))
      return
    }

    let connectedApps = createApps(applicationId: targetApplicationId).filter { connectIQ.getDeviceStatus($0.device) == .connected }

    guard !connectedApps.isEmpty else {
      result(FlutterError(code: "No connected devices", message: nil, details: nil))
      return
    }

    var errors = [String]()
    for app in connectedApps {
      let sendResult = await awaitFirstCallback(timeout: Self.sendMessageTimeout, fallback: IQSendMessageResult?.none) { done in
        connectIQ.sendMessage(message, to: app, progress: { _, _ in }) { result in
          done(result)
        }
      }
      if let sendResult {
        if sendResult != .success {
          errors.append("\(sendResult)")
        }
      } else {
        errors.append("timeout")
      }
    }

    if errors.isEmpty {
      result(nil)
    } else {
      result(FlutterError(code: "Error sending message", message: errors.joined(separator: ", "), details: nil))
    }
  }

  /// Waits for a Connect IQ completion block and returns its first value.
  ///
  /// The Connect IQ iOS SDK can call a completion block more than once (for example once from its
  /// own timeout and again when the late reply arrives). Resuming a continuation twice is a fatal
  /// error, so later calls are ignored. If the SDK never calls back, `fallback` is returned after
  /// `timeout` seconds. Runs on the main actor because the SDK is not thread-safe.
  @MainActor
  private func awaitFirstCallback<T>(
    timeout: TimeInterval,
    fallback: T,
    _ start: (@escaping (T) -> Void) -> Void
  ) async -> T {
    await withCheckedContinuation { continuation in
      let once = ResumeOnce(continuation)
      DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
        once.resume(returning: fallback)
      }
      start { value in
        once.resume(returning: value)
      }
    }
  }

  public func deviceStatusChanged(_ device: IQDevice!, status: IQDeviceStatus) {
    deviceConnectionHandler.success(status == .connected)
  }

  public func receivedMessage(_ message: Any!, from app: IQApp!) {
    let sourceApplicationId = app.uuid.uuidString.lowercased()
    if sourceApplicationId == applicationId?.lowercased() {
      messageHandler.success(message)
    }
    applicationMessageHandler.success([
      "applicationId": sourceApplicationId,
      "message": message as Any,
    ])
  }
}

class IQUIOverrideDelegateStub: NSObject, IQUIOverrideDelegate {}

/// Resumes a continuation at most once; later calls are ignored. Thread-safe.
final class ResumeOnce<T> {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<T, Never>?

  init(_ continuation: CheckedContinuation<T, Never>) {
    self.continuation = continuation
  }

  func resume(returning value: T) {
    lock.lock()
    let pending = continuation
    continuation = nil
    lock.unlock()
    pending?.resume(returning: value)
  }
}

class StreamHandler: NSObject, FlutterStreamHandler {
  private var sinks: [String: FlutterEventSink] = [:]

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sinks[arguments as! String] = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    guard let id = arguments as? String else { return nil }
    sinks.removeValue(forKey: id)
    return nil
  }
  
  func success(_ event: Any?) {
    for sink in sinks.values {
      sink(event)
    }
  }
}

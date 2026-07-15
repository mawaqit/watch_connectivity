package dev.rexios.watch_connectivity_garmin

import android.content.Context
import android.content.pm.PackageManager
import com.garmin.android.connectiq.ConnectIQ
import com.garmin.android.connectiq.ConnectIQ.ConnectIQListener
import com.garmin.android.connectiq.ConnectIQ.IQApplicationInfoListener
import com.garmin.android.connectiq.ConnectIQ.IQConnectType
import com.garmin.android.connectiq.ConnectIQ.IQSdkErrorStatus
import com.garmin.android.connectiq.IQApp
import com.garmin.android.connectiq.IQDevice
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.util.concurrent.CountDownLatch
import kotlin.concurrent.thread


/** WatchConnectivityGarminPlugin */
class WatchConnectivityGarminPlugin : FlutterPlugin, MethodCallHandler {
    private val channelName = "watch_connectivity_garmin"

    val messageHandler = StreamHandler()
    val applicationMessageHandler = StreamHandler()
    val deviceConnectionHandler = StreamHandler()
    val contextHandler = StreamHandler()

    private lateinit var methodChannel: MethodChannel
    private lateinit var messageChannel: EventChannel
    private lateinit var applicationMessageChannel: EventChannel
    private lateinit var deviceConnectionChannel: EventChannel
    private lateinit var contextChannel: EventChannel
    private lateinit var context: Context
    private lateinit var packageManager: PackageManager
    private lateinit var connectIQ: ConnectIQ
    private lateinit var primaryIqApp: IQApp
    private val iqApps = linkedMapOf<String, IQApp>()

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel = MethodChannel(flutterPluginBinding.binaryMessenger, "$channelName/methods")
        messageChannel = EventChannel(flutterPluginBinding.binaryMessenger, "$channelName/messages")
        applicationMessageChannel = EventChannel(
            flutterPluginBinding.binaryMessenger,
            "$channelName/application_messages"
        )
        deviceConnectionChannel = EventChannel(
            flutterPluginBinding.binaryMessenger,
            "$channelName/device_connections"
        )
        contextChannel = EventChannel(flutterPluginBinding.binaryMessenger, "$channelName/context")

        methodChannel.setMethodCallHandler(this)
        messageChannel.setStreamHandler(messageHandler)
        applicationMessageChannel.setStreamHandler(applicationMessageHandler)
        deviceConnectionChannel.setStreamHandler(deviceConnectionHandler)
        contextChannel.setStreamHandler(contextHandler)

        context = flutterPluginBinding.applicationContext

        packageManager = context.packageManager
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        messageChannel.setStreamHandler(null)
        applicationMessageChannel.setStreamHandler(null)
        deviceConnectionChannel.setStreamHandler(null)
        contextChannel.setStreamHandler(null)
        connectIQ.shutdown(context)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            // Getters
            "isSupported" -> isSupported(result)
            "isPaired" -> isPaired(result)
            "isReachable" -> isReachable(result)

            // Methods
            "initialize" -> initialize(call, result)
            "sendMessage" -> sendMessage(call, result)
            "sendMessageToApplication" -> sendMessageToApplication(call, result)

            // Not implemented
            else -> result.notImplemented()
        }
    }

    private fun initialize(call: MethodCall, result: Result) {
        val applicationId = call.argument<String>("applicationId")!!
        val additionalApplicationIds =
            call.argument<List<String>>("additionalApplicationIds") ?: listOf()
        val applicationIds = listOf(applicationId).plus(additionalApplicationIds).distinct()
        iqApps.clear()
        for (id in applicationIds) {
            iqApps[id] = IQApp(id)
        }
        primaryIqApp = iqApps.getValue(applicationId)

        val connectTypeString = call.argument<String>("connectType")!!
        val connectType = IQConnectType.valueOf(connectTypeString)
        connectIQ = ConnectIQ.getInstance(context, connectType)
        connectIQ.initialize(
            context,
            call.argument<Boolean>("autoUI")!!,
            object : ConnectIQListener {
                override fun onSdkReady() {
                    listenForMessages()
                    result.success(null)
                }

                override fun onInitializeError(status: IQSdkErrorStatus?) {
                    result.error(status.toString(), "Unable to initialize Garmin SDK", null)
                }

                override fun onSdkShutDown() {}
            },
        )

        if (connectType == IQConnectType.TETHERED) {
            val adbPort = call.argument<Int>("adbPort")!!
            connectIQ.adbPort = adbPort
        }
    }

    private fun listenForMessages() {
        val devices = connectIQ.knownDevices ?: listOf()

        for (device in devices) {
            connectIQ.registerForDeviceEvents(device) { _, status ->
                processDeviceStatus(device, status)
            }
        }

        for (device in connectIQ.connectedDevices ?: listOf()) {
            processDeviceStatus(device, IQDevice.IQDeviceStatus.CONNECTED)
        }
    }

    private fun processDeviceStatus(device: IQDevice, status: IQDevice.IQDeviceStatus) {
        deviceConnectionHandler.success(status == IQDevice.IQDeviceStatus.CONNECTED)
        if (status == IQDevice.IQDeviceStatus.CONNECTED) {
            for ((applicationId, iqApp) in iqApps) {
                connectIQ.registerForAppEvents(device, iqApp) { _, _, data, messageStatus ->
                    if (messageStatus != ConnectIQ.IQMessageStatus.SUCCESS) {
                        return@registerForAppEvents
                    }
                    for (datum in data) {
                        if (applicationId == primaryIqApp.applicationId) {
                            messageHandler.success(datum)
                        }
                        applicationMessageHandler.success(
                            mapOf("applicationId" to applicationId, "message" to datum)
                        )
                    }
                }
            }
        } else {
            for (iqApp in iqApps.values) {
                connectIQ.unregisterForApplicationEvents(device, iqApp)
            }
        }
    }

    private fun getApplicationForDevice(device: IQDevice, iqApp: IQApp): IQApp? {
        var installedApp: IQApp? = null
        val latch = CountDownLatch(1)
        connectIQ.getApplicationInfo(
            iqApp.applicationId, device, object : IQApplicationInfoListener {
                override fun onApplicationInfoReceived(app: IQApp?) {
                    installedApp = app
                    latch.countDown()
                }

                override fun onApplicationNotInstalled(p0: String?) {
                    latch.countDown()
                }
            })
        latch.await()
        return installedApp
    }

    private fun isSupported(result: Result) {
        val apps = packageManager.getInstalledApplications(0)
        val wearableAppInstalled =
            apps.any { it.packageName == "com.garmin.android.apps.connectmobile" }
        result.success(wearableAppInstalled)
    }

    private fun isPaired(result: Result) {
        result.success(connectIQ.knownDevices?.isNotEmpty() ?: false)
    }

    private fun isReachable(result: Result) {
        thread {
            for (device in connectIQ.connectedDevices ?: listOf()) {
                val installedApp = getApplicationForDevice(device, primaryIqApp)
                if (installedApp != null) {
                    result.success(true)
                    return@thread
                }
            }
            result.success(false)
        }
    }


    private fun sendMessage(call: MethodCall, result: Result) {
        sendMessage(primaryIqApp, call.arguments, result)
    }

    private fun sendMessageToApplication(call: MethodCall, result: Result) {
        val applicationId = call.argument<String>("applicationId")!!
        val iqApp = iqApps[applicationId]
        if (iqApp == null) {
            result.error("Unknown application", "Application was not registered", applicationId)
            return
        }

        sendMessage(iqApp, call.argument<Any>("message"), result)
    }

    private fun sendMessage(iqApp: IQApp, message: Any?, result: Result) {
        val devices = connectIQ.connectedDevices ?: listOf()
        if (devices.isEmpty()) {
            result.error("No connected devices", "No Garmin device is connected", null)
            return
        }

        thread {
            val latch = CountDownLatch(devices.count())
            val errors = mutableListOf<ConnectIQ.IQMessageStatus>()
            for (device in devices) {
                connectIQ.sendMessage(device, iqApp, message) { _, _, status ->
                    if (status != ConnectIQ.IQMessageStatus.SUCCESS) {
                        errors.add(status)
                    }

                    latch.countDown()
                }
            }

            latch.await()
            if (errors.isNotEmpty()) {
                result.error(errors.toString(), "Unable to send message", null)
            } else {
                result.success(null)
            }
        }
    }
}

class StreamHandler : EventChannel.StreamHandler {
    val sinks = mutableMapOf<String, EventChannel.EventSink>()

    override fun onListen(
        arguments: Any?, events: EventChannel.EventSink?
    ) {
        sinks[arguments as String] = events!!
    }

    override fun onCancel(arguments: Any?) {
        val id = arguments as? String ?: return
        sinks.remove(id)
    }

    fun success(event: Any?) {
        for (sink in sinks.values) {
            sink.success(event)
        }
    }
}

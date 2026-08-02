package com.daralturab.dar_al_turab_pos

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "dar_al_turab/bluetooth"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "bondedDevices" -> bondedDevices(result)
                    else -> result.notImplemented()
                }
            }
    }

    // Enumerates paired devices with their Bluetooth major device class, so the
    // Flutter side can show printers (Imaging) and hide earbuds/phones. The
    // print_bluetooth_thermal plugin only exposes name + MAC, hence this.
    private fun bondedDevices(result: MethodChannel.Result) {
        try {
            val manager = getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
            val adapter: BluetoothAdapter? = manager?.adapter
            if (adapter == null) {
                result.error("NO_ADAPTER", "Bluetooth is not available", null)
                return
            }

            val devices = adapter.bondedDevices?.map { device ->
                mapOf(
                    "name" to (device.name ?: ""),
                    "address" to device.address,
                    "majorClass" to (device.bluetoothClass?.majorDeviceClass ?: -1),
                )
            } ?: emptyList()

            result.success(devices)
        } catch (e: SecurityException) {
            // BLUETOOTH_CONNECT not granted yet — the Dart side falls back to
            // the plugin's unfiltered list.
            result.error("PERMISSION", e.message, null)
        } catch (e: Exception) {
            result.error("BT_ERROR", e.message, null)
        }
    }
}

package com.daralturab.dar_al_turab_pos

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
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
                    "isBluetoothOn" -> isBluetoothOn(result)
                    "requestEnable" -> requestEnable(result)
                    "disable" -> disableBluetooth(result)
                    "openSettings" -> openBluetoothSettings(result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun adapter(): BluetoothAdapter? {
        val manager = getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        return manager?.adapter
    }

    // Enumerates paired devices with their Bluetooth major device class, so the
    // Flutter side can show printers (Imaging) and hide earbuds/phones. The
    // print_bluetooth_thermal plugin only exposes name + MAC, hence this.
    private fun bondedDevices(result: MethodChannel.Result) {
        try {
            val adapter = adapter()
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

    private fun isBluetoothOn(result: MethodChannel.Result) {
        val adapter = adapter()
        if (adapter == null) {
            result.success(false)
            return
        }
        try {
            result.success(adapter.isEnabled)
        } catch (e: SecurityException) {
            result.success(false)
        }
    }

    // Shows the system "Allow this app to turn on Bluetooth?" consent dialog.
    // This is the only reliable way to enable the adapter across Android
    // versions (BluetoothAdapter.enable() is a no-op on API 31+).
    private fun requestEnable(result: MethodChannel.Result) {
        val adapter = adapter()
        if (adapter == null) {
            result.error("NO_ADAPTER", "Bluetooth is not available", null)
            return
        }
        if (adapter.isEnabled) {
            result.success(true)
            return
        }
        try {
            startActivity(Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE))
            result.success(true)
        } catch (e: Exception) {
            result.error("ENABLE_FAILED", e.message, null)
        }
    }

    // Turning Bluetooth off programmatically is blocked from Android 13 (API 33)
    // onward, so this returns "unsupported" there and the Dart side falls back to
    // opening the system Bluetooth settings.
    private fun disableBluetooth(result: MethodChannel.Result) {
        val adapter = adapter()
        if (adapter == null) {
            result.error("NO_ADAPTER", "Bluetooth is not available", null)
            return
        }
        if (!adapter.isEnabled) {
            result.success("already_off")
            return
        }
        if (Build.VERSION.SDK_INT >= 33) {
            result.success("unsupported")
            return
        }
        try {
            @Suppress("DEPRECATION")
            val ok = adapter.disable()
            result.success(if (ok) "disabled" else "unsupported")
        } catch (e: SecurityException) {
            result.success("unsupported")
        } catch (e: Exception) {
            result.error("DISABLE_FAILED", e.message, null)
        }
    }

    private fun openBluetoothSettings(result: MethodChannel.Result) {
        try {
            startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS))
            result.success(true)
        } catch (e: Exception) {
            result.error("SETTINGS_FAILED", e.message, null)
        }
    }
}

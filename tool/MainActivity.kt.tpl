package __PACKAGE__

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.wifi.WifiManager
import android.os.Build
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var multicastLock: WifiManager.MulticastLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "hotspot_racers/native")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "prepare" -> {
                        val bind = call.argument<Boolean>("bindWifi") ?: false
                        result.success(prepare(bind))
                    }
                    "release" -> {
                        release()
                        result.success(true)
                    }
                    "getPref" -> {
                        val k = call.argument<String>("k") ?: ""
                        val v = getSharedPreferences("hr", Context.MODE_PRIVATE).getString(k, null)
                        result.success(v)
                    }
                    "setPref" -> {
                        val k = call.argument<String>("k") ?: ""
                        val v = call.argument<String>("v") ?: ""
                        getSharedPreferences("hr", Context.MODE_PRIVATE).edit().putString(k, v).apply()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun prepare(bindWifi: Boolean): Boolean {
        try {
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            if (multicastLock == null) {
                multicastLock = wm.createMulticastLock("hr-multicast")
                multicastLock?.setReferenceCounted(false)
            }
            if (multicastLock?.isHeld == false) {
                multicastLock?.acquire()
            }
            if (wifiLock == null) {
                val mode = if (Build.VERSION.SDK_INT >= 29) {
                    WifiManager.WIFI_MODE_FULL_LOW_LATENCY
                } else {
                    WifiManager.WIFI_MODE_FULL_HIGH_PERF
                }
                wifiLock = wm.createWifiLock(mode, "hr-wifi")
                wifiLock?.setReferenceCounted(false)
            }
            if (wifiLock?.isHeld == false) {
                wifiLock?.acquire()
            }
        } catch (e: Exception) {
        }
        var bound = false
        if (bindWifi) {
            try {
                val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                for (n in cm.allNetworks) {
                    val caps = cm.getNetworkCapabilities(n) ?: continue
                    if (caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) {
                        bound = cm.bindProcessToNetwork(n)
                        break
                    }
                }
            } catch (e: Exception) {
                bound = false
            }
        }
        return bound
    }

    private fun release() {
        try {
            if (multicastLock?.isHeld == true) {
                multicastLock?.release()
            }
            if (wifiLock?.isHeld == true) {
                wifiLock?.release()
            }
            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            cm.bindProcessToNetwork(null)
        } catch (e: Exception) {
        }
    }
}

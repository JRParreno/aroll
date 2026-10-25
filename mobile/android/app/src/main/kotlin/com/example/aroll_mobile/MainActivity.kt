package com.example.aroll_mobile

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.LocationManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.wifi.SupplicantState
import android.net.wifi.WifiInfo
import android.net.wifi.WifiManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "aroll/workplace_wifi",
        ).setMethodCallHandler { call, result ->
            if (call.method == "readConnected") {
                result.success(readConnectedAccessPoint())
            } else {
                result.notImplemented()
            }
        }
    }

    /**
     * Foreground read of the access point this phone is already joined to.
     * Does not scan nearby networks and does not connect or disconnect.
     */
    private fun readConnectedAccessPoint(): Map<String, String?> {
        return try {
            val fineLocation = checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION)
            if (fineLocation != PackageManager.PERMISSION_GRANTED) {
                return mapOf("status" to "permission_denied")
            }

            val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            if (!wifiManager.isWifiEnabled) {
                return mapOf("status" to "not_connected")
            }

            val connectivity = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            val observed = observeConnectedWifi(connectivity)
            @Suppress("DEPRECATION")
            val legacyInfo = wifiManager.connectionInfo
            val transportBssid = usableBssid(observed.info?.bssid)
            val legacyBssid = usableBssid(legacyInfo?.bssid)
            val associated = observed.transportPresent || legacyAssociated(legacyInfo)
            val chosen = if (transportBssid != null) observed.info else legacyInfo
            val bssid = when {
                transportBssid != null -> transportBssid
                legacyBssid != null &&
                    (associated || Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) -> legacyBssid
                else -> null
            }
            if (bssid != null) {
                return mapOf(
                    "status" to "connected",
                    "ssid" to displaySsid(chosen?.ssid),
                    "bssid" to bssid,
                    "rssi_dbm" to usableRssi(chosen?.rssi),
                )
            }
            if (!associated) {
                return mapOf("status" to "not_connected")
            }
            when (locationServicesEnabled()) {
                false -> mapOf("status" to "location_disabled")
                else -> mapOf("status" to "bssid_unavailable")
            }
        } catch (_: Exception) {
            mapOf("status" to "unavailable")
        }
    }

    /**
     * Every connected network, not only [ConnectivityManager.getActiveNetwork].
     * Mobile data or a VPN can be the default route while Wi-Fi stays associated.
     * API 31+ reads [NetworkCapabilities.getTransportInfo]. Older releases have no
     * transport info, so the caller falls back to [WifiManager.getConnectionInfo].
     */
    private fun observeConnectedWifi(connectivity: ConnectivityManager): WifiObservation {
        var transportPresent = false
        var redacted: WifiInfo? = null
        for (network in connectivity.allNetworks) {
            val capabilities = try {
                connectivity.getNetworkCapabilities(network)
            } catch (_: Exception) {
                null
            } ?: continue
            if (!capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) continue
            transportPresent = true
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) continue
            val info = capabilities.transportInfo as? WifiInfo ?: continue
            if (usableBssid(info.bssid) != null) {
                return WifiObservation(transportPresent = true, info = info)
            }
            if (redacted == null) redacted = info
        }
        return WifiObservation(transportPresent = transportPresent, info = redacted)
    }

    private fun legacyAssociated(info: WifiInfo?): Boolean {
        if (info == null || Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) return false
        @Suppress("DEPRECATION")
        val networkId = info.networkId
        @Suppress("DEPRECATION")
        val state = info.supplicantState
        return networkId != -1 && state == SupplicantState.COMPLETED
    }

    private fun locationServicesEnabled(): Boolean? {
        return try {
            val manager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                manager.isLocationEnabled
            } else {
                manager.isProviderEnabled(LocationManager.GPS_PROVIDER) ||
                    manager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
            }
        } catch (_: Exception) {
            null
        }
    }
}

private data class WifiObservation(
    val transportPresent: Boolean,
    val info: WifiInfo?,
)

private fun usableRssi(raw: Int?): String? {
    // Android reports an unknown RSSI as -127. That constant is not in the
    // public compile SDK stub, so the same numeric cutoff is used here.
    if (raw == null || raw <= -127 || raw >= 0) return null
    return raw.toString()
}

private fun usableBssid(raw: String?): String? {
    if (raw.isNullOrBlank()) return null
    val value = raw.trim()
    if (value.equals("02:00:00:00:00:00", ignoreCase = true)) return null
    if (value.equals("00:00:00:00:00:00", ignoreCase = true)) return null
    if (value.startsWith("<") || value.contains("unknown", ignoreCase = true)) return null
    return value
}

private fun displaySsid(raw: String?): String? {
    if (raw.isNullOrBlank()) return null
    var ssid = raw.trim()
    if (ssid.length >= 2 && ssid.startsWith("\"") && ssid.endsWith("\"")) {
        ssid = ssid.substring(1, ssid.length - 1)
    }
    if (ssid.isBlank() || ssid.equals("<unknown ssid>", ignoreCase = true)) return null
    return ssid
}

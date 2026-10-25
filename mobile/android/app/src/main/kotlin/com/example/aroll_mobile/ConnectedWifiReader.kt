package com.example.aroll_mobile

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.location.LocationManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.ScanResult
import android.net.wifi.SupplicantState
import android.net.wifi.WifiInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.CancellationSignal
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.util.Log
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Foreground read of the access point this phone is already joined to.
 *
 * Android 11 (API 30) is the oldest version that can supply this reading.
 * BSSID and RSSI are collected separately: a redacted address does not
 * throw away a real signal strength, and a placeholder address is never
 * returned. Scan results are used only when the connected network name
 * matches exactly one real access point.
 */
class ConnectedWifiReader(private val context: Context) {
    fun read(reply: (Map<String, Any?>) -> Unit) {
        worker.execute {
            val payload = try {
                readBlocking()
            } catch (_: Exception) {
                mapOf("status" to "unavailable")
            }
            mainHandler.post {
                try {
                    reply(payload)
                } catch (_: Exception) {
                }
            }
        }
    }

    fun readBlocking(): Map<String, Any?> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            return mapOf("status" to "android_too_old")
        }
        val fineLocation = context.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION)
        if (fineLocation != PackageManager.PERMISSION_GRANTED) {
            return mapOf("status" to "permission_denied")
        }

        val managers = wifiManagers()
        if (managers.isEmpty()) return mapOf("status" to "unavailable")
        val wifiEnabled = managers.any { manager ->
            try {
                @Suppress("DEPRECATION")
                manager.isWifiEnabled
            } catch (_: Exception) {
                false
            }
        }
        if (!wifiEnabled) return mapOf("status" to "not_connected")

        var fields = readDirect()
        if (!fields.associated && fields.bssid == null) {
            return payload(fields, locationServicesEnabled(), emptyList())
        }
        if (fields.bssid != null) {
            return payload(fields, locationServicesEnabled(), emptyList())
        }

        val locationOn = locationServicesEnabled()
        if (locationOn != false && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            awaitLocationSensitiveWifi()?.let { fields = merge(it, fields) }
        }
        if (fields.bssid == null && locationOn == true) {
            probeLocation()
            fields = merge(readDirect(), fields)
        }

        val scans = if (fields.bssid == null && fields.ssid != null && locationOn == true) {
            cachedScans()
        } else {
            emptyList()
        }
        if (fields.bssid == null && fields.associated) {
            reliableScanMatch(fields.ssid, scans)?.let { match ->
                fields = fields.copy(
                    bssid = match.bssid,
                    rssi = fields.rssi ?: match.rssiDbm,
                )
            }
        }
        val result = payload(fields, locationOn, if (fields.bssid == null) scans else emptyList())
        Log.i(
            LOG_TAG,
            "status=${result["status"]} bssidPresent=${result["bssid"] != null} rssiPresent=${result["rssi_dbm"] != null}",
        )
        return result
    }

    private fun readDirect(): WifiFields {
        return merge(observeTransport(), readLegacy())
    }

    /**
     * Every connected network, not only [ConnectivityManager.getActiveNetwork].
     * Mobile data or a VPN can be the default route while Wi-Fi stays associated.
     * Transport info exists from API 29, so Android 11 is included.
     */
    private fun observeTransport(): WifiFields {
        val connectivity =
            context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
                ?: return WifiFields()
        var associated = false
        var redacted: WifiFields? = null
        for (network in connectivity.allNetworks) {
            val capabilities = try {
                connectivity.getNetworkCapabilities(network)
            } catch (_: Exception) {
                null
            } ?: continue
            if (!capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) continue
            associated = true
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) continue
            val info = capabilities.transportInfo as? WifiInfo ?: continue
            val fields = fieldsFrom(info, transportPresent = true)
            if (fields.bssid != null) return fields
            if (redacted == null) redacted = fields
        }
        return redacted?.copy(associated = true) ?: WifiFields(associated = associated)
    }

    @Suppress("DEPRECATION")
    private fun readLegacy(): WifiFields {
        var chosen: WifiInfo? = null
        for (manager in wifiManagers()) {
            val info = try {
                manager.connectionInfo
            } catch (_: SecurityException) {
                null
            } ?: continue
            if (normalizeBssid(info.bssid) != null) {
                return fieldsFrom(info, transportPresent = false)
            }
            if (chosen == null || (usableRssi(info.rssi) != null && usableRssi(chosen.rssi) == null)) {
                chosen = info
            }
        }
        return fieldsFrom(chosen, transportPresent = false)
    }

    /**
     * Android 12 and later omit BSSID and RSSI from a plain capabilities poll.
     * This listens only. It does not join, leave, or request a network.
     */
    @androidx.annotation.RequiresApi(Build.VERSION_CODES.S)
    private fun awaitLocationSensitiveWifi(): WifiFields? {
        val connectivity =
            context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
                ?: return null
        val request = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .build()
        val lock = Any()
        var found: WifiFields? = null
        val latch = CountDownLatch(1)
        val callback = object : ConnectivityManager.NetworkCallback(
            ConnectivityManager.NetworkCallback.FLAG_INCLUDE_LOCATION_INFO,
        ) {
            override fun onCapabilitiesChanged(
                network: Network,
                networkCapabilities: NetworkCapabilities,
            ) {
                val info = networkCapabilities.transportInfo as? WifiInfo ?: return
                val fields = fieldsFrom(info, transportPresent = true)
                synchronized(lock) { found = merge(fields, found ?: WifiFields()) }
                if (fields.bssid != null) latch.countDown()
            }
        }
        var registered = false
        try {
            connectivity.registerNetworkCallback(request, callback, callbackHandler)
            registered = true
            latch.await(LOCATION_CALLBACK_WAIT_MS, TimeUnit.MILLISECONDS)
        } catch (_: Exception) {
        } finally {
            if (registered) {
                try {
                    connectivity.unregisterNetworkCallback(callback)
                } catch (_: Exception) {
                }
            }
        }
        return synchronized(lock) { found }
    }

    /**
     * Some Android 11 phones keep the connected address redacted until the
     * app actually requests a location. This does not invent an address.
     */
    @SuppressLint("MissingPermission")
    private fun probeLocation() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        val manager = context.getSystemService(Context.LOCATION_SERVICE) as? LocationManager ?: return
        for (provider in listOf(LocationManager.NETWORK_PROVIDER, LocationManager.GPS_PROVIDER)) {
            val enabled = try {
                manager.isProviderEnabled(provider)
            } catch (_: Exception) {
                false
            }
            if (!enabled) continue
            if (awaitCurrentLocation(manager, provider)) return
        }
    }

    @SuppressLint("MissingPermission")
    private fun awaitCurrentLocation(manager: LocationManager, provider: String): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return false
        val delivered = AtomicBoolean(false)
        val latch = CountDownLatch(1)
        val cancel = CancellationSignal()
        try {
            manager.getCurrentLocation(provider, cancel, locationExecutor) {
                delivered.set(true)
                latch.countDown()
            }
        } catch (_: Exception) {
            return false
        }
        try {
            latch.await(LOCATION_PROBE_WAIT_MS, TimeUnit.MILLISECONDS)
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
        } finally {
            cancel.cancel()
        }
        return delivered.get()
    }

    @Suppress("DEPRECATION")
    private fun cachedScans(): List<WifiScanSight> {
        val scans = mutableListOf<WifiScanSight>()
        for (manager in wifiManagers()) {
            val results = try {
                manager.scanResults
            } catch (_: SecurityException) {
                emptyList()
            } ?: emptyList()
            for (result in results) {
                scans.add(sightFrom(result))
            }
        }
        return scans
    }

    @Suppress("DEPRECATION")
    private fun sightFrom(result: ScanResult): WifiScanSight {
        val modernSsid = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            result.wifiSsid?.toString()
        } else {
            null
        }
        return WifiScanSight(
            ssid = displaySsid(result.SSID) ?: displaySsid(modernSsid),
            bssid = result.BSSID,
            rssiDbm = result.level,
        )
    }

    private fun wifiManagers(): List<WifiManager> {
        return listOf(context, context.applicationContext)
            .distinct()
            .mapNotNull { it.getSystemService(Context.WIFI_SERVICE) as? WifiManager }
    }

    private fun locationServicesEnabled(): Boolean? {
        return try {
            val manager = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
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

    private fun payload(
        fields: WifiFields,
        locationOn: Boolean?,
        scans: List<WifiScanSight>,
    ): Map<String, Any?> {
        val status = when {
            fields.bssid != null -> "connected"
            fields.associated && locationOn == false -> "location_disabled"
            fields.associated -> "bssid_unavailable"
            else -> "not_connected"
        }
        val body = mutableMapOf<String, Any?>(
            "status" to status,
            "ssid" to fields.ssid,
            "bssid" to if (status == "connected") fields.bssid else null,
            "rssi_dbm" to fields.rssi,
        )
        if (status != "connected" && scans.isNotEmpty()) {
            body["scans"] = scans.map { scan ->
                mapOf(
                    "ssid" to scan.ssid,
                    "bssid" to scan.bssid,
                    "rssi_dbm" to scan.rssiDbm?.toString(),
                )
            }
        }
        return body
    }

    companion object {
        private const val LOG_TAG = "ArollWifi"
        private const val LOCATION_CALLBACK_WAIT_MS = 2_000L
        private const val LOCATION_PROBE_WAIT_MS = 1_500L

        private val worker = Executors.newSingleThreadExecutor()
        private val locationExecutor = Executors.newSingleThreadExecutor()
        private val mainHandler = Handler(Looper.getMainLooper())
        private val callbackHandler: Handler by lazy {
            Handler(HandlerThread("aroll-workplace-wifi").apply { start() }.looper)
        }

        /**
         * Keep this rule aligned with [reliableConnectedScanMatch] in
         * workplace_wifi.dart. One matching access point is usable. Two
         * addresses for the same name, a different name, or a placeholder
         * address are not.
         */
        fun reliableScanMatch(connectedSsid: String?, scans: List<WifiScanSight>): ReliableScanMatch? {
            val ssid = displaySsid(connectedSsid) ?: return null
            val byBssid = LinkedHashMap<String, Int?>()
            for (scan in scans) {
                if (displaySsid(scan.ssid) != ssid) continue
                val bssid = normalizeBssid(scan.bssid) ?: continue
                val rssi = usableRssi(scan.rssiDbm)?.toInt()
                val previous = byBssid[bssid]
                if (!byBssid.containsKey(bssid) || (rssi != null && (previous == null || rssi > previous))) {
                    byBssid[bssid] = rssi
                }
            }
            if (byBssid.size != 1) return null
            val match = byBssid.entries.first()
            return ReliableScanMatch(match.key, match.value?.toString())
        }
    }
}

data class WifiScanSight(
    val ssid: String?,
    val bssid: String?,
    val rssiDbm: Int?,
)

data class ReliableScanMatch(
    val bssid: String,
    val rssiDbm: String?,
)

private data class WifiFields(
    val ssid: String? = null,
    val bssid: String? = null,
    val rssi: String? = null,
    val associated: Boolean = false,
)

private fun merge(primary: WifiFields, extra: WifiFields): WifiFields {
    return WifiFields(
        ssid = primary.ssid ?: extra.ssid,
        bssid = primary.bssid ?: extra.bssid,
        rssi = primary.rssi ?: extra.rssi,
        associated = primary.associated || extra.associated,
    )
}

private fun fieldsFrom(info: WifiInfo?, transportPresent: Boolean): WifiFields {
    return WifiFields(
        ssid = displaySsid(info?.ssid),
        bssid = normalizeBssid(info?.bssid),
        rssi = usableRssi(info?.rssi),
        associated = transportPresent || infoAssociated(info),
    )
}

@Suppress("DEPRECATION")
private fun infoAssociated(info: WifiInfo?): Boolean {
    if (info == null) return false
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
        return info.networkId != -1 && info.supplicantState == SupplicantState.COMPLETED
    }
    return normalizeBssid(info.bssid) != null || usableRssi(info.rssi) != null
}

private fun usableRssi(raw: Int?): String? {
    if (raw == null || raw <= -127 || raw >= 0) return null
    return raw.toString()
}

fun normalizeBssid(raw: String?): String? {
    if (raw.isNullOrBlank()) return null
    val text = raw.trim().lowercase().replace('-', ':')
    if (text.isEmpty() || text.startsWith("<") || text.contains("unknown")) return null
    val parts = text.split(':')
    if (parts.size != 6) return null
    val octets = parts.map { part ->
        if (part.isEmpty() || part.length > 2) return null
        part.toIntOrNull(16)?.takeIf { it in 0..255 } ?: return null
    }
    val normalized = octets.joinToString(":") { it.toString(16).padStart(2, '0') }
    if (normalized == "00:00:00:00:00:00" || normalized == "02:00:00:00:00:00") return null
    return normalized
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

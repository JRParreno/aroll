package com.example.aroll_mobile

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ConnectedWifiReadTest {
    @Test
    fun scanMatchAcceptsOneAccessPointAndRejectsGuesses() {
        val only = ConnectedWifiReader.reliableScanMatch(
            "Cafe",
            listOf(
                WifiScanSight("Cafe", "aa:bb:cc:dd:ee:01", -40),
                WifiScanSight("Other", "aa:bb:cc:dd:ee:02", -50),
            ),
        )
        assertEquals("aa:bb:cc:dd:ee:01", only?.bssid)

        val sameAddress = ConnectedWifiReader.reliableScanMatch(
            "\"Cafe\"",
            listOf(
                WifiScanSight("Cafe", "AA-BB-CC-DD-EE-01", -70),
                WifiScanSight("\"Cafe\"", "aa:bb:cc:dd:ee:01", -40),
            ),
        )
        assertEquals("aa:bb:cc:dd:ee:01", sameAddress?.bssid)
        assertEquals("-40", sameAddress?.rssiDbm)

        assertNull(
            ConnectedWifiReader.reliableScanMatch(
                "Cafe",
                listOf(
                    WifiScanSight("Cafe", "aa:bb:cc:dd:ee:01", -40),
                    WifiScanSight("Cafe", "aa:bb:cc:dd:ee:02", -50),
                ),
            ),
        )
        assertNull(
            ConnectedWifiReader.reliableScanMatch(
                "Cafe",
                listOf(WifiScanSight("Neighbor", "aa:bb:cc:dd:ee:09", -30)),
            ),
        )
        assertNull(
            ConnectedWifiReader.reliableScanMatch(
                "<unknown ssid>",
                listOf(WifiScanSight("Cafe", "aa:bb:cc:dd:ee:01", -40)),
            ),
        )
        assertNull(
            ConnectedWifiReader.reliableScanMatch(
                "Cafe",
                listOf(
                    WifiScanSight("Cafe", "02:00:00:00:00:00", -40),
                    WifiScanSight("Cafe", "00:00:00:00:00:00", -40),
                ),
            ),
        )
        assertNull(normalizeBssid("02:00:00:00:00:00"))
        assertNull(normalizeBssid("00:00:00:00:00:00"))
    }

    @Test(timeout = 90_000)
    fun foregroundReadRejectsPlaceholderAndKeepsRssiSeparate() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val appContext = instrumentation.targetContext
        assertTrue(Build.VERSION.SDK_INT >= Build.VERSION_CODES.R)
        val granted = appContext.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED
        val readerContext = if (granted) foregroundContext(instrumentation) else appContext
        val payload = ConnectedWifiReader(readerContext).readBlocking()
        val status = payload["status"] as? String
        val bssid = payload["bssid"] as? String
        val rssi = (payload["rssi_dbm"] as? String)?.toIntOrNull()
        Log.i(TAG, "sdk=${Build.VERSION.SDK_INT} status=$status bssidPresent=${bssid != null} rssi=$rssi")

        assertNotEquals("unavailable", status)
        assertNotEquals("android_too_old", status)
        if (!granted) {
            assertEquals("permission_denied", status)
            assertNull(bssid)
            return
        }
        if (bssid != null) {
            assertFalse(bssid.equals("02:00:00:00:00:00", ignoreCase = true))
            assertFalse(bssid.equals("00:00:00:00:00:00", ignoreCase = true))
            assertTrue(bssid.matches(Regex("[0-9a-f]{2}(:[0-9a-f]{2}){5}")))
            assertEquals("connected", status)
        }
        if (rssi != null) {
            assertTrue(rssi < 0 && rssi > -127)
        }
        if (wifiTransportConnected(appContext)) {
            assertTrue(
                status == "connected" || status == "bssid_unavailable" || status == "location_disabled",
            )
            if (status == "bssid_unavailable") {
                assertNull(bssid)
            }
        }
    }

    private fun foregroundContext(instrumentation: android.app.Instrumentation): Context {
        return try {
            val intent = Intent(instrumentation.targetContext, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            instrumentation.startActivitySync(intent)
        } catch (error: Exception) {
            Log.i(TAG, "foreground activity unavailable: ${error.javaClass.simpleName}")
            instrumentation.targetContext
        }
    }

    private fun wifiTransportConnected(context: Context): Boolean {
        val connectivity =
            context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
                ?: return false
        return connectivity.allNetworks.any { network ->
            connectivity.getNetworkCapabilities(network)
                ?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
        }
    }

    companion object {
        private const val TAG = "ArollWifiTest"
    }
}

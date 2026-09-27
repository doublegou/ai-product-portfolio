package com.rivendell.stayword.media

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.location.Address
import android.location.Geocoder
import android.location.Location
import android.location.LocationManager
import android.os.Build
import android.os.CancellationSignal
import androidx.core.content.ContextCompat
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import java.util.Locale
import kotlin.coroutines.resume

interface LocationTitleSuggester {
    suspend fun suggest(): String?
}

class SystemLocationTitleSuggester(private val context: Context) : LocationTitleSuggester {
    override suspend fun suggest(): String? {
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION) !=
            PackageManager.PERMISSION_GRANTED
        ) return null

        val location = currentLocation() ?: return null
        val address = reverseGeocode(location) ?: return null
        return listOf(address.featureName, address.subLocality, address.locality, address.adminArea)
            .firstOrNull { !it.isNullOrBlank() }
            ?.trim()
            ?.take(160)
    }

    @SuppressLint("MissingPermission")
    private suspend fun currentLocation(): Location? {
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION) !=
            PackageManager.PERMISSION_GRANTED
        ) return null
        return suspendCancellableCoroutine { continuation ->
            val manager = context.getSystemService(LocationManager::class.java)
            val providers = listOf(
                LocationManager.NETWORK_PROVIDER,
                LocationManager.FUSED_PROVIDER,
                LocationManager.PASSIVE_PROVIDER,
            ).filter { provider -> manager.allProviders.contains(provider) }
            val fallback = providers.mapNotNull { provider ->
                runCatching { manager.getLastKnownLocation(provider) }.getOrNull()
            }.maxByOrNull { it.time }
            val provider = providers.firstOrNull {
                runCatching { manager.isProviderEnabled(it) }.getOrDefault(false)
            }
            if (provider == null) {
                continuation.resume(fallback)
                return@suspendCancellableCoroutine
            }

            val cancellation = CancellationSignal()
            continuation.invokeOnCancellation { cancellation.cancel() }
            runCatching {
                manager.getCurrentLocation(
                    provider,
                    cancellation,
                    ContextCompat.getMainExecutor(context),
                ) { location ->
                    if (continuation.isActive) continuation.resume(location ?: fallback)
                }
            }.onFailure {
                if (continuation.isActive) continuation.resume(fallback)
            }
        }
    }

    private suspend fun reverseGeocode(location: Location): Address? {
        val geocoder = Geocoder(context, Locale.getDefault())
        if (!Geocoder.isPresent()) return null
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            suspendCancellableCoroutine { continuation ->
                geocoder.getFromLocation(location.latitude, location.longitude, 1) { addresses ->
                    if (continuation.isActive) continuation.resume(addresses.firstOrNull())
                }
            }
        } else {
            @Suppress("DEPRECATION")
            withContext(Dispatchers.IO) {
                runCatching {
                    geocoder.getFromLocation(location.latitude, location.longitude, 1)?.firstOrNull()
                }.getOrNull()
            }
        }
    }
}

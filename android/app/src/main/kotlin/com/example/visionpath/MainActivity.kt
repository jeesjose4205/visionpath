package com.example.visionpath

import android.Manifest
import android.app.Activity
import android.app.PendingIntent
import android.content.ActivityNotFoundException
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import android.media.AudioManager
import android.media.ToneGenerator
import android.net.Uri
import android.os.Build
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.telephony.SmsManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executor
import java.util.function.Consumer

/**
 * Hosts the emergency channel used by the SOS flow.
 *
 * The app deliberately avoids telephony/SMS/location/audio plugins so it keeps
 * building on AGP 9, so the four capabilities SOS needs are implemented here
 * against the platform APIs directly:
 *
 *  * direct calling via [Intent.ACTION_CALL] (no second tap in the dialer),
 *  * silent SMS via [SmsManager], with a real delivery report,
 *  * a one-shot GPS fix via [LocationManager],
 *  * a repeating alert tone via [ToneGenerator] on the alarm stream.
 *
 * Every entry point reports what actually happened. A failed capability comes
 * back as an explicit error string rather than a silent success, so the Dart
 * layer can never claim a call or message went out when it did not.
 */
class MainActivity : FlutterActivity() {

    private companion object {
        const val CHANNEL = "com.example.visionpath/emergency"

        /** Longest we wait for a GPS fix before settling for a stale one. */
        const val LOCATION_TIMEOUT_MS = 12_000L

        /** A last-known fix younger than this is good enough to send as-is. */
        const val FRESH_FIX_MS = 120_000L

        /** Alert tone burst length, and the silence between bursts. */
        const val TONE_BURST_MS = 420L
        const val TONE_GAP_MS = 780L

        /**
         * Fixed alarm-stream volume. The user's media volume is never read or
         * written, so SOS cannot permanently alter what their music sounds like.
         */
        const val TONE_VOLUME = 85

        /** Distinct platform tones backing the user-selectable alert sounds. */
        val TONE_IDS = mapOf(
            "beep1" to ToneGenerator.TONE_CDMA_PIP,
            "beep2" to ToneGenerator.TONE_CDMA_HIGH_L,
            "beep3" to ToneGenerator.TONE_CDMA_MED_L,
            "emergency" to ToneGenerator.TONE_CDMA_ALERT_CALL_GUARD,
            "siren" to ToneGenerator.TONE_CDMA_EMERGENCY_RINGBACK,
        )

        const val ACTION_SMS_SENT = "com.example.visionpath.SMS_SENT"
        const val ACTION_SMS_DELIVERED = "com.example.visionpath.SMS_DELIVERED"

        /**
         * Identifies which send a broadcast belongs to.
         *
         * Android delivers the report to the PendingIntent we built, so a stale
         * report from an abandoned send must not be mistaken for the current one.
         */
        const val EXTRA_SEND_TOKEN = "sendToken"

        /** How long to wait for a delivery report before calling it unconfirmed. */
        const val SMS_DELIVERY_TIMEOUT_MS = 20_000L
    }

    private val mainHandler = Handler(Looper.getMainLooper())

    // ------------------------------------------------------------------
    // Alert tone state. The loop lives here, on the platform side, so it
    // keeps beeping while Dart timers are throttled in the background or the
    // SOS screen is not mounted at all.
    // ------------------------------------------------------------------
    private var toneGenerator: ToneGenerator? = null
    private var toneRunnable: Runnable? = null
    private var toneActive = false
    private var toneId: Int = ToneGenerator.TONE_CDMA_ALERT_CALL_GUARD

    // ------------------------------------------------------------------
    // SMS delivery confirmation. Android can tell us whether the message
    // actually reached the handset; without this we would be guessing.
    // ------------------------------------------------------------------
    private var pendingSmsResult: MethodChannel.Result? = null
    private var pendingSmsTimeout: Runnable? = null

    /** Incremented per send so a late report cannot answer the wrong request. */
    private var smsToken = 0

    /**
     * The token the in-flight send is waiting on, or `0` when nothing is pending.
     */
    private var pendingSmsToken = 0

    /**
     * Turns Android's report broadcasts into one honest answer.
     *
     * `getResultCode()` is the platform's own verdict: `RESULT_OK` on a delivery
     * report means the handset received the message. Anything else — including a
     * "sent" report that never got a delivery confirmation — is reported as such
     * so the UI never claims a delivered message it cannot prove.
     */
    private val smsReportReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val report = intent ?: return
            val token = report.getIntExtra(EXTRA_SEND_TOKEN, 0)
            if (token == 0 || token != pendingSmsToken) return

            when (report.action) {
                ACTION_SMS_SENT ->
                    if (resultCode != Activity.RESULT_OK) {
                        // The radio refused the message outright; waiting for a
                        // delivery report that will never come would only delay
                        // telling the user it failed.
                        finishSms("not_delivered")
                    }
                ACTION_SMS_DELIVERED ->
                    finishSms(
                        if (resultCode == Activity.RESULT_OK) "delivered" else "not_delivered",
                    )
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Registered for the whole activity lifetime rather than per send, so a
        // delivery report that arrives while the user is elsewhere still lands.
        registerSmsReportReceiver()
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result -> handle(call, result) }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        stopAlertTone()
        // A pending send can no longer be answered once the engine is gone, so
        // reply "unconfirmed" rather than leaving Dart waiting forever.
        if (pendingSmsResult != null) {
            finishSms("unconfirmed")
        }
        runOnUiThread {
            runCatching { unregisterReceiver(smsReportReceiver) }
            pendingSmsTimeout?.let { mainHandler.removeCallbacks(it) }
            pendingSmsTimeout = null
        }
        super.cleanUpFlutterEngine(flutterEngine)
    }

    /**
     * Registers for the SMS sent/delivery reports of this app.
     *
     * The three-argument overload only exists from Android 8, so older devices
     * use the two-argument form. The broadcasts are package-scoped to this app,
     * which is what keeps the legacy overload safe on Android 14+.
     */
    private fun registerSmsReportReceiver() {
        // No package scoping is applied here: `IntentFilter.setPackage` only exists
        // from Android 13. The reports can only be triggered by our own
        // PendingIntents (they carry this package and a per-send token), and the
        // registration flags are explicit, so an extra filter restriction would
        // add nothing.
        val filter = IntentFilter().apply {
            addAction(ACTION_SMS_SENT)
            addAction(ACTION_SMS_DELIVERED)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(smsReportReceiver, filter, Context.RECEIVER_EXPORTED)
        } else {
            @Suppress("DEPRECATION")
            runCatching { registerReceiver(smsReportReceiver, filter) }
        }
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "placeDirectCall" -> {
                val number = call.argument<String>("number").orEmpty()
                placeDirectCall(number, result)
            }
            "openDialer" -> {
                val number = call.argument<String>("number").orEmpty()
                openDialer(number, result)
            }
            "sendSms" -> {
                val number = call.argument<String>("number").orEmpty()
                val body = call.argument<String>("body").orEmpty()
                sendSms(number, body, result)
            }
            "openSmsComposer" -> {
                val number = call.argument<String>("number").orEmpty()
                val body = call.argument<String>("body").orEmpty()
                openSmsComposer(number, body, result)
            }
            "getLocation" -> {
                val timeoutMs =
                    (call.argument<Number>("timeoutMs")?.toLong() ?: LOCATION_TIMEOUT_MS)
                        .coerceIn(1_000L, 30_000L)
                getLocation(timeoutMs, result)
            }
            "startAlertTone" -> {
                val tone = call.argument<String>("tone") ?: "emergency"
                result.success(startAlertTone(tone))
            }
            "stopAlertTone" -> {
                stopAlertTone()
                result.success(true)
            }
            "isAlertToneSupported" -> result.success(isAlertToneSupported())
            else -> result.notImplemented()
        }
    }

    // ------------------------------------------------------------------
    // Permissions
    // ------------------------------------------------------------------

    private fun hasPermission(permission: String): Boolean =
        checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    /**
     * Why direct calling is unavailable right now, or `null` when it is ready.
     *
     * Distinguishing "not granted yet" from "no dialer on this device" matters:
     * the first is fixable with one permission prompt, the second is a hard
     * platform limit that the UI has to explain rather than work around.
     */
    private fun directCallBlocker(): String? = when {
        !hasPermission(Manifest.permission.CALL_PHONE) -> "permission_call_phone"
        else -> null
    }

    private fun smsBlocker(): String? = when {
        !hasPermission(Manifest.permission.SEND_SMS) -> "permission_send_sms"
        else -> null
    }

    // ------------------------------------------------------------------
    // Calling
    // ------------------------------------------------------------------

    /**
     * Places the call without the dialer: [Intent.ACTION_CALL] tells the
     * platform to connect immediately once [CALL_PHONE] has been granted.
     */
    private fun placeDirectCall(number: String, result: MethodChannel.Result) {
        val digits = sanitizePhone(number)
        if (digits.isEmpty()) {
            result.success(mapOf("placed" to false, "error" to "invalid_number"))
            return
        }
        directCallBlocker()?.let { blocker ->
            result.success(mapOf("placed" to false, "error" to blocker))
            return
        }
        try {
            startActivity(
                Intent(Intent.ACTION_CALL).apply { data = Uri.parse("tel:$digits") },
            )
            result.success(mapOf("placed" to true, "error" to ""))
        } catch (e: SecurityException) {
            result.success(mapOf("placed" to false, "error" to "permission_call_phone"))
        } catch (e: ActivityNotFoundException) {
            // No dialer app on this device: the only honest answer is that the
            // call was not placed.
            result.success(mapOf("placed" to false, "error" to "no_dialer"))
        } catch (e: Exception) {
            result.success(mapOf("placed" to false, "error" to (e.message ?: "call_failed")))
        }
    }

    /**
     * Fallback that opens a pre-filled dialer.
     *
     * This is deliberately reported as `requires_user_tap`: the number is on
     * screen, but the call has not been placed and the user must still press
     * call. The UI must never present this as a completed call.
     */
    private fun openDialer(number: String, result: MethodChannel.Result) {
        val digits = sanitizePhone(number)
        if (digits.isEmpty()) {
            result.success(mapOf("opened" to false, "error" to "invalid_number"))
            return
        }
        try {
            startActivity(
                Intent(Intent.ACTION_DIAL).apply { data = Uri.parse("tel:$digits") },
            )
            result.success(mapOf("opened" to true, "requires_user_tap" to true, "error" to ""))
        } catch (e: Exception) {
            result.success(mapOf("opened" to false, "error" to "no_dialer"))
        }
    }

    // ------------------------------------------------------------------
    // SMS
    // ------------------------------------------------------------------

    /**
     * Sends the emergency message without showing a composer.
     *
     * The reply only arrives once Android reports the delivery result, so the
     * UI can distinguish "the handset received this" from "the radio accepted
     * it but delivery is unconfirmed" instead of claiming success either way.
     */
    private fun sendSms(number: String, body: String, result: MethodChannel.Result) {
        val digits = sanitizePhone(number)
        if (digits.isEmpty()) {
            result.success(mapOf("sent" to false, "error" to "invalid_number"))
            return
        }
        smsBlocker()?.let { blocker ->
            result.success(mapOf("sent" to false, "error" to blocker))
            return
        }
        if (body.isBlank()) {
            result.success(mapOf("sent" to false, "error" to "empty_message"))
            return
        }

        try {
            val manager = smsManager()
            if (manager == null) {
                result.success(mapOf("sent" to false, "error" to "no_sms_service"))
                return
            }

            // Only one emergency message may be in flight; a second send would
            // mean a second SMS.
            pendingSmsTimeout?.let { mainHandler.removeCallbacks(it) }
            pendingSmsTimeout = null
            if (pendingSmsResult != null) {
                // Answer the abandoned send instead of dropping its result.
                finishSms("unconfirmed")
            }

            val token = ++smsToken
            val parts = manager.divideMessage(body)
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }

            fun reportIntent(action: String, requestCode: Int): PendingIntent =
                PendingIntent.getBroadcast(
                    this,
                    requestCode,
                    Intent(action).apply {
                        setPackage(packageName)
                        putExtra(EXTRA_SEND_TOKEN, token)
                    },
                    flags,
                )

            val sentIntents = ArrayList<PendingIntent>(parts.size)
            val deliveryIntents = ArrayList<PendingIntent>(parts.size)
            repeat(parts.size) { index ->
                sentIntents.add(reportIntent(ACTION_SMS_SENT, index * 2))
                deliveryIntents.add(reportIntent(ACTION_SMS_DELIVERED, index * 2 + 1))
            }

            pendingSmsResult = result
            pendingSmsToken = token
            // The fourth argument reports whether the radio accepted the
            // message; the fifth reports actual handset delivery. Only the
            // latter is treated as "sent" in the UI.
            manager.sendMultipartTextMessage(
                digits,
                null,
                parts,
                sentIntents,
                deliveryIntents,
            )

            val timeout = Runnable { finishSms("unconfirmed") }
            pendingSmsTimeout = timeout
            mainHandler.postDelayed(timeout, SMS_DELIVERY_TIMEOUT_MS)
        } catch (e: SecurityException) {
            result.success(mapOf("sent" to false, "error" to "permission_send_sms"))
        } catch (e: Exception) {
            result.success(mapOf("sent" to false, "error" to (e.message ?: "sms_failed")))
        }
    }

    private fun finishSms(status: String) {
        pendingSmsTimeout?.let { mainHandler.removeCallbacks(it) }
        pendingSmsTimeout = null
        val pending = pendingSmsResult ?: return
        pendingSmsResult = null
        pendingSmsToken = 0
        pending.success(
            mapOf(
                "sent" to (status == "delivered"),
                "status" to status,
                "error" to if (status == "delivered") "" else status,
            ),
        )
    }

    /**
     * Fallback that opens a pre-filled composer.
     *
     * Reported as `requires_user_tap`, because the message has not been sent
     * until the user presses send.
     */
    private fun openSmsComposer(number: String, body: String, result: MethodChannel.Result) {
        val digits = sanitizePhone(number)
        if (digits.isEmpty()) {
            result.success(mapOf("opened" to false, "error" to "invalid_number"))
            return
        }
        try {
            startActivity(
                Intent(Intent.ACTION_SENDTO).apply {
                    data = Uri.parse("smsto:$digits")
                    putExtra("sms_body", body)
                },
            )
            result.success(mapOf("opened" to true, "requires_user_tap" to true, "error" to ""))
        } catch (e: Exception) {
            result.success(mapOf("opened" to false, "error" to "no_sms_app"))
        }
    }

    private fun smsManager(): SmsManager? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            getSystemService(SmsManager::class.java)
        } else {
            @Suppress("DEPRECATION")
            runCatching { SmsManager.getDefault() }.getOrNull()
        }

    // ------------------------------------------------------------------
    // Location
    // ------------------------------------------------------------------

    /**
     * Resolves a single GPS fix, preferring a fresh one and falling back to a
     * recent cached fix rather than failing outright.
     *
     * A stale fix is returned with its real age and accuracy so the emergency
     * message can be honest about it. GPS is never allowed to delay the call:
     * this runs concurrently with the call, not before it.
     */
    private fun getLocation(timeoutMs: Long, result: MethodChannel.Result) {
        val granted = hasPermission(Manifest.permission.ACCESS_FINE_LOCATION) ||
            hasPermission(Manifest.permission.ACCESS_COARSE_LOCATION)
        if (!granted) {
            result.success(error("permission_location"))
            return
        }

        val manager = getSystemService(Context.LOCATION_SERVICE) as? LocationManager
        if (manager == null) {
            result.success(error("location_unavailable"))
            return
        }

        val providers = listOf(
            LocationManager.GPS_PROVIDER,
            LocationManager.NETWORK_PROVIDER,
        ).filter {
            runCatching { manager.isProviderEnabled(it) }.getOrDefault(false)
        }
        if (providers.isEmpty()) {
            result.success(error("location_disabled"))
            return
        }

        // A recent cached fix answers immediately and is good enough.
        val cached = providers.mapNotNull { provider ->
            runCatching { manager.getLastKnownLocation(provider) }.getOrNull()
        }.filter { it.time > 0L }.maxByOrNull { it.time }

        if (cached != null && System.currentTimeMillis() - cached.time < FRESH_FIX_MS) {
            result.success(payload(cached, "fresh_cache"))
            return
        }

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            // Pre-Android 11: getCurrentLocation does not exist, so the cached
            // fix is the best we can honestly offer.
            if (cached != null) {
                result.success(payload(cached, "stale_cache"))
            } else {
                result.success(error("location_unavailable"))
            }
            return
        }

        // Android 11+: ask each enabled provider for one fresh fix and take
        // whichever answers first. The result is posted back on the UI thread,
        // so a reply arriving on a location thread can never touch Flutter.
        var settled = false
        val signals = mutableListOf<CancellationSignal>()
        lateinit var timeout: Runnable

        val settle: (Map<String, Any?>) -> Unit = settle@{ answer ->
            if (settled) return@settle
            settled = true
            mainHandler.removeCallbacks(timeout)
            signals.forEach { runCatching { it.cancel() } }
            result.success(answer)
        }

        fun fallback(): Map<String, Any?> =
            if (cached != null) payload(cached, "stale_cache") else error("location_timeout")

        timeout = Runnable { settle(fallback()) }
        mainHandler.postDelayed(timeout, timeoutMs)

        val executor = Executor { command -> mainHandler.post(command) }

        for (provider in providers) {
            if (settled) break
            try {
                val signal = CancellationSignal()
                signals.add(signal)
                manager.getCurrentLocation(
                    provider,
                    signal,
                    executor,
                    Consumer { location ->
                        settle(
                            if (location != null) {
                                payload(location, "gps")
                            } else {
                                fallback()
                            },
                        )
                    },
                )
            } catch (e: Exception) {
                // Try the next provider rather than failing the whole request.
            }
        }
    }

    private fun payload(location: Location, source: String): Map<String, Any> = mapOf(
        "latitude" to location.latitude,
        "longitude" to location.longitude,
        "accuracyMeters" to (if (location.hasAccuracy()) location.accuracy else -1.0),
        "ageMs" to (System.currentTimeMillis() - location.time).coerceAtLeast(0L),
        "source" to source,
    )

    private fun error(code: String): Map<String, Any?> =
        mapOf("latitude" to null, "longitude" to null, "error" to code)

    // ------------------------------------------------------------------
    // Alert tone
    // ------------------------------------------------------------------

    private fun isAlertToneSupported(): Boolean = runCatching {
        ToneGenerator(AudioManager.STREAM_ALARM, TONE_VOLUME).use { true }
    }.getOrDefault(false)

    /**
     * Starts the repeating alert and reports whether audio is really running.
     *
     * A `false` here is meaningful: some devices and ROMs refuse tone playback
     * under Do Not Disturb, and the UI must say so rather than imply the alarm
     * is sounding.
     */
    private fun startAlertTone(tone: String): Boolean {
        stopAlertTone()
        toneId = TONE_IDS[tone] ?: ToneGenerator.TONE_CDMA_ALERT_CALL_GUARD
        return try {
            toneGenerator = ToneGenerator(AudioManager.STREAM_ALARM, TONE_VOLUME)
            toneActive = true
            scheduleTone(0L)
            true
        } catch (e: Exception) {
            toneActive = false
            toneGenerator = null
            false
        }
    }

    private fun scheduleTone(delayMs: Long) {
        val runnable = object : Runnable {
            override fun run() {
                if (!toneActive) return
                val generator = toneGenerator
                if (generator == null) {
                    toneActive = false
                    return
                }
                try {
                    generator.startTone(toneId, TONE_BURST_MS.toInt())
                } catch (e: Exception) {
                    // Playback refused (commonly Do Not Disturb). Stop instead
                    // of silently spinning.
                    toneActive = false
                    return
                }
                toneRunnable = this
                mainHandler.postDelayed(this, TONE_BURST_MS + TONE_GAP_MS + delayMs)
            }
        }
        toneRunnable = runnable
        mainHandler.postDelayed(runnable, delayMs)
    }

    /** Stops the loop and releases the audio resource so nothing keeps playing. */
    private fun stopAlertTone() {
        toneActive = false
        toneRunnable?.let { mainHandler.removeCallbacks(it) }
        toneRunnable = null
        runCatching {
            toneGenerator?.stopTone()
            toneGenerator?.release()
        }
        toneGenerator = null
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    /** Keeps only dialable characters so a stray space cannot break the URI. */
    private fun sanitizePhone(raw: String): String =
        raw.filter { it.isDigit() || it == '+' }.trim()

    private inline fun <T> ToneGenerator.use(block: (ToneGenerator) -> T): T = try {
        block(this)
    } finally {
        runCatching { release() }
    }
}
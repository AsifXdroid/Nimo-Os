package app.dailylife.daily_life_app

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Parcelable
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File

// D-034: share-intent capture is implemented in-house. The
// receive_sharing_intent plugin this replaces is defective in
// every published version under this project's toolchain
// (1.9.0 declares compileSdk 37; 1.8.1 omits its JVM targets and
// fails Kotlin target validation; both apply the Kotlin Gradle
// Plugin that future Flutter versions reject) — see
// docs/CI_BUILD_AUDIT-2026-10-30.md.
//
// The Dart side talks to these channels through
// AppShareIntentService (lib/features/learn/capture_service.dart)
// behind the same ShareIntentService contract the S4 flow was
// built on: getInitialMedia serves the launching share until
// reset; warm shares arrive on the event channel.
class MainActivity : FlutterActivity() {

    companion object {
        private const val METHOD_CHANNEL = "app.dailylife/share_intent"
        private const val EVENT_CHANNEL = "app.dailylife/share_intent/events"
    }

    // The share that launched the app (cold start).
    private var initialShare: List<Map<String, String>>? = null

    // A warm share that arrived before Dart started listening;
    // flushed when the event sink attaches (process-alive shares
    // must not be lost just because the UI was still starting).
    private var pendingShare: List<Map<String, String>>? = null
    private var eventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialMedia" ->
                    result.success(initialShare ?: emptyList<Map<String, String>>())
                "reset" -> {
                    initialShare = null
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        EventChannel(messenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    pendingShare?.let { events?.success(it) }
                    pendingShare = null
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            }
        )
        // Cold start: the launching intent may itself be a share.
        decodeShare(intent)?.let { initialShare = it }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        decodeShare(intent)?.let { share ->
            val sink = eventSink
            if (sink != null) sink.success(share) else pendingShare = share
        }
    }

    // Decode an ACTION_SEND / ACTION_SEND_MULTIPLE intent into the
    // channel payload: a list of {"kind", "value"} maps where kind
    // is "text" (value = the shared text) or "file" (value =
    // absolute path of a private copy of the shared file). As with
    // the old plugin, a SEND carrying a stream yields the file —
    // the stream is the share; text alongside it is not separate
    // content. Returns null for intents that are not shares.
    private fun decodeShare(intent: Intent?): List<Map<String, String>>? {
        if (intent == null) return null
        return when (intent.action) {
            Intent.ACTION_SEND -> {
                val stream = intent.parcelable<Uri>(Intent.EXTRA_STREAM)
                val text = intent.getStringExtra(Intent.EXTRA_TEXT)
                when {
                    stream != null -> copySharedFile(stream)?.let {
                        listOf(mapOf("kind" to "file", "value" to it))
                    }
                    text != null ->
                        listOf(mapOf("kind" to "text", "value" to text))
                    else -> null
                }
            }
            Intent.ACTION_SEND_MULTIPLE -> {
                val streams =
                    intent.parcelableArrayList<Uri>(Intent.EXTRA_STREAM)
                streams
                    ?.mapNotNull { uri ->
                        copySharedFile(uri)?.let {
                            mapOf("kind" to "file", "value" to it)
                        }
                    }
                    ?.takeIf { it.isNotEmpty() }
            }
            else -> null
        }
    }

    // Copy a shared content/file URI into the app cache and return
    // the copy's absolute path. The Dart side treats it as a temp
    // path and imports it into the Library promptly at capture
    // time. A stream that cannot be opened is skipped — never
    // half-delivered as a path that does not exist.
    private fun copySharedFile(uri: Uri): String? {
        return try {
            val dir = File(cacheDir, "shared_captures").apply { mkdirs() }
            val target = File(dir, sharedFileName(uri))
            val opened = contentResolver.openInputStream(uri)?.use { input ->
                target.outputStream().use { output -> input.copyTo(output) }
                true
            } ?: false
            if (opened) target.absolutePath else null
        } catch (e: Exception) {
            null
        }
    }

    // Display name for a shared URI, made safe as a cache file
    // name. The Library sanitises the name again at import; this
    // only needs to be a usable, collision-free-enough name.
    private fun sharedFileName(uri: Uri): String {
        var name: String? = null
        if (uri.scheme == "content") {
            try {
                contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                    val idx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (idx >= 0 && cursor.moveToFirst()) {
                        name = cursor.getString(idx)
                    }
                }
            } catch (e: Exception) {
                name = null
            }
        }
        if (name.isNullOrBlank()) name = uri.lastPathSegment
        val safe = name
            ?.replace(Regex("[^A-Za-z0-9._-]"), "_")
            ?.trim('.', '_')
        return if (safe.isNullOrBlank()) {
            "shared-${System.currentTimeMillis()}"
        } else {
            safe
        }
    }

    private inline fun <reified T : Parcelable> Intent.parcelable(
        key: String
    ): T? = when {
        Build.VERSION.SDK_INT >= 33 -> getParcelableExtra(key, T::class.java)
        else -> @Suppress("DEPRECATION") getParcelableExtra(key) as? T
    }

    private inline fun <reified T : Parcelable> Intent.parcelableArrayList(
        key: String
    ): ArrayList<T>? = when {
        Build.VERSION.SDK_INT >= 33 ->
            getParcelableArrayListExtra(key, T::class.java)
        else -> @Suppress("DEPRECATION") getParcelableArrayListExtra(key)
    }
}

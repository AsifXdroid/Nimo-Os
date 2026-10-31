package app.dailylife.daily_life_app

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Parcelable
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

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

        // D-043 (P0): SAF backup channel — see the saf section
        // below. In-house like the share capture (D-034): the
        // backup zip logic stays in Dart (BackupStore); this
        // channel only moves files in and out of the
        // user-granted Documents tree.
        private const val SAF_CHANNEL = "app.dailylife/saf_backup"
        private const val REQ_PICK_FOLDER = 7331
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

        MethodChannel(messenger, SAF_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickFolder" -> pickFolder(result)
                "folderAccess" ->
                    result.success(safFolderAccess(call.argument<String>("treeUri")))
                "listBackups" -> safList(call.argument<String>("treeUri"), result)
                "writeBackup" -> safWrite(
                    call.argument<String>("treeUri"),
                    call.argument<String>("sourcePath"),
                    call.argument<String>("fileName"),
                    result,
                )
                "copyBackupOut" -> safCopyOut(
                    call.argument<String>("treeUri"),
                    call.argument<String>("documentId"),
                    call.argument<String>("destPath"),
                    result,
                )
                else -> result.notImplemented()
            }
        }
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

    // ------------------------------------------------------ SAF (D-043)
    //
    // The external backup folder lives in shared storage under a
    // Storage Access Framework tree grant the user makes once.
    // Android revokes the grant on uninstall (the FILES survive;
    // a fresh install asks for the folder again). This side only
    // moves bytes — creating a document under a `.partial` name,
    // streaming into it, verifying its size, and renaming it to
    // the final backup name. An existing backup is never opened
    // for writing, so an interrupted write cannot damage the
    // last known-good backup.

    private val safIo = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var pendingPick: MethodChannel.Result? = null

    private fun pickFolder(result: MethodChannel.Result) {
        if (pendingPick != null) {
            result.error("saf_busy", "A folder pick is already open.", null)
            return
        }
        pendingPick = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
            )
        }
        @Suppress("DEPRECATION")
        startActivityForResult(intent, REQ_PICK_FOLDER)
    }

    @Deprecated("SAF picker result rides the activity result")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQ_PICK_FOLDER) return
        val pending = pendingPick ?: return
        pendingPick = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            pending.success(null) // user cancelled — not an error
            return
        }
        try {
            contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
            )
        } catch (e: Exception) {
            pending.error(
                "saf_grant_failed",
                "Android did not grant lasting access to that folder.",
                null,
            )
            return
        }
        pending.success(
            mapOf(
                "treeUri" to uri.toString(),
                "label" to (safDisplayName(uri) ?: "Selected folder"),
            )
        )
    }

    private fun safDisplayName(treeUri: Uri): String? = try {
        val docUri = DocumentsContract.buildDocumentUriUsingTree(
            treeUri, DocumentsContract.getTreeDocumentId(treeUri))
        contentResolver.query(
            docUri,
            arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
            null, null, null,
        )?.use { c -> if (c.moveToFirst()) c.getString(0) else null }
    } catch (e: Exception) {
        null
    }

    private fun safFolderAccess(treeUri: String?): Boolean {
        if (treeUri == null) return false
        return contentResolver.persistedUriPermissions.any {
            it.uri.toString() == treeUri && it.isReadPermission && it.isWritePermission
        }
    }

    private fun safPostError(
        result: MethodChannel.Result, code: String, message: String?,
    ) {
        mainHandler.post {
            result.error(code, message ?: "Storage operation failed.", null)
        }
    }

    private fun safList(treeUriStr: String?, result: MethodChannel.Result) {
        if (treeUriStr == null) {
            result.error("saf_args", "Missing folder reference.", null)
            return
        }
        safIo.execute {
            try {
                val tree = Uri.parse(treeUriStr)
                val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(
                    tree, DocumentsContract.getTreeDocumentId(tree))
                val entries = mutableListOf<Map<String, Any?>>()
                contentResolver.query(
                    childrenUri,
                    arrayOf(
                        DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                        DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                        DocumentsContract.Document.COLUMN_SIZE,
                        DocumentsContract.Document.COLUMN_LAST_MODIFIED,
                        DocumentsContract.Document.COLUMN_MIME_TYPE,
                    ),
                    null, null, null,
                )?.use { c ->
                    while (c.moveToNext()) {
                        entries.add(
                            mapOf(
                                "documentId" to c.getString(0),
                                "name" to (c.getString(1) ?: ""),
                                "sizeBytes" to
                                    (if (c.isNull(2)) -1L else c.getLong(2)),
                                "modifiedAt" to
                                    (if (c.isNull(3)) 0L else c.getLong(3)),
                                "isDirectory" to
                                    (c.getString(4) ==
                                        DocumentsContract.Document.MIME_TYPE_DIR),
                            )
                        )
                    }
                }
                mainHandler.post { result.success(entries) }
            } catch (e: Exception) {
                safPostError(result, "saf_list_failed", e.message)
            }
        }
    }

    private fun safWrite(
        treeUriStr: String?,
        sourcePath: String?,
        fileName: String?,
        result: MethodChannel.Result,
    ) {
        if (treeUriStr == null || sourcePath == null || fileName == null) {
            result.error("saf_args", "Missing backup write arguments.", null)
            return
        }
        safIo.execute {
            var created: Uri? = null
            try {
                val tree = Uri.parse(treeUriStr)
                val parentDocUri = DocumentsContract.buildDocumentUriUsingTree(
                    tree, DocumentsContract.getTreeDocumentId(tree))
                val source = File(sourcePath)
                created = DocumentsContract.createDocument(
                    contentResolver, parentDocUri, "application/zip",
                    "$fileName.partial",
                ) ?: throw IllegalStateException(
                    "The storage provider refused to create the backup file.")
                val copied = contentResolver.openOutputStream(created)?.use { out ->
                    source.inputStream().use { input -> input.copyTo(out) }
                } ?: throw IllegalStateException(
                    "Could not open the backup file for writing.")
                if (copied != source.length()) {
                    throw IllegalStateException(
                        "The backup write was incomplete.")
                }
                val renamed = DocumentsContract.renameDocument(
                    contentResolver, created, fileName)
                    ?: throw IllegalStateException(
                        "The storage provider refused to finalise the backup file.")
                created = renamed
                mainHandler.post {
                    result.success(
                        mapOf("name" to fileName, "sizeBytes" to source.length()))
                }
            } catch (e: Exception) {
                // Best effort: remove the partial we created. Any
                // pre-existing backup is untouched either way.
                created?.let {
                    try {
                        DocumentsContract.deleteDocument(contentResolver, it)
                    } catch (_: Exception) {
                    }
                }
                safPostError(result, "saf_write_failed", e.message)
            }
        }
    }

    private fun safCopyOut(
        treeUriStr: String?,
        documentId: String?,
        destPath: String?,
        result: MethodChannel.Result,
    ) {
        if (treeUriStr == null || documentId == null || destPath == null) {
            result.error("saf_args", "Missing backup read arguments.", null)
            return
        }
        safIo.execute {
            val dest = File(destPath)
            try {
                val tree = Uri.parse(treeUriStr)
                val docUri = DocumentsContract.buildDocumentUriUsingTree(
                    tree, documentId)
                val copied = contentResolver.openInputStream(docUri)?.use { input ->
                    dest.outputStream().use { out -> input.copyTo(out) }
                } ?: throw IllegalStateException(
                    "Could not open the selected backup.")
                mainHandler.post { result.success(copied) }
            } catch (e: Exception) {
                try {
                    if (dest.exists()) dest.delete()
                } catch (_: Exception) {
                }
                safPostError(result, "saf_read_failed", e.message)
            }
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

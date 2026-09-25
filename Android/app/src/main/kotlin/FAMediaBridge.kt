//
//  FAMediaBridge.kt
//  FurAffinity (Android)
//
//  Kotlin helper backing Save (to the gallery or Downloads), Share and Open in another
//  app. Same rationale and shape as FAImageFetchBridge: FurAffinityUI is a *native* Skip module, so it cannot touch Android
//  framework classes directly and reaches this one by name through SkipBridge's
//  AnyDynamicObject — see MediaBridge.swift.
//
//  Save writes into MediaStore's Pictures/FurAffinity (images) or Download/FurAffinity
//  (documents) collection; see `insert` for the permissions involved.
//
//  Share and Open hand out a content:// URI from the app's FileProvider rather than a file
//  path: the source file lives in a staging directory inside the app's cache, which no
//  other app may read. res/xml/file_paths.xml exposes exactly that directory.
//

package fur.affinity.ui

import android.content.ContentValues
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.util.Log
import android.webkit.MimeTypeMap
import android.widget.Toast
import androidx.core.content.FileProvider
import java.io.File
import skip.foundation.ProcessInfo

class FAMediaBridge {
    fun saveImage(path: String, displayName: String): Boolean = Companion.saveImage(path, displayName)

    fun saveDocument(path: String, displayName: String): Boolean = Companion.saveDocument(path, displayName)

    fun share(path: String, displayName: String): Boolean = Companion.share(path, displayName)

    fun open(path: String, displayName: String): Boolean = Companion.open(path, displayName)

    companion object {
        private const val TAG = "FAMediaBridge"
        private const val ALBUM = "FurAffinity"
        private const val STAGED_FILE_LIFETIME_MS = 60 * 60 * 1000L

        private fun context() = ProcessInfo.processInfo.androidContext

        /// Nil when the extension is missing or unknown. Callers must not substitute
        /// `image/*`: MediaProvider can't derive a file extension from a wildcard, and
        /// the row lands as an extension-less file most gallery apps won't render.
        private fun mimeType(of: String): String? {
            val extension = of.substringAfterLast('.', "").lowercase()
            if (extension.isEmpty()) return null
            return MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension)
        }

        /// Copies `path` into the shared Pictures/FurAffinity collection so it shows up
        /// in the gallery. Returns false (and logs) rather than throwing across JNI.
        fun saveImage(path: String, displayName: String): Boolean {
            val mimeType = mimeType(displayName)
            if (mimeType == null) {
                Log.e(TAG, "saveImage: no MIME type for $displayName")
                return false
            }
            return insert(
                "saveImage",
                path,
                displayName,
                mimeType,
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                "Pictures/$ALBUM"
            )
        }

        /// Copies `path` into Download/FurAffinity, where the Files app shows it, and says
        /// in a toast whether that worked. `MediaStore.Downloads` is API 29+; below that the system share
        /// chooser stands in, as it did for every document before.
        fun saveDocument(path: String, displayName: String): Boolean {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                return share(path, displayName)
            }
            val saved = insert(
                "saveDocument",
                path,
                displayName,
                mimeType(displayName) ?: "application/octet-stream",
                MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                "Download/$ALBUM"
            )
            val message = if (saved) "Saved to Download/$ALBUM" else "Could not save $displayName"
            Handler(Looper.getMainLooper()).post {
                Toast.makeText(context(), message, Toast.LENGTH_SHORT).show()
            }
            return saved
        }

        /// On API 29+ the insert needs no permission at all (scoped storage, IS_PENDING
        /// while writing); on API 28 it needs WRITE_EXTERNAL_STORAGE, which the manifest
        /// declares with maxSdkVersion="28", and ignores `relativePath`.
        private fun insert(
            label: String,
            path: String,
            displayName: String,
            mimeType: String,
            collection: android.net.Uri,
            relativePath: String
        ): Boolean {
            val source = File(path)
            if (!source.isFile) {
                Log.e(TAG, "$label: no file at $path")
                return false
            }

            val resolver = context().contentResolver
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, displayName)
                put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
                    // Hides the row from other apps until the bytes are all there.
                    put(MediaStore.MediaColumns.IS_PENDING, 1)
                }
            }

            // Held so every failure path can delete the row it inserted; an abandoned
            // IS_PENDING row is invisible to the user and never reclaimed.
            var uri: android.net.Uri? = null
            return try {
                uri = resolver.insert(collection, values)
                if (uri == null) {
                    Log.e(TAG, "$label: MediaStore insert returned no URI")
                    return false
                }
                val output = resolver.openOutputStream(uri)
                if (output == null) {
                    Log.e(TAG, "$label: could not open $uri for writing")
                    resolver.delete(uri, null, null)
                    return false
                }
                output.use { stream -> source.inputStream().use { it.copyTo(stream) } }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    values.clear()
                    values.put(MediaStore.MediaColumns.IS_PENDING, 0)
                    resolver.update(uri, values, null, null)
                }
                Log.i(TAG, "$label: wrote $displayName to $uri")
                true
            } catch (e: Exception) {
                Log.e(TAG, "$label failed for $path", e)
                uri?.let { runCatching { resolver.delete(it, null, null) } }
                false
            }
        }

        /// Presents the system chooser to send `path` to another app.
        fun share(path: String, displayName: String): Boolean =
            startChooser("share", path, displayName, Intent.ACTION_SEND) { uri ->
                putExtra(Intent.EXTRA_STREAM, uri)
            }

        /// Presents the system chooser to open `path` in another app, for formats this
        /// one can't show.
        fun open(path: String, displayName: String): Boolean =
            startChooser("open", path, displayName, Intent.ACTION_VIEW) { uri ->
                setDataAndType(uri, type)
            }

        /// The file is copied into a FileProvider-exposed subdirectory first, under its
        /// display name, so the receiving app sees a sensible filename rather than the
        /// cache's hashed one.
        private fun startChooser(
            label: String,
            path: String,
            displayName: String,
            action: String,
            attach: Intent.(android.net.Uri) -> Unit
        ): Boolean {
            val source = File(path)
            if (!source.isFile) {
                Log.e(TAG, "$label: no file at $path")
                return false
            }

            return try {
                val context = context()
                val shared = File(context.cacheDir, "shared")
                // Bounded by age rather than cleared: a player handed an mp3 by Open
                // re-opens the URI to seek, so the last hand-off's file must outlive the
                // next one.
                val stale = System.currentTimeMillis() - STAGED_FILE_LIFETIME_MS
                shared.listFiles()?.filter { it.lastModified() < stale }?.forEach { it.delete() }
                shared.mkdirs()
                val staged = File(shared, displayName)
                // Reuse a copy that is already current, touched so the expiry counts
                // from this hand-off. Otherwise copy under a temporary name of its own
                // (two hand-offs can run at once) and rename, so a reader of the previous
                // copy keeps its inode rather than seeing the file truncated under it.
                if (staged.isFile && staged.length() == source.length() && staged.lastModified() >= source.lastModified()) {
                    staged.setLastModified(System.currentTimeMillis())
                } else {
                    val partial = File(shared, ".$displayName.${java.util.UUID.randomUUID()}.partial")
                    try {
                        source.copyTo(partial, overwrite = true)
                    } catch (e: Exception) {
                        partial.delete()
                        throw e
                    }
                    if (!partial.renameTo(staged)) {
                        partial.delete()
                        Log.e(TAG, "$label: could not stage $displayName")
                        return false
                    }
                }

                val uri = FileProvider.getUriForFile(
                    context,
                    "${context.packageName}.fileprovider",
                    staged
                )
                val intent = Intent(action).apply {
                    // A wildcard is acceptable here, unlike for a MediaStore insert:
                    // the chooser only uses it to pick candidate apps.
                    type = mimeType(displayName) ?: "*/*"
                    attach(uri)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                // Started from outside an Activity context, so the chooser needs its own task.
                val chooser = Intent.createChooser(intent, null).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(chooser)
                true
            } catch (e: Exception) {
                Log.e(TAG, "$label failed for $path", e)
                false
            }
        }
    }
}

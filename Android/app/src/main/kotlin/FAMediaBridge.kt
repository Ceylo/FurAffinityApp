//
//  FAMediaBridge.kt
//  FurAffinity (Android)
//
//  Kotlin helper backing Save-to-gallery and Share. Same rationale and shape as
//  FACoilBridge: FurAffinityUI is a *native* Skip module, so it cannot touch Android
//  framework classes directly and reaches this one by name through SkipBridge's
//  AnyDynamicObject — see MediaBridge.swift.
//
//  Save writes into MediaStore's Pictures/FurAffinity collection. On API 29+ that needs
//  no permission at all (scoped storage, IS_PENDING while writing); on API ≤28 the same
//  insert works but requires WRITE_EXTERNAL_STORAGE, which the manifest declares with
//  maxSdkVersion="28".
//
//  Share hands out a content:// URI from the app's FileProvider rather than a file
//  path: the source file lives in a staging directory inside the app's cache, which no
//  other app may read. res/xml/file_paths.xml exposes exactly that directory.
//

package fur.affinity.ui

import android.content.ContentValues
import android.content.Intent
import android.os.Build
import android.provider.MediaStore
import android.util.Log
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import java.io.File
import skip.foundation.ProcessInfo

class FAMediaBridge {
    fun saveImage(path: String, displayName: String): Boolean = Companion.saveImage(path, displayName)

    fun share(path: String, displayName: String): Boolean = Companion.share(path, displayName)

    companion object {
        private const val TAG = "FAMediaBridge"
        private const val ALBUM = "FurAffinity"

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
            val source = File(path)
            if (!source.isFile) {
                Log.e(TAG, "saveImage: no file at $path")
                return false
            }

            val mimeType = mimeType(displayName)
            if (mimeType == null) {
                Log.e(TAG, "saveImage: no MIME type for $displayName")
                return false
            }

            val resolver = context().contentResolver
            val values = ContentValues().apply {
                put(MediaStore.Images.Media.DISPLAY_NAME, displayName)
                put(MediaStore.Images.Media.MIME_TYPE, mimeType)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/$ALBUM")
                    // Hides the row from other apps until the bytes are all there.
                    put(MediaStore.Images.Media.IS_PENDING, 1)
                }
            }

            // Held so every failure path can delete the row it inserted; an abandoned
            // IS_PENDING row is invisible to the user and never reclaimed.
            var uri: android.net.Uri? = null
            return try {
                uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
                if (uri == null) {
                    Log.e(TAG, "saveImage: MediaStore insert returned no URI")
                    return false
                }
                val output = resolver.openOutputStream(uri)
                if (output == null) {
                    Log.e(TAG, "saveImage: could not open $uri for writing")
                    resolver.delete(uri, null, null)
                    return false
                }
                output.use { stream -> source.inputStream().use { it.copyTo(stream) } }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    values.clear()
                    values.put(MediaStore.Images.Media.IS_PENDING, 0)
                    resolver.update(uri, values, null, null)
                }
                Log.i(TAG, "saveImage: wrote $displayName to $uri")
                true
            } catch (e: Exception) {
                Log.e(TAG, "saveImage failed for $path", e)
                uri?.let { runCatching { resolver.delete(it, null, null) } }
                false
            }
        }

        /// Presents the system chooser for `path`. The file is copied into a
        /// FileProvider-exposed subdirectory first, under its display name, so the
        /// receiving app sees a sensible filename rather than the cache's hashed one.
        fun share(path: String, displayName: String): Boolean {
            val source = File(path)
            if (!source.isFile) {
                Log.e(TAG, "share: no file at $path")
                return false
            }

            return try {
                val context = context()
                val shared = File(context.cacheDir, "shared")
                // One share at a time: clearing first bounds this directory, and avoids
                // rewriting a file under a receiving app still reading the URI we
                // granted it for the same name a moment ago.
                shared.deleteRecursively()
                shared.mkdirs()
                val staged = File(shared, displayName)
                source.copyTo(staged, overwrite = true)

                val uri = FileProvider.getUriForFile(
                    context,
                    "${context.packageName}.fileprovider",
                    staged
                )
                val intent = Intent(Intent.ACTION_SEND).apply {
                    // A wildcard is acceptable here, unlike for a MediaStore insert:
                    // the chooser only uses it to pick candidate apps.
                    type = mimeType(displayName) ?: "*/*"
                    putExtra(Intent.EXTRA_STREAM, uri)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                // Started from outside an Activity context, so the chooser needs its own task.
                val chooser = Intent.createChooser(intent, null).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(chooser)
                true
            } catch (e: Exception) {
                Log.e(TAG, "share failed for $path", e)
                false
            }
        }
    }
}

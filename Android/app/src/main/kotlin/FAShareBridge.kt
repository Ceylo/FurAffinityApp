//
//  FAShareBridge.kt
//  FurAffinity (Android)
//
//  Kotlin helper for sharing a file out of the app. SkipUI's `ShareLink` only carries
//  plain text, so exporting the log file goes through `ACTION_SEND` with a
//  `FileProvider` URI instead — the app's temporary directory is private storage, so
//  a `file://` URI would fault in the receiving app.
//
//  Called from Swift by class name through SkipBridge's AnyDynamicObject; lives in the
//  app Gradle module for the same reason FACoilBridge does, and because the
//  `<provider>` it needs is declared in the app's manifest. See AndroidSharing.swift.
//

package fur.affinity.ui

import android.content.Intent
import android.util.Log
import androidx.core.content.FileProvider
import skip.foundation.ProcessInfo
import java.io.File

class FAShareBridge {
    // Returns a value (not Unit) so the Swift AnyDynamicObject call resolves to a typed
    // overload instead of the ambiguous void one.
    fun shareFile(path: String, mimeType: String): Boolean = Companion.shareFile(path, mimeType)

    companion object {
        private const val TAG = "FAShareBridge"

        fun shareFile(path: String, mimeType: String): Boolean {
            return try {
                val context = ProcessInfo.processInfo.androidContext
                // Must match the authority in AndroidManifest.xml, which is derived from
                // the *installed* application id — not the Swift module's namespace.
                val authority = context.packageName + ".fileprovider"
                val uri = FileProvider.getUriForFile(context, authority, File(path))

                val send = Intent(Intent.ACTION_SEND)
                send.type = mimeType
                send.putExtra(Intent.EXTRA_STREAM, uri)
                send.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)

                val chooser = Intent.createChooser(send, null)
                // Started from the application context, which has no task of its own.
                chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                chooser.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                context.startActivity(chooser)
                true
            } catch (e: Exception) {
                Log.e(TAG, "shareFile failed for $path: $e")
                false
            }
        }
    }
}

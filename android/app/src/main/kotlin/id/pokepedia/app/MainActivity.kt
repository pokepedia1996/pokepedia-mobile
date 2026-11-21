package id.pokepedia.app

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Sharing straight to one app, which share_plus can't target. Each
        // call answers false when the app isn't installed, and Dart falls
        // back to the system share sheet. Anything else is reported as an
        // error so it gets logged instead of passing for "not installed".
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "instagramStory" -> result.success(
                            shareToInstagramStory(
                                call.argument<String>("path"),
                                call.argument<String>("appId"),
                            ),
                        )
                        "whatsapp" -> result.success(
                            shareToWhatsApp(
                                call.argument<String>("path"),
                                call.argument<String>("text"),
                            ),
                        )
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("share_failed", e.message, null)
                }
            }
    }

    /// Only files under cache/social_share/ resolve (see
    /// res/xml/social_share_paths.xml); anything else throws.
    private fun shareUri(path: String): Uri =
        FileProvider.getUriForFile(this, "$packageName.social_share", File(path))

    private fun shareToInstagramStory(path: String?, appId: String?): Boolean {
        requireNotNull(path) { "path required" }
        requireNotNull(appId) { "appId required" }
        // The intent's read grant covers Instagram for as long as it needs
        // the file; no lasting grantUriPermission.
        val intent = Intent("com.instagram.share.ADD_TO_STORY").apply {
            putExtra("source_application", appId)
            setDataAndType(shareUri(path), "image/png")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            setPackage(INSTAGRAM)
        }
        return start(intent)
    }

    /// WhatsApp, then WhatsApp Business: plenty of sellers only have the
    /// latter.
    private fun shareToWhatsApp(path: String?, text: String?): Boolean {
        requireNotNull(path) { "path required" }
        val uri = shareUri(path)
        return WHATSAPPS.any { pkg ->
            start(
                Intent(Intent.ACTION_SEND).apply {
                    type = "image/png"
                    putExtra(Intent.EXTRA_STREAM, uri)
                    if (text != null) putExtra(Intent.EXTRA_TEXT, text)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    setPackage(pkg)
                },
            )
        }
    }

    /// False only when no app takes the intent, i.e. it isn't installed.
    private fun start(intent: Intent): Boolean = try {
        startActivity(intent)
        true
    } catch (_: ActivityNotFoundException) {
        false
    }

    private companion object {
        const val CHANNEL = "id.pokepedia.app/social_share"
        const val INSTAGRAM = "com.instagram.android"
        val WHATSAPPS = listOf("com.whatsapp", "com.whatsapp.w4b")
    }
}

package com.liuguang.liuguang

import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import java.security.MessageDigest
import android.content.ContentValues
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val executor = Executors.newSingleThreadExecutor()
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "liuguang/native").setMethodCallHandler { call, result ->
            when (call.method) {
                "currentLauncherIcon" -> result.success(LauncherIcons.current(this))
                "launcherIconPreview" -> {
                    try { result.success(LauncherIcons.preview(this,call.argument<String>("id") ?: "default")) }
                    catch(e:Exception) { result.error("icon_preview",e.message,null) }
                }
                "setLauncherIcon" -> {
                    try { LauncherIcons.apply(this,call.argument<String>("id") ?: "default");result.success(null) }
                    catch(e:Exception) { result.error("icon_change",e.message,null) }
                }
                "configureUpdates" -> {
                    UpdateScheduler.configure(this, call.argument<Boolean>("enabled") ?: true, call.argument<Boolean>("notify") ?: true, call.argument<String>("source") ?: "gitee", call.argument<String>("version") ?: "1.0.0")
                    if (call.argument<Boolean>("requestPermission") == true && Build.VERSION.SDK_INT >= 33 && checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 915)
                    result.success(null)
                }
                "installUpdate" -> {
                    try {
                        val file = File(call.argument<String>("path") ?: error("未指定安装包")).canonicalFile
                        check(file.path.startsWith(cacheDir.canonicalPath + File.separator)) { "安装包必须位于应用缓存目录" }
                        val archive = packageManager.getPackageArchiveInfo(file.path, PackageManager.GET_SIGNING_CERTIFICATES) ?: error("安装包无效")
                        check(archive.packageName == packageName) { "安装包包名不匹配" }
                        val expected = "7298c7e695fd825f5b9b981da4c0d77458a849aa35d21058e35a8fc8044f70a6"
                        val signers = archive.signingInfo?.apkContentsSigners ?: error("无签名信息")
                        check(signers.isNotEmpty() && signers.all { signature -> MessageDigest.getInstance("SHA-256").digest(signature.toByteArray()).joinToString("") { "%02x".format(it.toInt() and 255) } == expected }) { "签名不匹配" }
                        val current = packageManager.getPackageInfo(packageName, 0)
                        check(archive.longVersionCode >= current.longVersionCode) { "不允许降级" }
                        if (!packageManager.canRequestPackageInstalls()) {
                            startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, android.net.Uri.parse("package:$packageName")))
                            result.error("permission", "请允许安装未知应用，然后重试", null)
                        } else {
                            val uri = FileProvider.getUriForFile(this, "$packageName.update_provider", file)
                            startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/vnd.android.package-archive").addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
                            result.success(null)
                        }
                    } catch (e: Exception) { result.error("install", e.message, null) }
                }
                "saveToGallery" -> {
                    val path = call.argument<String>("path")
                    if (path == null) { result.error("invalid", "未指定图片", null); return@setMethodCallHandler }
                    executor.execute {
                        var uri: android.net.Uri? = null
                        try {
                            val file = File(path)
                            val mime = when (file.extension.lowercase()) { "jpg", "jpeg" -> "image/jpeg"; "webp" -> "image/webp"; "gif" -> "image/gif"; else -> "image/png" }
                            val values = ContentValues().apply {
                                put(MediaStore.Images.Media.DISPLAY_NAME, "Liuguang_${System.currentTimeMillis()}.${file.extension}")
                                put(MediaStore.Images.Media.MIME_TYPE, mime)
                                put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/琉光")
                                put(MediaStore.Images.Media.IS_PENDING, 1)
                            }
                            uri = contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
                                ?: error("无法创建相册文件")
                            contentResolver.openOutputStream(uri)?.use { output -> file.inputStream().use { it.copyTo(output) } }
                                ?: error("无法写入相册")
                            values.clear(); values.put(MediaStore.Images.Media.IS_PENDING, 0)
                            contentResolver.update(uri, values, null, null)
                            runOnUiThread { result.success(uri.toString()) }
                        } catch (e: Exception) {
                            uri?.let { contentResolver.delete(it, null, null) }
                            runOnUiThread { result.error("save", e.message, null) }
                        }
                    }
                }
                "encodeWebp" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    val quality = call.argument<Int>("quality") ?: 90
                    executor.execute {
                        try {
                            val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes!!.size) ?: error("无法读取图片")
                            val stream = ByteArrayOutputStream()
                            @Suppress("DEPRECATION")
                            val format = if (android.os.Build.VERSION.SDK_INT >= 30) Bitmap.CompressFormat.WEBP_LOSSY else Bitmap.CompressFormat.WEBP
                            check(bitmap.compress(format, quality.coerceIn(1, 100), stream))
                            bitmap.recycle()
                            runOnUiThread { result.success(stream.toByteArray()) }
                        } catch (e: Exception) { runOnUiThread { result.error("encode", e.message, null) } }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
    override fun onDestroy() { executor.shutdown(); super.onDestroy() }
}

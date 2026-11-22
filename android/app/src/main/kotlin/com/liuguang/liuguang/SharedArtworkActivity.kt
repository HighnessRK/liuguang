package com.liuguang.liuguang

import android.app.Activity
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.os.Bundle
import android.view.Gravity
import android.view.ScaleGestureDetector
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.TextView
import com.itgsa.animation.sharedview.ViewAnimationConfig
import com.itgsa.animation.sharedview.ViewAnimationManager
import com.itgsa.animation.sharedview.ViewAnimationType
import java.io.File

internal fun previewBitmap(file: File, limit: Int): Bitmap? {
    val size = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    BitmapFactory.decodeFile(file.path, size)
    if (size.outWidth < 1 || size.outHeight < 1) return null
    var sample = 1
    while (maxOf(size.outWidth, size.outHeight) / sample > limit) sample *= 2
    return BitmapFactory.decodeFile(file.path, BitmapFactory.Options().apply { inSampleSize = sample })
}

class SharedArtworkActivity : Activity() {
    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        val path = intent.getStringExtra("path")
        if (path == null) { finish(); return }
        window.statusBarColor = Color.BLACK
        window.navigationBarColor = Color.BLACK
        val root = FrameLayout(this).apply { setBackgroundColor(Color.BLACK) }
        val image = ImageView(this).apply {
            scaleType = ImageView.ScaleType.FIT_CENTER
            contentDescription = "作品大图"
        }
        root.addView(image, FrameLayout.LayoutParams(-1, -1))
        val detector = ScaleGestureDetector(this, object : ScaleGestureDetector.SimpleOnScaleGestureListener() {
            override fun onScale(detector: ScaleGestureDetector): Boolean {
                val scale = (image.scaleX * detector.scaleFactor).coerceIn(1f, 5f)
                image.scaleX = scale
                image.scaleY = scale
                if (scale == 1f) { image.translationX = 0f; image.translationY = 0f }
                return true
            }
        })
        var lastX = 0f
        var lastY = 0f
        image.setOnTouchListener { _, event ->
            detector.onTouchEvent(event)
            if (event.actionMasked == android.view.MotionEvent.ACTION_MOVE && !detector.isInProgress && image.scaleX > 1f && event.pointerCount == 1) {
                val x = image.width * (image.scaleX - 1f) / 2f
                val y = image.height * (image.scaleY - 1f) / 2f
                image.translationX = (image.translationX + event.rawX - lastX).coerceIn(-x, x)
                image.translationY = (image.translationY + event.rawY - lastY).coerceIn(-y, y)
            }
            lastX = event.rawX
            lastY = event.rawY
            true
        }
        val inset = (12 * resources.displayMetrics.density).toInt()
        val side = (48 * resources.displayMetrics.density).toInt()
        val close = TextView(this).apply {
            text = "×"
            contentDescription = "关闭大图"
            gravity = Gravity.CENTER
            textSize = 28f
            setTextColor(Color.WHITE)
            setOnClickListener { finish() }
        }
        root.addView(close, FrameLayout.LayoutParams(side, side, Gravity.TOP or Gravity.END).apply { topMargin = inset; marginEnd = inset })
        root.setOnApplyWindowInsetsListener { _, insets ->
            val top = if (android.os.Build.VERSION.SDK_INT >= 30) insets.getInsets(android.view.WindowInsets.Type.systemBars()).top else insets.systemWindowInsetTop
            (close.layoutParams as FrameLayout.LayoutParams).let { lp -> lp.topMargin = maxOf(inset, top + inset); close.layoutParams = lp }
            insets
        }
        setContentView(root)
        kotlin.concurrent.thread(name = "liuguang-preview", isDaemon = true) {
            val bitmap = previewBitmap(File(path), 3072)
            runOnUiThread { if (!isFinishing && !isDestroyed) image.setImageBitmap(bitmap) }
        }
    }

    override fun finish() {
        // The Flutter route is underneath this Activity and may have changed bounds.
        runCatching {
            ViewAnimationManager.overrideViewAnimationTransition(this,
                ViewAnimationConfig().setBackAnimType(ViewAnimationType.VIEW_ANIM_FADE_OUT).toBundle())
        }
        super.finish()
    }
}

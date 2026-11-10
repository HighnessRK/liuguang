package com.liuguang.liuguang

import android.content.Context
import android.content.ComponentName
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.Build
import java.io.ByteArrayOutputStream

object LauncherIcons {
    private val ids = listOf("default", "spark_blue_glass", "spark_blue_frost", "spark_blue_ceramic", "spark_blue_plush", "spark_violet_glass", "spark_violet_frost", "spark_violet_ceramic", "spark_violet_plush", "spark_rose_glass", "spark_rose_frost", "spark_rose_ceramic", "spark_rose_plush", "spark_teal_glass", "spark_teal_frost", "spark_teal_ceramic", "spark_teal_plush", "spark_amber_glass", "spark_amber_frost", "spark_amber_ceramic", "spark_amber_plush", "spark_graphite_glass", "spark_graphite_frost", "spark_graphite_ceramic", "spark_graphite_plush", "aperture_blue_glass", "aperture_blue_frost", "aperture_blue_ceramic", "aperture_blue_plush", "aperture_violet_glass", "aperture_violet_frost", "aperture_violet_ceramic", "aperture_violet_plush", "aperture_rose_glass", "aperture_rose_frost", "aperture_rose_ceramic", "aperture_rose_plush", "aperture_teal_glass", "aperture_teal_frost", "aperture_teal_ceramic", "aperture_teal_plush", "aperture_amber_glass", "aperture_amber_frost", "aperture_amber_ceramic", "aperture_amber_plush", "aperture_graphite_glass", "aperture_graphite_frost", "aperture_graphite_ceramic", "aperture_graphite_plush", "orb_blue_glass", "orb_blue_frost", "orb_blue_ceramic", "orb_blue_plush", "orb_violet_glass", "orb_violet_frost", "orb_violet_ceramic", "orb_violet_plush", "orb_rose_glass", "orb_rose_frost", "orb_rose_ceramic", "orb_rose_plush", "orb_teal_glass", "orb_teal_frost", "orb_teal_ceramic", "orb_teal_plush", "orb_amber_glass", "orb_amber_frost", "orb_amber_ceramic", "orb_amber_plush", "orb_graphite_glass", "orb_graphite_frost", "orb_graphite_ceramic", "orb_graphite_plush", "orbit_blue_glass", "orbit_blue_frost", "orbit_blue_ceramic", "orbit_blue_plush", "orbit_violet_glass", "orbit_violet_frost", "orbit_violet_ceramic", "orbit_violet_plush", "orbit_rose_glass", "orbit_rose_frost", "orbit_rose_ceramic", "orbit_rose_plush", "orbit_teal_glass", "orbit_teal_frost", "orbit_teal_ceramic", "orbit_teal_plush", "orbit_amber_glass", "orbit_amber_frost", "orbit_amber_ceramic", "orbit_amber_plush", "orbit_graphite_glass", "orbit_graphite_frost", "orbit_graphite_ceramic", "orbit_graphite_plush")
    private fun name(id: String) = if(id == "default") "LauncherDefault" else "Launcher_" + id
    fun current(context: Context): String = context.getSharedPreferences("liuguang_icon",0).getString("selected","default") ?: "default"
    fun apply(context: Context, id: String) {
        require(ids.contains(id)) { "Unknown launcher icon" }
        val manager = context.packageManager
        fun component(key: String) = ComponentName(context,context.packageName + "." + name(key))
        if(Build.VERSION.SDK_INT >= 33) {
            manager.setComponentEnabledSettings(ids.map { key -> PackageManager.ComponentEnabledSetting(
                component(key), if(key == id) PackageManager.COMPONENT_ENABLED_STATE_ENABLED else PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                PackageManager.DONT_KILL_APP) })
        } else {
            manager.setComponentEnabledSetting(component(id), PackageManager.COMPONENT_ENABLED_STATE_ENABLED,PackageManager.DONT_KILL_APP)
            ids.filter { it != id }.forEach { manager.setComponentEnabledSetting(component(it), PackageManager.COMPONENT_ENABLED_STATE_DISABLED,PackageManager.DONT_KILL_APP) }
        }
        context.getSharedPreferences("liuguang_icon",0).edit().putString("selected",id).apply()
    }
    fun preview(context: Context,id: String): ByteArray {
        require(ids.contains(id))
        val resource = if(id=="default") context.applicationInfo.icon else context.resources.getIdentifier("launcher_"+id,"mipmap",context.packageName)
        val drawable=context.getDrawable(resource) ?: error("Icon unavailable")
        val bitmap=Bitmap.createBitmap(256,256,Bitmap.Config.ARGB_8888)
        drawable.setBounds(0,0,256,256); drawable.draw(Canvas(bitmap))
        val stream=ByteArrayOutputStream(); bitmap.compress(Bitmap.CompressFormat.PNG,100,stream);bitmap.recycle()
        return stream.toByteArray()
    }
}

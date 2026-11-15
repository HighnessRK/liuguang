"""Build/run a signed local probe against the installed app without replacing its APK/data.
No model API calls. Verifies TRIM/KILL Binder acknowledgements and local foreground service.
"""
from pathlib import Path
import os, subprocess, zipfile, argparse, shutil, time
ROOT = Path(__file__).resolve().parents[1]
SDK = Path(os.environ.get('LOCALAPPDATA', r'C:\Users\59222\AppData\Local')) / 'Android/Sdk'
JBR = Path(os.environ.get('JAVA_HOME', r'E:\ProgramFiles\Android\jbr'))
CACHE = ROOT / 'tools/.cache/memory-probe'
SOURCE = r'''
package com.liuguang.qa;
import android.app.*;
import android.content.*;
import android.os.*;
import java.util.concurrent.*;
public class MemoryProbe extends Instrumentation {
  private boolean exportShares = false;
  @Override public void onCreate(Bundle args) { super.onCreate(args); exportShares = args != null && "true".equals(args.getString("exportShares")); start(); }
  @Override public void onStart() {
    Bundle results = new Bundle();
    Intent service = new Intent().setClassName("com.liuguang.liuguang", "com.liuguang.liuguang.ProcessingService");
    try {
      Intent launch = new Intent().setClassName("com.liuguang.liuguang", "com.liuguang.liuguang.MainActivity");
      launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
      Activity activity = startActivitySync(launch);
      Thread.sleep(1800);
      getTargetContext().startForegroundService(service.putExtra("local", true).putExtra("cloud", false));
      Thread.sleep(800);
      ActivityManager manager = (ActivityManager)getTargetContext().getSystemService(Context.ACTIVITY_SERVICE);
      boolean foreground = false;
      for (ActivityManager.RunningServiceInfo s : manager.getRunningServices(100)) {
        if (s.service.getClassName().endsWith("ProcessingService")) foreground = s.foreground;
      }
      if (!foreground) throw new AssertionError("local foreground service was not running");
      runOnMainSync(() -> activity.moveTaskToBack(true));
      Thread.sleep(350);
      for (int i = 0; i < 2; i++) {
        final int expectedType = i + 1, expectedId = 10500 + i;
        CountDownLatch latch = new CountDownLatch(1);
        final String[] error = new String[1];
        final long started = SystemClock.elapsedRealtime();
        final long[] elapsed = new long[1];
        Binder callback = new Binder() {
          @Override protected boolean onTransact(int code, Parcel data, Parcel reply, int flags) {
            int type = data.readInt(), id = data.readInt(), status = data.readInt();
            elapsed[0] = SystemClock.elapsedRealtime() - started;
            if (type != expectedType || id != expectedId || status != 0) error[0] = "invalid ack: " + type + "/" + id + "/" + status;
            latch.countDown(); return true;
          }
        };
        Bundle common = new Bundle(); common.putBinder("callback", callback); common.putInt("notifyType", expectedType); common.putInt("notifyId", expectedId);
        String action = i == 0 ? "itgsa.intent.action.TRIM" : "itgsa.intent.action.KILL";
        getTargetContext().sendBroadcast(new Intent(action).setPackage("com.liuguang.liuguang").putExtra("common", common));
        if (!latch.await(3, TimeUnit.SECONDS)) throw new AssertionError(action + " missed 3s deadline");
        if (error[0] != null) throw new AssertionError(error[0]);
        results.putLong(i == 0 ? "trim_ack_ms" : "kill_ack_ms", elapsed[0]);
      }
      results.putString("local_foreground", "passed");
      android.graphics.Bitmap sample = android.graphics.Bitmap.createBitmap(64, 48, android.graphics.Bitmap.Config.ARGB_8888);
      java.io.ByteArrayOutputStream encoded = new java.io.ByteArrayOutputStream();
      sample.compress(android.graphics.Bitmap.CompressFormat.WEBP_LOSSY, 88, encoded); sample.recycle();
      android.graphics.Bitmap restored = android.graphics.BitmapFactory.decodeByteArray(encoded.toByteArray(), 0, encoded.size());
      if (restored.getWidth() != 64 || restored.getHeight() != 48) throw new AssertionError("WebP dimensions changed");
      restored.recycle(); results.putString("webp_encoding", "64x48 passed");
      if (exportShares) {
        java.io.File shared = new java.io.File(getTargetContext().getFilesDir(), "studio/share_cache");
        java.io.File[] cards = shared.listFiles((dir, name) -> name.endsWith(".png"));
        if (cards != null) for (java.io.File card : cards) {
          android.content.ContentValues values = new android.content.ContentValues();
          values.put(android.provider.MediaStore.Downloads.DISPLAY_NAME, "liuguang_qa_" + card.getName());
          values.put(android.provider.MediaStore.Downloads.MIME_TYPE, "image/png");
          values.put(android.provider.MediaStore.Downloads.RELATIVE_PATH, "Download/LiuguangQA");
          values.put(android.provider.MediaStore.Downloads.IS_PENDING, 1);
          android.net.Uri uri = getTargetContext().getContentResolver().insert(android.provider.MediaStore.Downloads.EXTERNAL_CONTENT_URI, values);
          try (java.io.OutputStream out = getTargetContext().getContentResolver().openOutputStream(uri)) { java.nio.file.Files.copy(card.toPath(), out); }
          values.clear(); values.put(android.provider.MediaStore.Downloads.IS_PENDING, 0); getTargetContext().getContentResolver().update(uri, values, null, null);
        }
        java.io.File old = new java.io.File(getTargetContext().getExternalFilesDir(null), "local-qa");
        java.io.File[] leftovers = old.listFiles((dir, name) -> name.endsWith(".png"));
        if (leftovers != null) for (java.io.File f : leftovers) f.delete(); old.delete();
        results.putInt("share_cards_exported", cards == null ? 0 : cards.length);
      }
      getTargetContext().stopService(service);
      getTargetContext().startActivity(launch);
      results.putString("result", "PASS");
      finish(Activity.RESULT_OK, results);
    } catch (Throwable error) {
      getTargetContext().stopService(service);
      results.putString("result", "FAIL: " + error.toString()); finish(Activity.RESULT_CANCELED, results);
    }
  }
}
'''
def run(args, **kw):
    return subprocess.run([str(a) for a in args], check=True, **kw)
def main():
    parser = argparse.ArgumentParser(); parser.add_argument('--device', default='b39ee542'); parser.add_argument('--build-only', action='store_true'); parser.add_argument('--export-shares', action='store_true'); args = parser.parse_args()
    CACHE.mkdir(parents=True, exist_ok=True)
    tools = SDK / 'build-tools/37.0.0'; android = SDK / 'platforms/android-36/android.jar'
    source = CACHE/'MemoryProbe.java'; source.write_text(SOURCE, encoding='utf-8')
    classes = CACHE/'classes'; classes.mkdir(exist_ok=True)
    manifest = CACHE/'AndroidManifest.xml'; manifest.write_text('''<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="com.liuguang.qa" android:versionCode="1" android:versionName="1"><uses-sdk android:minSdkVersion="29" android:targetSdkVersion="36"/><application android:label="琉光本地核查"/><instrumentation android:name="com.liuguang.qa.MemoryProbe" android:targetPackage="com.liuguang.liuguang" android:functionalTest="true"/></manifest>''',encoding='utf-8')
    run([JBR/'bin/javac.exe', '-encoding', 'UTF-8', '-source', '8', '-target', '8', '-cp', android, '-d', classes, source])
    run([JBR/'bin/java.exe', '-cp', tools/'lib/d8.jar', 'com.android.tools.r8.D8', '--lib', android, '--min-api', '29', '--output', CACHE, *classes.rglob('*.class')])
    unsigned = CACHE/'unsigned.apk'; run([tools/'aapt2.exe', 'link', '-o', unsigned, '--manifest', manifest, '-I', android])
    with zipfile.ZipFile(unsigned, 'a') as archive: archive.write(CACHE/'classes.dex', 'classes.dex')
    aligned = CACHE/'aligned.apk'; run([tools/'zipalign.exe', '-f', '4', unsigned, aligned])
    props = {}
    for line in (ROOT/'android/key.properties').read_text(encoding='utf-8-sig').splitlines():
        if '=' in line: k,v=line.split('=',1); props[k.strip()] = v.strip().replace('\\\\','\\')
    environment = dict(os.environ, LIUGUANG_PROBE_STORE_PASS=props['storePassword'], LIUGUANG_PROBE_KEY_PASS=props['keyPassword'])
    store_file = Path(props['storeFile']); store_file = store_file if store_file.is_absolute() else ROOT/'android/app'/store_file
    result = CACHE/'memory-qa.apk'
    run([JBR/'bin/java.exe','-jar',tools/'lib/apksigner.jar','sign','--ks',store_file,'--ks-key-alias',props['keyAlias'],'--ks-pass','env:LIUGUANG_PROBE_STORE_PASS','--key-pass','env:LIUGUANG_PROBE_KEY_PASS','--out',result,aligned],env=environment)
    print('Built local memory probe:', result)
    if not args.build_only:
        run([shutil.which('pwsh') or 'powershell','-NoProfile','-File',ROOT/'tools/install.ps1','-Device',args.device,'-Apk',result])
        command = [str(SDK/'platform-tools/adb.exe'), '-s', args.device, 'shell', 'am', 'instrument', '-w', '-e', 'exportShares', str(args.export_shares).lower(), 'com.liuguang.qa/com.liuguang.qa.MemoryProbe']
        process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding='utf-8', errors='replace')
        time.sleep(1)
        # HyperOS can hold instrumentation's background activity launch; a shell launch is permitted.
        run([SDK/'platform-tools/adb.exe', '-s', args.device, 'shell', 'am', 'start', '-n', 'com.liuguang.liuguang/.MainActivity'], stdout=subprocess.DEVNULL)
        try: output, _ = process.communicate(timeout=35)
        except subprocess.TimeoutExpired:
            process.terminate(); raise RuntimeError('Local device probe timed out; app data has not been cleared')
        print(output)
        if 'result=PASS' not in output: raise RuntimeError('Local memory/foreground probe failed')
if __name__ == '__main__': main()

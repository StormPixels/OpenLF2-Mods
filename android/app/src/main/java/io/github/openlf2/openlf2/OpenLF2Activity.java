package io.github.openlf2.openlf2;

import android.Manifest;
import android.content.Intent;
import android.content.pm.ActivityInfo;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Environment;
import android.os.Process;
import android.provider.Settings;
import android.util.Log;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import org.libsdl.app.SDLActivity;

/** Stages only the project's Lua modules before SDL starts the native entry point. */
public final class OpenLF2Activity extends SDLActivity {
    private static final String TAG = "OpenLF2";

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        try {
            copyAssetTree("scripts", new File(getFilesDir(), "scripts"));
        } catch (IOException error) {
            Log.e(TAG, "Could not stage Lua modules", error);
            throw new IllegalStateException("Could not stage Lua modules", error);
        }
        requestStorageAccess();
        super.onCreate(savedInstanceState);
    }

    /**
     * The game data is read from /storage/emulated/0/LF2_ENGINE, outside the app's own folders: Android 11+
     * needs "All files access", older versions the storage permission. Until it is granted the native
     * side shows LF2_ENGINE NOT INSTALLED; grant it and start OpenLF2 again.
     */
    private void requestStorageAccess() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                if (!Environment.isExternalStorageManager()) {
                    Intent intent = new Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                            Uri.parse("package:" + getPackageName()));
                    startActivity(intent);
                }
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M
                    && checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE)
                            != PackageManager.PERMISSION_GRANTED) {
                requestPermissions(new String[] {
                        Manifest.permission.READ_EXTERNAL_STORAGE,
                        Manifest.permission.WRITE_EXTERNAL_STORAGE}, 1);
            }
        } catch (RuntimeException error) {
            Log.e(TAG, "Could not request storage access", error);
        }
    }

    /**
     * The options page picked another game: native code leaves restart_requested in the files directory and
     * returns, which makes SDL finish this activity. The app then starts again in a fresh process (through
     * RestartActivity, which starts while this activity is still visible) and opens the picked game.
     */
    @Override
    public void finish() {
        File marker = new File(getFilesDir(), "restart_requested");
        if (marker.exists()) {
            marker.delete();
            try {
                Intent relaunch = getPackageManager().getLaunchIntentForPackage(getPackageName());
                if (relaunch != null) {
                    relaunch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK);
                    Intent restart = new Intent(this, RestartActivity.class);
                    restart.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                    restart.putExtra(RestartActivity.EXTRA_RELAUNCH, relaunch);
                    restart.putExtra(RestartActivity.EXTRA_PID, Process.myPid());
                    startActivity(restart);
                }
            } catch (RuntimeException error) {
                Log.e(TAG, "Could not restart", error);
            }
        }
        super.finish();
    }

    @Override
    public void setOrientationBis(int width, int height, boolean resizable, String hint) {
        setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE);
    }

    /**
     * getFilesDir(), passed to native main() as its first argument. The native entry point
     * (src/adapters/sdl/entry.cpp) used to ask SDL for this same directory instead
     * (SDL_GetAndroidInternalStoragePath()), but that returned a pointer that was not safely
     * readable by the time native code ran; this Activity already has the same path reliably,
     * from staging the Lua modules above.
     */
    @Override
    protected String[] getArguments() {
        return new String[] {getFilesDir().getAbsolutePath()};
    }

    private void copyAssetTree(String assetPath, File destination) throws IOException {
        String[] children = getAssets().list(assetPath);
        if (children == null) {
            throw new IOException("Cannot list " + assetPath);
        }
        if (children.length > 0) {
            if (!destination.isDirectory() && !destination.mkdirs()) {
                throw new IOException("Cannot create " + destination);
            }
            for (String child : children) {
                copyAssetTree(assetPath + "/" + child, new File(destination, child));
            }
            return;
        }
        try (InputStream source = getAssets().open(assetPath);
             OutputStream target = new FileOutputStream(destination)) {
            byte[] buffer = new byte[8192];
            int count;
            while ((count = source.read(buffer)) != -1) {
                target.write(buffer, 0, count);
            }
        }
    }
}

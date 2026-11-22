package io.github.openlf2.openlf2;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;
import android.os.Process;
import android.util.Log;

/**
 * Runs in its own process (see AndroidManifest.xml) so it survives the main process: it ends that process,
 * then starts the app again. Used when the options page picks another game.
 */
public final class RestartActivity extends Activity {
    static final String EXTRA_RELAUNCH = "relaunch";
    static final String EXTRA_PID = "pid";

    @Override
    @SuppressWarnings("deprecation")
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        try {
            Intent relaunch = getIntent().getParcelableExtra(EXTRA_RELAUNCH);
            int pid = getIntent().getIntExtra(EXTRA_PID, -1);
            if (relaunch != null) startActivity(relaunch);
            if (pid > 0) Process.killProcess(pid);
        } catch (RuntimeException error) {
            Log.e("OpenLF2", "Restart failed", error);
        }
        finish();
        Runtime.getRuntime().exit(0);
    }
}

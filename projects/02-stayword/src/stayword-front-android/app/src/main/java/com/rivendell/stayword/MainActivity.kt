package com.rivendell.stayword

import android.os.Bundle
import android.content.Intent
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.viewmodel.compose.viewModel
import com.rivendell.stayword.ui.StayWordApp
import com.rivendell.stayword.ui.StayWordViewModel
import com.rivendell.stayword.ui.theme.StayWordTheme

class MainActivity : ComponentActivity() {
    private var deepLink by mutableStateOf<String?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        deepLink = intent?.dataString
        enableEdgeToEdge()
        setContent {
            StayWordTheme {
                val stayWordViewModel: StayWordViewModel = viewModel(
                    factory = StayWordViewModel.factory(appContainer),
                )
                StayWordApp(
                    viewModel = stayWordViewModel,
                    deepLink = deepLink,
                    onDeepLinkConsumed = { deepLink = null },
                )
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        deepLink = intent.dataString
    }
}

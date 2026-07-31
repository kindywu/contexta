package com.ak.contexta

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.ak.contexta.navigation.ContextaNavGraph
import com.ak.contexta.navigation.Screen
import com.ak.contexta.ui.components.BottomNavBar
import com.ak.contexta.ui.components.BottomNavTab
import com.ak.contexta.ui.theme.ContextaTheme
import dagger.hilt.android.AndroidEntryPoint

@AndroidEntryPoint
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            ContextaTheme {
                ContextaApp()
            }
        }
    }
}

@Composable
private fun ContextaApp() {
    val navController = rememberNavController()
    val navBackStackEntry by navController.currentBackStackEntryAsState()
    val currentRoute = navBackStackEntry?.destination?.route

    // Show bottom nav only on main tab screens
    val showBottomBar = currentRoute in listOf(
        Screen.Home.route,
        Screen.Reference.route,
        Screen.Settings.route
    )
    val currentTab = BottomNavTab.entries.find { it.route == currentRoute }

    Scaffold(
        modifier = Modifier.fillMaxSize(),
        bottomBar = {
            if (showBottomBar && currentTab != null) {
                BottomNavBar(
                    selectedTab = currentTab,
                    onTabSelected = { tab ->
                        navController.navigate(tab.route) {
                            launchSingleTop = true
                        }
                    }
                )
            }
        }
    ) { innerPadding ->
        ContextaNavGraph(
            navController = navController,
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
        )
    }
}

@Preview(showBackground = true)
@Composable
fun DefaultPreview() {
    ContextaTheme {
        Scaffold(modifier = Modifier.fillMaxSize()) {
            // Placeholder
        }
    }
}

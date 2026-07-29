package com.ak.contexta.navigation

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.navigation.NavHostController
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.navArgument
import com.ak.contexta.ui.home.HomeScreen
import com.ak.contexta.ui.onboarding.OnboardingScreen
import com.ak.contexta.ui.reading.ReadingScreen
import com.ak.contexta.ui.reference.ReferenceScreen
import com.ak.contexta.ui.settings.SettingsScreen
import com.ak.contexta.ui.vocabulary.VocabularyScreen

@Composable
fun ContextaNavGraph(
    navController: NavHostController,
    modifier: Modifier = Modifier,
    startDestination: String = Screen.Onboarding.route
) {
    NavHost(
        navController = navController,
        startDestination = startDestination,
        modifier = modifier
    ) {
        composable(Screen.Onboarding.route) {
            OnboardingScreen(
                onComplete = {
                    navController.navigate(Screen.Home.route) {
                        popUpTo(Screen.Onboarding.route) { inclusive = true }
                    }
                }
            )
        }

        composable(Screen.Home.route) {
            HomeScreen(
                onArticleClick = { articleId ->
                    navController.navigate(Screen.Reading.createRoute(articleId))
                }
            )
        }

        composable(
            route = Screen.Reading.route,
            arguments = listOf(navArgument("articleId") { type = NavType.LongType })
        ) { backStackEntry ->
            val articleId = backStackEntry.arguments?.getLong("articleId") ?: return@composable
            ReadingScreen(
                articleId = articleId,
                onBack = { navController.popBackStack() }
            )
        }

        composable(Screen.Vocabulary.route) {
            VocabularyScreen()
        }

        composable(Screen.Reference.route) {
            ReferenceScreen()
        }

        composable(Screen.Settings.route) {
            SettingsScreen()
        }
    }
}

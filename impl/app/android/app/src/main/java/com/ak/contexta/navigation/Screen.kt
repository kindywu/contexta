package com.ak.contexta.navigation

sealed class Screen(val route: String) {
    data object Onboarding : Screen("onboarding")
    data object Home : Screen("home")
    data object Reading : Screen("reading/{articleId}") {
        fun createRoute(articleId: Long) = "reading/$articleId"
    }
    data object Vocabulary : Screen("vocabulary")
    data object AddWord : Screen("add_word")
    data object Reference : Screen("reference")
    data object Settings : Screen("settings")
}

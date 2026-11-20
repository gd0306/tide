package cn.gd306.tideenglish.core

data class DailyPracticePlan(val languageID: String, val themeID: String, val words: List<WordState>) {
    companion object {
        fun make(languageID: String, words: List<WordState>, now: Double = nowSeconds()): DailyPracticePlan? {
            val theme = LanguageRegistry.get(languageID)?.themes?.firstOrNull() ?: return null
            val due = words.filter { it.id.startsWith("$languageID|") && it.dueAt <= now }.sortedWith(compareBy<WordState> { it.dueAt }.thenBy { it.id }).take(3)
            return DailyPracticePlan(languageID, theme.id, due)
        }
    }
}

package cn.gd306.tideenglish.core

/** Recognition segments are not whole turns. Only a quiet interval releases pending speech. */
class VoicePauseBuffer(seconds: Int = 5) {
    val seconds = seconds.takeIf { it in choices } ?: 5
    private var completed = ""
    private var partial = ""
    private var lastActivity: Double? = null
    val text get() = listOf(completed, partial).filter { it.isNotEmpty() }.joinToString(" ").take(2000)
    val hasPendingInput get() = text.isNotEmpty()
    fun update(value: String, now: Double): Boolean {
        val bounded = value.trim().take(2000)
        if (!now.isFinite() || now < 0 || bounded.isEmpty() || bounded == partial) return false
        partial = bounded; speech(now)
        return true
    }
    fun finishSegment() { completed = text; partial = "" }
    fun discardPartial() { partial = "" }
    fun speech(now: Double) {
        if (now.isFinite() && now >= 0) lastActivity = maxOf(lastActivity ?: now, now)
    }
    fun remaining(now: Double): Double? {
        val last = lastActivity ?: return null
        if (!hasPendingInput || !now.isFinite()) return null
        return maxOf(0.0, seconds - maxOf(0.0, now - last))
    }
    fun reset() { completed = ""; partial = ""; lastActivity = null }
    companion object { val choices = listOf(5, 10, 20, 30) }
}

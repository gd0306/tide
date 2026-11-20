package cn.gd306.tideenglish.core

import java.util.UUID
import java.util.Locale
import kotlinx.serialization.Serializable

@Serializable
data class SavedExpression(
    val id: String = UUID.randomUUID().toString(), val languageID: String, val text: String,
    val meaning: String, val context: String, val createdAt: Double = nowSeconds(),
    val sourceSessionID: String? = null, val sourcePassageID: String? = null, val revisionKey: String? = null
)
@Serializable
data class SavedCorrection(
    val id: String = UUID.randomUUID().toString(), val languageID: String, val original: String,
    val corrected: String, val explanation: String, val createdAt: Double = nowSeconds(),
    val sourceSessionID: String, val sourcePassageID: String, val revisionKey: String, val rehearsedAt: Double? = null
) {
    fun matches(sessions: List<SessionRecord>): Boolean {
        val session = sessions.firstOrNull { it.id.equals(sourceSessionID, true) && it.languageID == languageID } ?: return false
        val passage = session.passages.firstOrNull { it.id == sourcePassageID && it.speaker == Speaker.user } ?: return false
        return passage.revisionKey == revisionKey && passage.text.canonical() == original.canonical()
    }
}
@Serializable
data class PracticeLibrary(
    var expressions: MutableList<SavedExpression> = mutableListOf(),
    var corrections: MutableList<SavedCorrection> = mutableListOf()
) {
    // Unicode White_Space, explicitly shared with Swift.
    private fun isWhitespace(c: Char) = c.code in 0x09..0x0d || c == '\u0020' || c == '\u0085' || c == '\u00a0' || c == '\u1680' || c.code in 0x2000..0x200a || c == '\u2028' || c == '\u2029' || c == '\u202f' || c == '\u205f' || c == '\u3000'
    private fun normalized(text: String) = text.trim(::isWhitespace).canonical().lowercase(Locale.ROOT)
    fun saveExpression(value: SavedExpression): SavedExpression {
        PracticeLibrary(expressions = mutableListOf(value)).validate()
        expressions.firstOrNull { it.languageID == value.languageID && normalized(it.text) == normalized(value.text) }?.let { return it }
        val candidate = copy(expressions = (expressions + value).toMutableList()); candidate.validate()
        expressions.add(value); return value
    }
    fun saveCorrection(value: SavedCorrection, sessions: List<SessionRecord>): Boolean {
        if (!value.matches(sessions) || corrections.any { it.id.equals(value.id, true) }) return false
        copy(corrections = (corrections + value).toMutableList()).validate()
        corrections.add(value); return true
    }
    fun deleteExpression(id: String) { expressions.removeAll { it.id.equals(id, true) } }
    fun deleteCorrection(id: String) { corrections.removeAll { it.id.equals(id, true) } }
    fun invalidateCorrections(sessions: List<SessionRecord>) {
        val byID = sessions.associateBy { it.id.lowercase(Locale.ROOT) }
        val cached = mutableMapOf<String, Map<String, Passage>>()
        corrections.removeAll { correction ->
            val key = correction.sourceSessionID.lowercase(Locale.ROOT)
            val session = byID[key]
            if (session == null || session.languageID != correction.languageID) true else {
                val passages = cached.getOrPut(key) { session.passages.filter { it.speaker == Speaker.user }.associateBy { it.id } }
                val passage = passages[correction.sourcePassageID]
                passage == null || passage.revisionKey != correction.revisionKey || passage.text.canonical() != correction.original.canonical()
            }
        }
    }
    fun merging(incoming: PracticeLibrary): PracticeLibrary {
        incoming.validate()
        val out = PracticeLibrary(expressions.toMutableList(), corrections.toMutableList())
        incoming.expressions.filter { item -> out.expressions.none { it.id.equals(item.id, true) } }.forEach { out.saveExpression(it) }
        incoming.corrections.filter { item -> out.corrections.none { it.id.equals(item.id, true) } }.forEach { out.corrections.add(it) }
        out.validate(); return out
    }
    fun validate() {
        fun validText(s: String, max: Int, empty: Boolean = false) = (empty || s.any { !isWhitespace(it) }) && s.codePointCount(0, s.length) <= max
        fun validDate(d: Double) = d.isFinite() && d in -63114076800.0..63113904000.0
        fun validUUID(s: String) = try { UUID.fromString(s).toString().equals(s, true) } catch (_: IllegalArgumentException) { false }
        if (expressions.size > 2000 || corrections.size > 2000 || expressions.map { it.id.lowercase(Locale.ROOT) }.toSet().size != expressions.size || corrections.map { it.id.lowercase(Locale.ROOT) }.toSet().size != corrections.size) throw ArchiveError.INVALID
        expressions.forEach { e ->
            if (LanguageRegistry.get(e.languageID) == null) throw ArchiveError.UNSUPPORTED_LANGUAGE
            if (!validUUID(e.id) || e.sourceSessionID?.let { !validUUID(it) } == true || !validText(e.text, 2000) || !validText(e.meaning, 4000) || !validText(e.context, 4000) || !validDate(e.createdAt) || e.sourcePassageID?.let { !validText(it, 4000) } == true || e.revisionKey?.let { !validText(it, 4000) } == true) throw ArchiveError.INVALID
        }
        corrections.forEach { c ->
            if (LanguageRegistry.get(c.languageID) == null) throw ArchiveError.UNSUPPORTED_LANGUAGE
            if (!validUUID(c.id) || !validUUID(c.sourceSessionID) || !validText(c.original, 2000) || !validText(c.corrected, 2000) || !validText(c.explanation, 4000) || !validText(c.sourcePassageID, 4000) || !validText(c.revisionKey, 4000) || !validDate(c.createdAt) || c.rehearsedAt?.let { !validDate(it) } == true) throw ArchiveError.INVALID
        }
    }
}

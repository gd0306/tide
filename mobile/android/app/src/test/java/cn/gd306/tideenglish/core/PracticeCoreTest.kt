package cn.gd306.tideenglish.core

import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class PracticeCoreTest {
    @Test fun libraryDeduplicatesAndInvalidatesRevisions() {
        val session = SessionRecord(languageID = "es")
        session.append(Fragment(id = "p", speaker = Speaker.user, text = "Yo gusto café", startMS = 0, endMS = 1))
        val p = session.passages.single()
        val library = PracticeLibrary()
        val a = SavedExpression(languageID = "es", text = " Café ", meaning = "咖啡", context = "注文")
        assertEquals(a.id, library.saveExpression(a).id)
        assertEquals(a.id, library.saveExpression(SavedExpression(languageID = "es", text = "café", meaning = "coffee", context = "coffee")).id)
        val correction = SavedCorrection(languageID = "es", original = p.text, corrected = "Me gusta el café", explanation = "表达喜好", sourceSessionID = session.id, sourcePassageID = p.id, revisionKey = p.revisionKey)
        assertTrue(library.saveCorrection(correction, listOf(session)))
        session.correctFragment("p", "Me gusta café")
        library.invalidateCorrections(listOf(session))
        assertTrue(library.corrections.isEmpty())
        assertFalse(library.saveCorrection(correction, listOf(session)))
        library.deleteExpression(a.id)
        assertTrue(library.expressions.isEmpty())
    }
    @Test fun planAndCorrectionResult() {
        val plan = DailyPracticePlan.make("es", emptyList(), nowSeconds())!!
        assertTrue(LanguageRegistry.get("es")!!.themes.any { it.id == plan.themeID })
        assertTrue(plan.words.isEmpty())
        assertNull(DailyPracticePlan.make("unknown", emptyList(), nowSeconds()))
        assertNull(PracticeCorrectionResult(false, "invented", "invented").correction("es", "hola", java.util.UUID.randomUUID().toString(), "p", "p:0", emptyList()))
    }
    @Test fun dueWordsAreLimitedAndOrdered() {
        fun word(id: String, due: Double) = WordState(id, id, "m", "f", "e", 0, 0, 0, 0.0, due)
        val words = listOf(word("es|late", 90.0), word("es|early", 10.0), word("es|mid", 50.0), word("es|fourth", 95.0), word("es|future", 101.0), word("en|foreign", 1.0))
        assertEquals(listOf("es|early", "es|mid", "es|late"), DailyPracticePlan.make("es", words, 100.0)!!.words.map { it.id })
    }
    @Test fun validationAndMergePreservePreferences() {
        val good = SavedExpression(languageID = "es", text = "hola", meaning = "hello", context = "greeting")
        assertThrows(ArchiveError::class.java) { PracticeLibrary(expressions = mutableListOf(good.copy(languageID = "unknown"))).validate() }
        assertThrows(ArchiveError::class.java) { PracticeLibrary(expressions = mutableListOf(good.copy(text = "a".repeat(2001)))).validate() }
        assertThrows(ArchiveError::class.java) { PracticeLibrary(expressions = MutableList(2001) { good }).validate() }
        val local = Archive(preferences = Preferences(meaningLanguage = "Chinese (Simplified)"))
        val incoming = Archive(preferences = Preferences(meaningLanguage = "French"), practice = PracticeLibrary(expressions = mutableListOf(good)))
        val merged = ArchiveCodec.merge(local, incoming)
        assertEquals("Chinese (Simplified)", merged.preferences.meaningLanguage)
        assertEquals(good.id, merged.practice!!.expressions.single().id)
        assertEquals(1, ArchiveCodec.merge(merged, incoming).practice!!.expressions.size)
        assertThrows(ArchiveError::class.java) { ArchiveCodec.merge(local, Archive(sessions = mutableListOf(SessionRecord(practiceKind = "other")))) }
    }
    @Test fun correctionResultIsBoundToExistingUnchangedSource() {
        val session = SessionRecord(languageID = "es")
        session.append(Fragment(id = "x", speaker = Speaker.user, text = "Yo gusta", startMS = 0, endMS = 1))
        val p = session.passages.single()
        val result = PracticeCorrectionResult(true, "Me gusta", "Use me")
        fun correction(sessions: List<SessionRecord>) = result.correction("es", p.text, session.id, p.id, p.revisionKey, sessions)
        val saved = correction(listOf(session))!!
        assertNull(PracticeCorrectionResult(true, p.text, "none").correction("es", p.text, session.id, p.id, p.revisionKey, listOf(session)))
        val library = PracticeLibrary(corrections = mutableListOf(saved)); library.invalidateCorrections(emptyList())
        assertTrue(library.corrections.isEmpty())
        assertNull(correction(emptyList()))
        session.correctFragment("x", "Me gusta")
        assertNull(correction(listOf(session)))
    }
    @Test fun sharedWhitespaceRules() {
        val json = kotlinx.serialization.json.Json.parseToJsonElement(java.io.File("../../../packages/fixtures/cross-platform/practice-whitespace.json").readText())
        for (item in json.jsonObject.getValue("cases").jsonArray.map { it.jsonObject }) {
            val text = item.getValue("text").jsonPrimitive.content; val blank = item.getValue("blank").jsonPrimitive.boolean
            val expression = SavedExpression(languageID = "es", text = text, meaning = "m", context = "c")
            assertEquals(text, blank, try { PracticeLibrary(expressions = mutableListOf(expression)).validate(); false } catch (_: ArchiveError) { true })
            item["normalized"]?.jsonPrimitive?.content?.let { expected ->
                val library = PracticeLibrary(); val first = library.saveExpression(expression)
                assertEquals(first.id, library.saveExpression(expression.copy(id = java.util.UUID.randomUUID().toString(), text = expected)).id)
                if (expected != "hola") assertNotEquals(first.id, library.saveExpression(expression.copy(id = java.util.UUID.randomUUID().toString(), text = "hola")).id)
            }
        }
    }
    @Test fun mergeDiscardsStaleIncomingBeforeCapacityCheck() {
        val old = SessionRecord(languageID = "es"); old.append(Fragment(id = "p", speaker = Speaker.user, text = "wrong", startMS = 0, endMS = 1))
        val oldP = old.passages.single(); val current = old.copy(fragments = old.fragments.toMutableList()); current.correctFragment("p", "new")
        val currentP = current.passages.single()
        val existing = MutableList(2000) { SavedCorrection(languageID = "es", original = currentP.text, corrected = "newer", explanation = "m", sourceSessionID = current.id, sourcePassageID = currentP.id, revisionKey = currentP.revisionKey) }
        val stale = SavedCorrection(languageID = "es", original = oldP.text, corrected = "right", explanation = "m", sourceSessionID = old.id, sourcePassageID = oldP.id, revisionKey = oldP.revisionKey)
        val local = Archive(sessions = mutableListOf(current), practice = PracticeLibrary(corrections = existing))
        val incoming = Archive(sessions = mutableListOf(old), practice = PracticeLibrary(corrections = mutableListOf(stale)))
        assertEquals(2000, ArchiveCodec.merge(local, incoming).practice!!.corrections.size)
    }
    @Test fun falseAndCanonicalCorrectionWithValidSource() {
        val s = SessionRecord(languageID = "es"); s.append(Fragment(id = "p", speaker = Speaker.user, text = "café", startMS = 0, endMS = 1))
        val p = s.passages.single()
        for (result in listOf(PracticeCorrectionResult(false, "casa", "x"), PracticeCorrectionResult(true, "cafe\u0301", "x")))
            assertNull(result.correction("es", p.text, s.id, p.id, p.revisionKey, listOf(s)))
    }
    @Test fun rejectsQuotedPracticeDates() {
        val source = java.io.File("../../../packages/fixtures/cross-platform/practice-archive.json").readText()
        for (number in listOf("800000002", "800000004", "800000005"))
            assertThrows(ArchiveError::class.java) { ArchiveCodec.decode(source.replace(":$number", ":\"$number\"")) }
    }
}

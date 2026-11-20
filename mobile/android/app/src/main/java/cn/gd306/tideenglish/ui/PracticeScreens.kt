package cn.gd306.tideenglish.ui

import androidx.annotation.StringRes
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import cn.gd306.tideenglish.R
import cn.gd306.tideenglish.TideEnglishViewModel
import cn.gd306.tideenglish.core.*
import kotlinx.coroutines.launch
import cn.gd306.tideenglish.ui.tideStringResource as stringResource

@Composable
internal fun PracticeDialog(title: String, onDismiss: () -> Unit, tag: String, content: @Composable ColumnScope.() -> Unit) {
    Dialog(onDismissRequest = onDismiss) {
        Surface(shape = RoundedCornerShape(24.dp), color = TideEnglishColors.Surface) {
            Column(Modifier.fillMaxWidth().testTag(tag).padding(vertical = 14.dp)) {
                SettingsSheetHeader(title, onDismiss, R.string.common_close)
                Column(Modifier.fillMaxWidth().weight(1f, fill = false).verticalScroll(rememberScrollState())
                    .padding(horizontal = 22.dp, vertical = 6.dp), verticalArrangement = Arrangement.spacedBy(14.dp), content = content)
            }
        }
    }
}

@Composable
internal fun PracticeButton(@StringRes title: Int, onClick: () -> Unit, tag: String, enabled: Boolean = true) {
    TideEnglishTextButton(onClick, Modifier.fillMaxWidth().heightIn(min = 48.dp).testTag(tag), enabled) {
        Text(stringResource(title))
    }
}

@Composable
internal fun DailyPracticeDialog(plan: DailyPracticePlan, theme: ConversationTheme, enabled: Boolean,
    onStart: () -> Unit, onDismiss: () -> Unit) {
    PracticeDialog(stringResource(R.string.practice_daily), onDismiss, "daily-practice-preview") {
        PracticeField(R.string.practice_daily_scene, theme.title)
        Text(if (theme.id == "coffee") stringResource(R.string.practice_daily_cafe) else theme.subtitle,
            color = TideEnglishColors.Secondary)
        PracticeField(R.string.practice_daily_goal_label, stringResource(R.string.practice_daily_goal))
        if (plan.words.isNotEmpty()) {
            Text(stringResource(R.string.practice_daily_review_words), style = MaterialTheme.typography.titleSmall,
                modifier = Modifier.semantics { heading() })
            plan.words.forEach { word ->
                Column {
                    Text(word.lemma)
                    Text(word.meaning, color = TideEnglishColors.Secondary)
                }
            }
        }
        Button(onClick = onStart, enabled = enabled,
            modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp).testTag("start-daily-practice")) {
            Text(stringResource(R.string.practice_daily_start))
        }
    }
}

@Composable
internal fun SaveExpressionAction(vm: TideEnglishViewModel, expression: SavedExpression) {
    var result by remember(expression.languageID, expression.text, expression.context) { mutableStateOf<ExpressionSave?>(null) }
    var enteringMeaning by remember { mutableStateOf(false) }
    var meaning by remember { mutableStateOf("") }
    var saving by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    fun save(value: SavedExpression) {
        saving = true
        scope.launch {
            result = vm.saveExpression(value)
            saving = false
        }
    }

    PracticeButton(if (saving) R.string.practice_saving else R.string.practice_save_expression, onClick = {
        if (expression.meaning.isBlank()) {
            meaning = ""
            enteringMeaning = true
        } else save(expression)
    }, tag = "save-expression", enabled = !vm.isRunning && !saving)
    result?.let {
        Text(stringResource(when (it) {
            ExpressionSave.SAVED -> R.string.practice_expression_saved
            ExpressionSave.DUPLICATE -> R.string.practice_expression_duplicate
            ExpressionSave.INVALID -> R.string.practice_expression_invalid
            ExpressionSave.FAILED -> R.string.error_save_progress_failed
        }), style = MaterialTheme.typography.bodySmall, color = TideEnglishColors.Secondary,
            modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite })
    }
    if (enteringMeaning) PracticeDialog(stringResource(R.string.practice_add_meaning), { enteringMeaning = false }, "expression-meaning-dialog") {
        TideEnglishTextField(meaning, { meaning = it.take(4000) }, Modifier.fillMaxWidth().testTag("expression-meaning"),
            label = { Text(stringResource(R.string.practice_meaning)) }, minLines = 2, maxLines = 5)
        PracticeButton(R.string.common_save, { enteringMeaning = false; save(expression.copy(meaning = meaning.trim())) },
            "confirm-expression-meaning", enabled = !vm.isRunning && meaning.isNotBlank())
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun PracticeLibrarySheet(vm: TideEnglishViewModel, corrections: Boolean,
    onRehearse: (SavedCorrection) -> Unit, onDismiss: () -> Unit) {
    var query by rememberSaveable { mutableStateOf("") }
    var selectedID by rememberSaveable { mutableStateOf<String?>(null) }
    var deleteID by rememberSaveable { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    val languageID = vm.language.id
    val library = vm.archive.practice
    val needle = query.trim()
    fun matches(vararg values: String) = needle.isEmpty() || values.any { it.contains(needle, ignoreCase = true) }
    val expressions = if (corrections) emptyList() else library?.expressions.orEmpty()
        .filter { it.languageID == languageID && matches(it.text, it.meaning, it.context) }.sortedByDescending { it.createdAt }
    val entries = if (!corrections) emptyList() else library?.corrections.orEmpty()
        .filter { it.languageID == languageID && matches(it.original, it.corrected, it.explanation) }.sortedByDescending { it.createdAt }
    val title = if (corrections) R.string.practice_library_corrections else R.string.practice_library_expressions
    val searchTitle = if (corrections) R.string.practice_library_correction_search else R.string.practice_library_expression_search
    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = TideEnglishColors.Cream,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        TideDialogAppearance()
        Column(Modifier.fillMaxHeight(.92f).testTag(if (corrections) "correction-notebook" else "saved-expressions")) {
            SettingsSheetHeader(stringResource(title), onDismiss)
            LazyColumn(Modifier.weight(1f), contentPadding = PaddingValues(20.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)) {
                item {
                    TideEnglishTextField(query, { query = it.take(200) },
                        Modifier.fillMaxWidth().testTag("practice-library-search"), label = { Text(stringResource(searchTitle)) }, singleLine = true)
                }
                if (expressions.isEmpty() && entries.isEmpty()) item {
                    Text(stringResource(when {
                        needle.isNotEmpty() -> R.string.practice_no_matches
                        corrections -> R.string.practice_library_corrections_empty
                        else -> R.string.practice_library_expressions_empty
                    }), color = TideEnglishColors.Secondary)
                }
                items(expressions, key = { it.id }) { expression ->
                    PracticeLibraryRow(expression.text, expression.meaning, "expression-${expression.id}") { selectedID = expression.id }
                }
                items(entries, key = { it.id }) { correction ->
                    PracticeLibraryRow(correction.corrected, correction.original, "correction-${correction.id}") { selectedID = correction.id }
                }
            }
        }
    }
    expressions.firstOrNull { it.id == selectedID }?.let { expression ->
        PracticeDialog(stringResource(R.string.practice_library_expressions), { selectedID = null }, "saved-expression-detail") {
            SelectionContainer { Text(expression.text, style = MaterialTheme.typography.titleLarge) }
            PracticeField(R.string.practice_meaning, expression.meaning)
            PracticeField(R.string.practice_context, expression.context)
            PracticeButton(R.string.common_delete, { deleteID = expression.id }, "delete-expression", enabled = !vm.isRunning)
        }
    }
    entries.firstOrNull { it.id == selectedID }?.let { correction ->
        PracticeDialog(stringResource(R.string.practice_library_corrections), { selectedID = null }, "saved-correction-detail") {
            CorrectionDetails(correction)
            Button(onClick = { onRehearse(correction) }, enabled = vm.canStartPractice,
                modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp).testTag("rehearse-correction")) {
                Text(stringResource(R.string.practice_correction_rehearse))
            }
            PracticeButton(R.string.common_delete, { deleteID = correction.id }, "delete-correction", enabled = !vm.isRunning)
        }
    }
    deleteID?.let { id ->
        PracticeDialog(stringResource(R.string.practice_delete_item), { deleteID = null }, "practice-delete-confirmation") {
            PracticeButton(R.string.common_delete, {
                deleteID = null
                scope.launch { vm.deletePracticeItem(id, corrections) }
            }, "confirm-practice-delete", enabled = !vm.isRunning)
        }
    }
}

@Composable
private fun PracticeLibraryRow(text: String, detail: String, tag: String, onClick: () -> Unit) {
    Surface(onClick = onClick, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp).testTag(tag),
        shape = RoundedCornerShape(18.dp), color = TideEnglishColors.Surface) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(text, style = MaterialTheme.typography.titleMedium, maxLines = 3, overflow = TextOverflow.Ellipsis)
            Text(detail, color = TideEnglishColors.Secondary, maxLines = 2, overflow = TextOverflow.Ellipsis)
        }
    }
}

@Composable
internal fun PracticeCorrectionDialog(state: CorrectionState, running: Boolean, onRetry: () -> Unit,
    onSave: () -> Unit, onModelSetup: () -> Unit, onDismiss: () -> Unit) {
    PracticeDialog(stringResource(R.string.practice_correction_title), onDismiss, "practice-correction-dialog") {
        val answer = state as? CorrectionState.Answer
        val correction = answer?.correction
        if (correction != null) CorrectionDetails(correction)
        else PracticeField(R.string.practice_correction_original, state.source.original)
        when (state) {
            is CorrectionState.Checking -> {
                CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
                PracticeStatus(R.string.practice_correction_checking)
            }
            is CorrectionState.Answer -> when {
                correction == null -> PracticeStatus(R.string.practice_correction_none)
                state.saved -> PracticeStatus(R.string.practice_correction_saved)
                else -> {
                    if (state.storageFailed) PracticeStatus(R.string.error_save_progress_failed)
                    Button(onClick = onSave, enabled = !running && !state.saving,
                        modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp).testTag("save-correction")) {
                        Text(stringResource(if (state.saving) R.string.practice_saving else R.string.practice_correction_save))
                    }
                }
            }
            is CorrectionState.Failure -> {
                PracticeStatus(when (state.problem) {
                    CorrectionProblem.STALE -> R.string.practice_correction_stale
                    CorrectionProblem.INPUT_LIMIT -> R.string.practice_correction_input_limit
                    CorrectionProblem.RESPONSE -> R.string.practice_correction_response
                    CorrectionProblem.REQUEST -> R.string.practice_correction_request
                    CorrectionProblem.PERSONAL_KEY -> R.string.practice_correction_personal_key
                    CorrectionProblem.KEY_REQUIRED -> R.string.error_missing_key
                })
                when (state.problem) {
                    CorrectionProblem.REQUEST, CorrectionProblem.RESPONSE -> PracticeButton(R.string.practice_correction_retry, onRetry, "retry-correction", enabled = !running)
                    CorrectionProblem.KEY_REQUIRED -> PracticeButton(R.string.practice_open_model_setup, onModelSetup, "correction-model-setup", enabled = !running)
                    else -> Unit
                }
            }
        }
    }
}

@Composable
private fun CorrectionDetails(correction: SavedCorrection) {
    PracticeField(R.string.practice_correction_original, correction.original)
    PracticeField(R.string.practice_correction_suggestion, correction.corrected)
    PracticeField(R.string.practice_correction_explanation, correction.explanation)
}

@Composable
private fun PracticeField(@StringRes label: Int, value: String) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(stringResource(label), style = MaterialTheme.typography.titleSmall,
            color = TideEnglishColors.Secondary, modifier = Modifier.semantics { heading() })
        SelectionContainer { Text(value, style = MaterialTheme.typography.bodyLarge) }
    }
}

@Composable
private fun PracticeStatus(@StringRes message: Int) {
    Text(stringResource(message), modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite })
}

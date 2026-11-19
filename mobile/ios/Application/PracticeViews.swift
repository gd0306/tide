import SwiftUI
import TideEnglishCore

struct DailyPracticePreview: View {
    let plan: DailyPracticePlan
    let theme: ConversationTheme
    let start: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section(UI("Scene")) {
                    Label(UI(theme.title), systemImage: theme.symbol).font(.headline)
                    Text(UI(theme.subtitle))
                }
                Section(UI("Practice goal")) {
                    Text(UI("Answer a question about this scene in your own words."))
                        .accessibilityIdentifier("daily-goal")
                }
                if !plan.words.isEmpty {
                    Section(UI("Words to revisit")) {
                        ForEach(plan.words) { word in
                            VStack(alignment: .leading) { Text(word.lemma); Text(word.meaning).foregroundStyle(TideEnglishColor.secondary) }
                        }
                    }
                }
                Button(UI("Start five-minute practice"), action: start)
                    .accessibilityIdentifier("start-daily-practice")
            }
            .scrollContentBackground(.hidden).background(TideEnglishColor.cream)
            .navigationTitle(UI("Today’s five minutes")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(UI("Close")) { dismiss() } } }
        }.presentationDetents([.large])
    }
}

struct SaveExpressionButton: View {
    let coordinator: ConversationCoordinator
    let expression: SavedExpression
    @State private var message: String?
    @State private var enteringMeaning = false
    @State private var meaning = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(UI("Save expression"), systemImage: "bookmark") {
                if expression.meaning.isEmpty { enteringMeaning = true }
                else { save(expression) }
            }.accessibilityIdentifier("save-expression").disabled(coordinator.isRunning)
            if let message { Text(UI(message)).font(.footnote).foregroundStyle(TideEnglishColor.secondary) }
        }
        .alert(UI("Add a meaning"), isPresented: $enteringMeaning) {
            TextField(UI("Meaning"), text: $meaning)
            Button(UI("Cancel"), role: .cancel) {}
            Button(UI("Save")) {
                var value = expression
                value.meaning = meaning
                save(value)
            }.disabled(meaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
    private func save(_ expression: SavedExpression) {
        guard !coordinator.isRunning else { return }
        do { message = try coordinator.store.saveExpression(expression) ? "Expression saved." : "Already saved." }
        catch { message = "Couldn’t save the expression. Check its length and try again." }
    }
}

enum PracticeShelf: String, Identifiable {
    case expressions, corrections
    var id: Self { self }
    var title: String { self == .expressions ? "Saved expressions" : "Correction notebook" }
}

struct PracticeShelfView: View {
    let shelf: PracticeShelf
    let coordinator: ConversationCoordinator
    let rehearse: (SavedCorrection) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var deleteFailed = false

    private func matches(_ fields: String...) -> Bool {
        search.isEmpty || fields.contains { $0.localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        NavigationStack {
            List {
                if shelf == .expressions {
                    let values = coordinator.store.practice.expressions.reversed().filter {
                        $0.languageID == coordinator.language.id && matches($0.text, $0.meaning, $0.context)
                    }
                    if values.isEmpty {
                        empty(title: "No saved expressions", symbol: "bookmark",
                              detail: "Save an expression from a word or a past conversation.")
                    }
                    ForEach(values) { expression in
                        NavigationLink {
                            List {
                                Section { Text(expression.text).font(.title2).textSelection(.enabled) }
                                Section(UI("Meaning")) { Text(expression.meaning) }
                                Section(UI("Context")) { Text(expression.context) }
                            }.scrollContentBackground(.hidden).background(TideEnglishColor.cream)
                                .navigationTitle(UI("Saved expression")).navigationBarTitleDisplayMode(.inline)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(expression.text)
                                Text(expression.meaning).font(.subheadline).foregroundStyle(TideEnglishColor.secondary)
                            }
                        }.accessibilityIdentifier("saved-expression-row")
                            .swipeActions {
                                Button(UI("Delete"), role: .destructive) {
                                    do { try coordinator.store.deleteExpression(expression.id) } catch { deleteFailed = true }
                                }.disabled(coordinator.isRunning)
                            }
                    }
                } else {
                    let values = coordinator.store.practice.corrections.reversed().filter {
                        $0.languageID == coordinator.language.id && matches($0.original, $0.corrected, $0.explanation)
                    }
                    if values.isEmpty {
                        empty(title: "No saved corrections", symbol: "text.book.closed",
                              detail: "Check a sentence you said in a past conversation, then save the suggestion.")
                    }
                    ForEach(values) { correction in
                        NavigationLink {
                            List {
                                Section(UI("What you said")) { Text(correction.original) }
                                Section(UI("Suggested wording")) { Text(correction.corrected) }
                                Section(UI("Explanation")) { Text(correction.explanation) }
                                Button(UI("Say it again"), systemImage: "mic") { rehearse(correction) }
                                    .disabled(coordinator.isRunning || coordinator.hasContinuation)
                                    .accessibilityIdentifier("rehearse-correction")
                            }.scrollContentBackground(.hidden).background(TideEnglishColor.cream)
                                .navigationTitle(UI("Saved correction")).navigationBarTitleDisplayMode(.inline)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(correction.corrected)
                                Text(correction.original).font(.subheadline).foregroundStyle(TideEnglishColor.secondary)
                            }
                        }.accessibilityIdentifier("saved-correction-row")
                            .swipeActions {
                                Button(UI("Delete"), role: .destructive) {
                                    do { try coordinator.store.deleteCorrection(correction.id) } catch { deleteFailed = true }
                                }.disabled(coordinator.isRunning)
                            }
                    }
                }
            }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: UI("Search"))
            .scrollContentBackground(.hidden).background(TideEnglishColor.cream)
            .navigationTitle(UI(shelf.title)).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(UI("Done")) { dismiss() } } }
            .alert(UI("Couldn’t delete the entry. Please try again."), isPresented: $deleteFailed) { Button(UI("OK")) {} }
        }.presentationDetents([.large])
    }
    private func empty(title: String, symbol: String, detail: String) -> some View {
        ContentUnavailableView(UI(search.isEmpty ? title : "No matches"), systemImage: symbol,
                               description: Text(UI(search.isEmpty ? detail : "Try another word or phrase.")))
    }
}

struct PassageCorrectionView: View {
    let coordinator: ConversationCoordinator
    let session: SessionRecord
    let passage: Passage
    @State private var attempt: UUID?
    @State private var binding: ConversationCoordinator.CorrectionRequest?
    @State private var result: SavedCorrection?
    @State private var status: String?
    @State private var failed = false
    @State private var loading = false
    @State private var consent = false
    @State private var saved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if loading {
                ProgressView(UI("Checking your sentence…"))
            } else if let binding, let result, coordinator.canUseCorrection(binding) {
                Text(UI("Suggested wording")).font(.caption).foregroundStyle(TideEnglishColor.secondary)
                Text(result.corrected).font(.headline).accessibilityIdentifier("correction-suggestion")
                Text(result.explanation)
                if !saved {
                    Button(UI("Save correction"), systemImage: "bookmark") {
                        do {
                            try coordinator.saveCorrection(result, for: binding)
                            saved = true; status = "Correction saved."
                        } catch { status = "Couldn’t save the correction. Please try again." }
                    }.accessibilityIdentifier("save-correction")
                }
            } else {
                Button(UI(failed ? "Try again" : "Check my sentence"), systemImage: "text.magnifyingglass") {
                    if coordinator.hasAIConsent { check() } else { consent = true }
                }.disabled(coordinator.isRunning)
                    .accessibilityIdentifier(failed ? "retry-correction" : "request-correction")
            }
            if let status { Text(UI(status)).font(.footnote).foregroundStyle(TideEnglishColor.secondary) }
        }
        .sheet(isPresented: $consent) {
            AIConsentView(summary: coordinator.providerConsentSummary, agree: {
                coordinator.acceptAIConsent(); consent = false
                check()
            }, decline: { consent = false })
        }
        .task(id: attempt) {
            guard let attempt, let binding else { return }
            do {
                let suggestion = try await coordinator.checkCorrection(binding)
                try Task.checkCancellation()
                guard self.attempt == attempt, coordinator.canUseCorrection(binding) else { return }
                result = suggestion
                status = suggestion == nil ? "No correction needed." : nil
            } catch is CancellationError { return }
            catch {
                guard !Task.isCancelled, self.attempt == attempt else { return }
                failed = true
                status = (error as? LocalizedError)?.errorDescription ?? "Couldn’t check this sentence. Please try again."
            }
            loading = false
        }
        .onChange(of: coordinator.correctionGeneration) { _, _ in clear() }
        .onChange(of: coordinator.isRunning) { _, _ in clear() }
    }
    private func clear() {
        attempt = nil; binding = nil; result = nil; status = nil; failed = false; loading = false; saved = false
    }
    private func check() {
        clear()
        binding = coordinator.correctionRequest(session: session, passage: passage)
        loading = true; attempt = UUID()
    }
}

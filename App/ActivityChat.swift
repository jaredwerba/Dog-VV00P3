import SwiftUI
import VV00PCore

struct ActivityLine: Identifiable, Equatable {
    enum Role: String {
        case user
        case diary
    }

    let id = UUID()
    var role: Role
    var text: String
}

struct ActivityChatSheet: View {
    @ObservedObject var session: StrapSession
    @Environment(\.dismiss) private var dismiss
    @State private var lines: [ActivityLine] = []
    @State private var draft = ""
    @State private var sending = false
    @State private var opened = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(lines) { line in
                            Text(line.text)
                                .military(line.role == .user ? 15 : 16, bold: line.role == .diary)
                                .foregroundStyle(line.role == .user ? Color.secondary : Color.primary)
                                .frame(maxWidth: .infinity, alignment: line.role == .user ? .trailing : .leading)
                                .padding(12)
                                .background(bubble, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                    }
                    .padding(20)
                }
                HStack(spacing: 10) {
                    TextField("Ask about Max", text: $draft)
                        .textFieldStyle(.plain)
                        .military(16)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(bubble, in: Capsule())
                    Button("Send") {
                        let text = draft
                        draft = ""
                        Task { await ask(text) }
                    }
                    .vvControlGlass(prominent: true)
                    .disabled(sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .navigationTitle(session.profile.name)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .modifier(ChatSheetChrome())
        .environment(\.font, MilitaryFont.text(17))
        .task {
            guard !opened else { return }
            opened = true
            await ask(ActivityReport.openingQuestion)
        }
    }

    private var bubble: some ShapeStyle {
        Color.primary.opacity(0.08)
    }

    private var sentence: String {
        ActivityReport.sentence(
            name: session.profile.name,
            todayMeters: session.todayTotals.distance,
            weekMeters: session.weekTotals.distance,
            unit: session.unit
        )
    }

    private func ask(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !sending else { return }
        sending = true
        lines.append(ActivityLine(role: .user, text: trimmed))
        let first = lines.filter { $0.role == .user }.count == 1
        if ProcessInfo.processInfo.arguments.contains("--screenshot") {
            lines.append(ActivityLine(role: .diary, text: sentence))
            sending = false
            return
        }
        let history = lines.map { (role: $0.role == .user ? "user" : "assistant", text: $0.text) }
        do {
            let answer = try await ActivityChatClient.reply(history: history, sentence: sentence)
            let cleaned = answer.trimmingCharacters(in: .whitespacesAndNewlines)
            lines.append(ActivityLine(role: .diary, text: cleaned.isEmpty && first ? sentence : cleaned))
        } catch {
            lines.append(ActivityLine(
                role: .diary,
                text: first ? sentence : "The diary could not answer. Pull to refresh, then ask again."
            ))
        }
        sending = false
    }
}

private struct ChatSheetChrome: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        } else {
            content
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

enum ActivityChatClient {
    static func reply(history: [(role: String, text: String)], sentence: String) async throws -> String {
        guard let key = OpenRouterKey.load() else { throw DayBriefError.missingKey }
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Max Werba", forHTTPHeaderField: "X-Title")
        var messages: [[String: String]] = [[
            "role": "system",
            "content": """
            You speak for Max's movement diary. Use only this sentence's figures. Do not invent sleep, heart rate, or a place.
            When the person asks about activity, reply with this sentence and nothing else:
            \(sentence)
            For a later question, answer in one or two short sentences using only those figures.
            """,
        ]]
        messages.append(contentsOf: history.map { ["role": $0.role, "content": $0.text] })
        let body: [String: Any] = [
            "model": DayBriefClient.model,
            "temperature": 0.2,
            "max_tokens": 220,
            "reasoning": ["effort": "none"],
            "messages": messages,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else { throw DayBriefError.requestFailed(status) }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = root["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw DayBriefError.unreadable
        }
        return content
    }
}

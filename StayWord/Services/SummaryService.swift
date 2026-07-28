import Foundation
import MLXLLM
import MLXLMCommon
import OSLog
import Tokenizers

#if canImport(FoundationModels)
import FoundationModels
#endif

struct SummaryDraft: Sendable {
    let subject: String
    let text: String
    let kind: SummaryKind
}

enum SummaryContentPolicy {
    static func isDistinctSummary(_ summary: String, from transcript: String) -> Bool {
        let normalizedSummary = summary.normalizedForContentComparison
        return !normalizedSummary.isEmpty
            && normalizedSummary != transcript.normalizedForContentComparison
    }
}

protocol SummaryService: Sendable {
    func summarize(transcript: String) async throws -> SummaryDraft
}

actor OnDeviceSummaryService: SummaryService {
    private enum LocalModel {
        static let directoryName = "Qwen3.5-0.8B-MLX-4bit"
        static let relativeDirectory = "Models/Summary/\(directoryName)"
        static let maximumChunkCharacters = 3_600
    }

    private let localModelDirectoryOverride: URL?
    private let usesSystemLanguageModel: Bool
    private var localModelContainer: ModelContainer?
    private var localModelLoadTask: Task<ModelContainer, Error>?

    init(
        localModelDirectory: URL? = nil,
        usesSystemLanguageModel: Bool = true
    ) {
        self.localModelDirectoryOverride = localModelDirectory
        self.usesSystemLanguageModel = usesSystemLanguageModel
    }

    func summarize(transcript: String) async throws -> SummaryDraft {
        let cleaned = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            throw StayWordError.emptyTranscript
        }

        #if canImport(FoundationModels)
        if usesSystemLanguageModel, #available(iOS 26.0, *) {
            do {
                if let generated = try await generateFoundationSummary(transcript: cleaned) {
                    return generated
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                Self.logger.notice(
                    "Foundation Models summary unavailable; falling back to bundled Qwen: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
        #endif

        #if targetEnvironment(simulator)
        Self.logger.notice(
            "Bundled MLX summary is unavailable in the iOS Simulator."
        )
        throw LocalSummaryError.simulatorUnsupported
        #else
        do {
            return try await generateLocalSummary(transcript: cleaned)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            Self.logger.error(
                "Bundled Qwen summary failed: \(error.localizedDescription, privacy: .public)"
            )
            throw LocalSummaryError.generationFailed
        }
        #endif
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func generateFoundationSummary(transcript: String) async throws -> SummaryDraft? {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else {
            return nil
        }

        let chunks = transcript.chunked(maxCharacters: 6_000)
        var intermediate: [String] = []

        for chunk in chunks {
            let session = LanguageModelSession(
                model: model,
                instructions: """
                You summarize private voice-note transcripts. Preserve facts, names, decisions,
                and action items. Do not invent details. Respond in the transcript's language.
                """
            )
            let response = try await session.respond(
                to: "Summarize this transcript concisely:\n\n\(chunk)",
                generating: GeneratedAudioSummary.self
            )
            intermediate.append("\(response.content.subject)\n\(response.content.summary)")
        }

        let final: GeneratedAudioSummary
        if intermediate.count == 1 {
            let session = LanguageModelSession(
                instructions: "Return a concise subject and factual summary in the source language."
            )
            final = try await session.respond(
                to: intermediate[0],
                generating: GeneratedAudioSummary.self
            ).content
        } else {
            let session = LanguageModelSession(
                instructions: """
                Combine partial summaries into one factual voice-note summary. Remove repetition
                and preserve decisions and action items. Respond in the source language.
                """
            )
            final = try await session.respond(
                to: intermediate.joined(separator: "\n\n"),
                generating: GeneratedAudioSummary.self
            ).content
        }

        let subject = final.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = final.summary.trimmingCharacters(in: .whitespacesAndNewlines)

        guard SummaryContentPolicy.isDistinctSummary(
            summary,
            from: transcript
        ) else {
            return nil
        }

        return SummaryDraft(subject: subject, text: summary, kind: .foundationModel)
    }
    #endif

    private func generateLocalSummary(transcript: String) async throws -> SummaryDraft {
        let chunks = transcript.chunked(
            maxCharacters: LocalModel.maximumChunkCharacters
        )
        var partialSummaries: [String] = []

        for chunk in chunks {
            let summary = try await generateLocalText(
                prompt: """
                请总结下面这段录音转写。
                - 使用与转写原文相同的语言。
                - 保留事实、人物、决定和待办事项。
                - 不要编造原文没有的信息。
                - 不要解释任务，不要输出“摘要：”等前缀，只输出摘要正文。
                - 用一到三个简洁段落完成。

                转写内容：
                \(chunk)
                """,
                maximumOutputTokens: 240
            )
            partialSummaries.append(summary)
        }

        let summary: String
        if partialSummaries.count == 1 {
            summary = partialSummaries[0]
        } else {
            summary = try await generateLocalText(
                prompt: """
                下面是同一段录音的分段摘要。请合并为一份连贯、简洁、无重复的最终摘要。
                使用原摘要的语言，保留事实、人物、决定和待办事项。
                不要解释任务，不要输出“摘要：”等前缀，只输出摘要正文。

                \(partialSummaries.joined(separator: "\n\n"))
                """,
                maximumOutputTokens: 320
            )
        }

        guard SummaryContentPolicy.isDistinctSummary(summary, from: transcript) else {
            throw LocalSummaryError.invalidOutput
        }

        return SummaryDraft(
            subject: "",
            text: summary,
            kind: .localLanguageModel
        )
    }

    private func generateLocalText(
        prompt: String,
        maximumOutputTokens: Int
    ) async throws -> String {
        let container = try await localModel()
        let session = ChatSession(
            container,
            instructions: """
            You are an offline voice-note summarizer. Be concise and factual.
            Never add information that is not present in the transcript.
            Always answer in the same language as the supplied transcript.
            """,
            generateParameters: GenerateParameters(
                maxTokens: maximumOutputTokens,
                temperature: 0.2,
                topP: 0.9,
                repetitionPenalty: 1.05,
                repetitionContextSize: 64,
                prefillStepSize: 256
            )
        )
        let response = try await session.respond(to: prompt)
        let cleaned = response.cleanedLocalModelSummary
        guard !cleaned.isEmpty else {
            throw LocalSummaryError.invalidOutput
        }
        return cleaned
    }

    private func localModel() async throws -> ModelContainer {
        if let localModelContainer {
            return localModelContainer
        }
        if let localModelLoadTask {
            return try await localModelLoadTask.value
        }

        let directory = try localModelDirectory()
        let task = Task {
            try await LLMModelFactory.shared.loadContainer(
                from: directory,
                using: SwiftTransformersTokenizerLoader()
            )
        }
        localModelLoadTask = task

        do {
            let container = try await task.value
            localModelContainer = container
            localModelLoadTask = nil
            return container
        } catch {
            localModelLoadTask = nil
            throw error
        }
    }

    private func localModelDirectory() throws -> URL {
        if let localModelDirectoryOverride {
            return localModelDirectoryOverride
        }

        guard let resourceURL = Bundle.main.resourceURL else {
            throw LocalSummaryError.missingModel
        }
        let directory = resourceURL.appendingPathComponent(
            LocalModel.relativeDirectory,
            isDirectory: true
        )
        let configuration = directory.appendingPathComponent("config.json")
        let weights = directory.appendingPathComponent("model.safetensors")
        guard
            FileManager.default.isReadableFile(atPath: configuration.path),
            FileManager.default.isReadableFile(atPath: weights.path)
        else {
            throw LocalSummaryError.missingModel
        }
        return directory
    }

    private static let logger = Logger(
        subsystem: "com.rivendell.stayword",
        category: "Summary"
    )
}

private enum LocalSummaryError: LocalizedError {
    case missingModel
    case invalidOutput
    case generationFailed
    case simulatorUnsupported

    var errorDescription: String? {
        switch self {
        case .missingModel:
            String(localized: "The bundled on-device summary model is missing.")
        case .invalidOutput:
            String(localized: "The on-device model did not produce a usable summary.")
        case .generationFailed:
            String(localized: "The on-device summary could not be generated. Try again.")
        case .simulatorUnsupported:
            String(localized: "On-device summary is unavailable in the iOS Simulator. Use a physical iPhone.")
        }
    }
}

private struct SwiftTransformersTokenizerLoader: MLXLMCommon.TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        let tokenizer = try await Tokenizers.AutoTokenizer.from(modelFolder: directory)
        return SwiftTransformersTokenizer(tokenizer)
    }
}

private struct SwiftTransformersTokenizer: MLXLMCommon.Tokenizer, @unchecked Sendable {
    private let upstream: any Tokenizers.Tokenizer

    init(_ upstream: any Tokenizers.Tokenizer) {
        self.upstream = upstream
    }

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? {
        upstream.convertTokenToId(token)
    }

    func convertIdToToken(_ id: Int) -> String? {
        upstream.convertIdToToken(id)
    }

    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }

    func applyChatTemplate(
        messages: [[String: any Sendable]],
        tools: [[String: any Sendable]]?,
        additionalContext: [String: any Sendable]?
    ) throws -> [Int] {
        do {
            return try upstream.applyChatTemplate(
                messages: messages,
                tools: tools,
                additionalContext: additionalContext
            )
        } catch Tokenizers.TokenizerError.missingChatTemplate {
            throw MLXLMCommon.TokenizerError.missingChatTemplate
        }
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
private struct GeneratedAudioSummary {
    var subject: String
    var summary: String
}
#endif

private extension String {
    var normalizedForContentComparison: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .unicodeScalars
            .filter { !CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters).contains($0) }
            .map(String.init)
            .joined()
    }

    var cleanedLocalModelSummary: String {
        var result = replacingOccurrences(
            of: #"(?s)<think>.*?</think>"#,
            with: "",
            options: .regularExpression
        )
        result = result
            .replacingOccurrences(of: "```text", with: "")
            .replacingOccurrences(of: "```markdown", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let prefixes = [
            "摘要：", "摘要:", "总结：", "总结:",
            "Summary:", "Summary：",
        ]
        for prefix in prefixes where result.hasPrefix(prefix) {
            result.removeFirst(prefix.count)
            break
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func chunked(maxCharacters: Int) -> [String] {
        guard count > maxCharacters else { return [self] }
        var chunks: [String] = []
        var start = startIndex
        while start < endIndex {
            let end = index(start, offsetBy: maxCharacters, limitedBy: endIndex) ?? endIndex
            chunks.append(String(self[start..<end]))
            start = end
        }
        return chunks
    }
}

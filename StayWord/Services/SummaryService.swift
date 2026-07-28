import Foundation
import MLXLLM
import MLXLMCommon
import OSLog
import Tokenizers

struct SummaryDraft: Sendable {
    let subject: String
    let text: String
    let kind: SummaryKind
}

protocol SummaryService: Sendable {
    func summarize(segments: [TranscriptDraft]) async throws -> SummaryDraft
}

enum SummaryInputChunker {
    static func chunks(
        from segments: [TranscriptDraft],
        targetCharacterCount: Int
    ) -> [String] {
        precondition(targetCharacterCount > 0)

        var chunks: [String] = []
        var currentSegments: [String] = []
        var currentCharacterCount = 0

        for segment in segments {
            let text = segment.text.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard !text.isEmpty else { continue }

            let separatorCount = currentSegments.isEmpty ? 0 : 1
            currentSegments.append(text)
            currentCharacterCount += separatorCount + text.count

            if currentCharacterCount >= targetCharacterCount {
                chunks.append(currentSegments.joined(separator: "\n"))
                currentSegments.removeAll(keepingCapacity: true)
                currentCharacterCount = 0
            }
        }

        if !currentSegments.isEmpty {
            chunks.append(currentSegments.joined(separator: "\n"))
        }
        return chunks
    }
}

struct StructuredSummaryOutput: Sendable, Equatable {
    let title: String
    let summary: String
}

enum SummaryOutputParser {
    static func parse(_ output: String) -> StructuredSummaryOutput? {
        let cleaned = output.cleanedLocalModelResponse
        guard
            let title = content(of: "title", in: cleaned),
            let summary = content(of: "summary", in: cleaned),
            !title.isEmpty,
            !summary.isEmpty
        else {
            return nil
        }
        return StructuredSummaryOutput(title: title, summary: summary)
    }

    private static func content(of tag: String, in text: String) -> String? {
        let openingTag = "<\(tag)>"
        let closingTag = "</\(tag)>"
        guard
            let openingRange = text.range(
                of: openingTag,
                options: .caseInsensitive
            ),
            let closingRange = text.range(
                of: closingTag,
                options: .caseInsensitive,
                range: openingRange.upperBound..<text.endIndex
            )
        else {
            return nil
        }
        return String(text[openingRange.upperBound..<closingRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

actor OnDeviceSummaryService: SummaryService {
    private enum LocalModel {
        static let directoryName = "Qwen3.5-0.8B-MLX-4bit"
        static let relativeDirectory = "Models/Summary/\(directoryName)"
        static let targetChunkCharacters = 5_000
    }

    private let localModelDirectoryOverride: URL?
    private var localModelContainer: ModelContainer?
    private var localModelLoadTask: Task<ModelContainer, Error>?

    init(localModelDirectory: URL? = nil) {
        self.localModelDirectoryOverride = localModelDirectory
    }

    func summarize(segments: [TranscriptDraft]) async throws -> SummaryDraft {
        try Task.checkCancellation()
        let chunks = SummaryInputChunker.chunks(
            from: segments,
            targetCharacterCount: LocalModel.targetChunkCharacters
        )
        guard !chunks.isEmpty else {
            throw StayWordError.emptyTranscript
        }

        #if targetEnvironment(simulator)
        Self.logger.notice(
            "Bundled MLX summary is unavailable in the iOS Simulator."
        )
        throw LocalSummaryError.simulatorUnsupported
        #else
        do {
            return try await generateLocalSummary(chunks: chunks)
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

    private func generateLocalSummary(chunks: [String]) async throws -> SummaryDraft {
        if chunks.count == 1 {
            let finalSummary = try await generateFinalSummary(
                prompt: Self.singleDocumentPrompt(for: chunks[0])
            )
            #if DEBUG
            Self.logSummaryMetrics(
                path: "single",
                inputCharacters: chunks.map(\.count),
                partialCharacters: [],
                finalSummary: finalSummary
            )
            #endif
            return finalSummary
        }

        var partialSummaries: [String] = []

        for chunk in chunks {
            try Task.checkCancellation()
            let response = try await generateLocalResponse(
                prompt: Self.partialDocumentPrompt(for: chunk)
            )
            let summary = response.cleanedPartialSummary
            guard !summary.isEmpty else {
                throw LocalSummaryError.invalidOutput
            }
            try Task.checkCancellation()
            partialSummaries.append(summary)
        }

        let finalSummary = try await generateFinalSummary(
            prompt: Self.integratedDocumentPrompt(for: partialSummaries)
        )
        #if DEBUG
        Self.logSummaryMetrics(
            path: "multi",
            inputCharacters: chunks.map(\.count),
            partialCharacters: partialSummaries.map(\.count),
            finalSummary: finalSummary
        )
        #endif
        return finalSummary
    }

    private func generateFinalSummary(prompt: String) async throws -> SummaryDraft {
        let response = try await generateLocalResponse(prompt: prompt)
        guard let output = SummaryOutputParser.parse(response) else {
            throw LocalSummaryError.invalidOutput
        }
        return SummaryDraft(
            subject: output.title,
            text: output.summary,
            kind: .localLanguageModel
        )
    }

    private func generateLocalResponse(prompt: String) async throws -> String {
        try Task.checkCancellation()
        let container = try await localModel()
        try Task.checkCancellation()
        let session = ChatSession(
            container,
            instructions: Self.systemInstructions,
            generateParameters: GenerateParameters(
                temperature: 0.2,
                topP: 0.9,
                repetitionPenalty: 1.05,
                repetitionContextSize: 64,
                prefillStepSize: 256
            )
        )
        let response = try await session.respond(to: prompt)
        try Task.checkCancellation()
        let cleaned = response.cleanedLocalModelResponse
        guard !cleaned.isEmpty else {
            throw LocalSummaryError.invalidOutput
        }
        return cleaned
    }

    private static let systemInstructions = """
        你是一名智能内容总结与编辑专家。准确理解输入内容，并根据具体任务完成总结或整合。

        只依据输入内容，不补充、猜测或编造信息。
        直接陈述内容，不使用“本文”“本文档”“文章”“原文”“上述内容”“这些材料”等元话语。
        使用与输入内容相同的主要语言。
        根据内容选择自然的段落和组织方式，不套用固定场景或模板。
        """

    private static func partialDocumentPrompt(for text: String) -> String {
        """
        请总结下面这部分内容。你的输出将作为最终整合时理解这一部分的唯一依据，也是长文本流程中唯一的信息压缩阶段。

        完整保留其中有意义的主题、观点、事实、人物、数字、例子、因果关系、结论、决定和待处理事项。可以合并重复表达，但不要用宽泛结论替代具体信息，也不要因为这是中间材料而过度简化。

        直接陈述内容，不使用“本文”“本段”“原文”等元话语。不要把不确定的信息改写为确定事实。
        使用与输入内容相同的主要语言。
        只输出这一部分的摘要正文，不生成标题，不解释任务。

        <text>
        \(text)
        </text>
        """
    }

    private static func singleDocumentPrompt(for text: String) -> String {
        """
        请对下面的完整内容进行总结，并生成一个准确、自然的标题。

        总结应完整覆盖其中有意义的主题、观点、事实、人物、数字、例子、因果关系、结论、决定和待处理事项。合并真正重复的表达，但不要把多个具体信息压缩成空泛概述。

        直接呈现总结内容，不要描述你正在总结一份文本。内容简单时可以使用自然段；内容较复杂时，应通过合适的分段或分点呈现完整的信息层次。

        标题应准确表达核心主题，像自然的笔记标题，不使用“摘要”“总结”“内容记录”等空泛表述，也不要写成冗长的文章副标题。

        只依据输入内容，使用与输入内容相同的主要语言。

        请严格按照下面的结构输出，不要添加其他说明：

        <title>标题</title>
        <summary>
        总结正文
        </summary>

        <text>
        \(text)
        </text>
        """
    }

    private static func integratedDocumentPrompt(
        for partialSummaries: [String]
    ) -> String {
        let parts = partialSummaries.enumerated().map { index, summary in
            """
            <part index="\(index + 1)">
            \(summary)
            </part>
            """
        }.joined(separator: "\n\n")

        return """
        下面是同一内容按照原始顺序生成的分段摘要。请将它们编辑整合成一份连贯、自然、可以独立阅读的最终内容，并生成标题。

        这是编辑整合任务，不是新一轮摘要。保留各部分中所有不重复且有意义的信息，最终正文的信息量应与去重后的分段内容相当。

        只删除真正重复的内容。如果同一主题在多个部分延续，应把相关内容组织到一起，梳理观点、事实、原因、结果、变化和行动之间的关系。不要把多个具体信息重新概括成一句空泛结论。

        改善段落顺序、衔接和表达，使结果看起来像一次完成的智能摘要，而不是多段内容的机械拼接。根据内容复杂度自然分段或分点。

        直接呈现内容，不提及“本文”“本文档”“分段摘要”“材料”或整合过程。

        标题应准确、自然地表达核心主题，不使用空泛表述，也不要写成冗长的文章副标题。

        只依据提供的内容，不补充、猜测或编造信息。使用与输入内容相同的主要语言。

        请严格按照下面的结构输出，不要添加其他说明：

        <title>标题</title>
        <summary>
        最终总结正文
        </summary>

        <parts>
        \(parts)
        </parts>
        """
    }

    #if DEBUG
    private static func logSummaryMetrics(
        path: String,
        inputCharacters: [Int],
        partialCharacters: [Int],
        finalSummary: SummaryDraft
    ) {
        let inputs = inputCharacters.map(String.init).joined(separator: ",")
        let partials = partialCharacters.map(String.init).joined(separator: ",")
        logger.debug(
            "Summary metrics path=\(path, privacy: .public) inputCharacters=[\(inputs, privacy: .public)] partialCharacters=[\(partials, privacy: .public)] finalTitleCharacters=\(finalSummary.subject.count, privacy: .public) finalBodyCharacters=\(finalSummary.text.count, privacy: .public)"
        )
    }
    #endif

    private func localModel() async throws -> ModelContainer {
        if let localModelContainer {
            return localModelContainer
        }
        if let localModelLoadTask {
            return try await waitForLocalModel(localModelLoadTask)
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
            let container = try await waitForLocalModel(task)
            localModelContainer = container
            localModelLoadTask = nil
            return container
        } catch {
            localModelLoadTask = nil
            throw error
        }
    }

    private func waitForLocalModel(
        _ task: Task<ModelContainer, Error>
    ) async throws -> ModelContainer {
        try await withTaskCancellationHandler {
            let container = try await task.value
            try Task.checkCancellation()
            return container
        } onCancel: {
            task.cancel()
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

private extension String {
    var cleanedLocalModelResponse: String {
        var result = replacingOccurrences(
            of: #"(?s)<think>.*?</think>"#,
            with: "",
            options: .regularExpression
        )
        result = result
            .replacingOccurrences(of: "```text", with: "")
            .replacingOccurrences(of: "```markdown", with: "")
            .replacingOccurrences(of: "```xml", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return result
    }

    var cleanedPartialSummary: String {
        var result = cleanedLocalModelResponse
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
}

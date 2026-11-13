import Foundation
import Testing

@testable import VoiceInk

@Suite("AutoLearn correction diff")
struct AutoLearnCorrectionDiffTests {
    @Test func extractsWordFromLongChineseParagraph() throws {
        let prefix = "今天我们一起讨论工作计划并且认真检查所有需要准备的资料，接下来请购买"
        let revision = AutoLearnRevision(original: prefix + "苹果。", corrected: prefix + "香蕉。")
        #expect(revision.original.count > 32)
        let candidates = CorrectionDiffEngine.candidates(from: revision, usesAIReviewer: false)
        #expect(candidates.count == 1)
        let candidate = try #require(candidates.first)
        let pair = try #require(CorrectionDiffEngine.replacementPair(from: .init(
            original: candidate.originalText, corrected: candidate.correctedText)))
        #expect(pair.source == "苹果")
        #expect(pair.destination == "香蕉")
    }

    @Test func chinesePunctuationBoundsReviewContext() throws {
        let revision = AutoLearnRevision(original: "这是私人背景，苹果。不要包含后面的句子。",
            corrected: "这是私人背景，香蕉。不要包含后面的句子。")
        let candidate = try #require(CorrectionDiffEngine.candidates(from: revision, usesAIReviewer: false).first)
        #expect(candidate.originalText == "苹果")
        #expect(candidate.correctedText == "香蕉")
    }

    @Test func shortChineseWordsRemainEligible() {
        #expect(AutoLearnLocalReviewPolicy.accepts(source: "苹果", destination: "香蕉"))
        #expect(AutoLearnLocalReviewPolicy.accepts(source: "北京", destination: "上海"))
    }

    @Test func rejectsSingletonHanRulesEvenWithAIReview() {
        #expect(!AutoLearnLocalReviewPolicy.fitsLimits(source: "他", destination: "她"))
        #expect(CorrectionDiffEngine.candidates(from: .init(original: "他", corrected: "她"),
            usesAIReviewer: true).isEmpty)
    }

    @Test func sentenceIsNotOneWhitespaceWord() {
        #expect(!AutoLearnLocalReviewPolicy.fitsLimits(source: "今天我们一起讨论工作计划并且认真检查资料",
            destination: "明天他们一起购买新鲜水果然后回到办公室"))
        #expect(!AutoLearnLocalReviewPolicy.fitsLimits(source: "苹果，香蕉", destination: "北京，上海"))
    }

    @Test func candidatePrivacyLimitRemainsInForce() {
        #expect(!AutoLearnLocalReviewPolicy.fitsLimits(source: String(repeating: "苹果", count: 17),
            destination: String(repeating: "香蕉", count: 17)))
    }

    @Test func englishSegmentationAndFiltersUnchanged() throws {
        let pair = try #require(CorrectionDiffEngine.replacementPair(from: .init(
            original: "Please use Acmee today.", corrected: "Please use Acme today.")))
        #expect(pair.source == "Acmee")
        #expect(pair.destination == "Acme")
        #expect(!AutoLearnLocalReviewPolicy.accepts(source: "go", destination: "went"))
        #expect(!AutoLearnLocalReviewPolicy.accepts(source: "wanna", destination: "want to"))
    }

    @Test func punctuationOnlyAndPureInsertionsDoNotCreateRules() {
        #expect(CorrectionDiffEngine.candidates(from: .init(original: "苹果。", corrected: "苹果！"),
            usesAIReviewer: false).isEmpty)
        #expect(CorrectionDiffEngine.candidates(from: .init(original: "苹果", corrected: "苹果 香蕉"),
            usesAIReviewer: false).isEmpty)
    }
    @Test func placeholderCannotReplaceOriginalSentence() {
        let revision = AutoLearnRevision(original: "我改成公开的了，本身也没什么敏感的。", corrected: "发送消息")
        #expect(CorrectionDiffEngine.candidates(from: revision, usesAIReviewer: false).isEmpty)
        #expect(CorrectionDiffEngine.candidates(from: revision, usesAIReviewer: true).isEmpty)
    }

    @Test func tokenizerRespectsRequestedSpan() {
        let text = "前面的私人信息，苹果。后面的私人信息"
        let range = text.range(of: "苹果")!
        let tokens = AutoLearnChineseTokenization.wordRanges(in: text, range: range)
        #expect(!tokens.isEmpty)
        #expect(tokens.allSatisfy { $0.lowerBound >= range.lowerBound && $0.upperBound <= range.upperBound })
        #expect(tokens.map { String(text[$0]) }.joined() == "苹果")
    }

    @Test func chineseTermsCanReachTheAIReviewerWithoutTranslation() {
        let candidate = AutoLearnReviewCandidate(candidateID: UUID(),
            originalText: "北京", correctedText: "上海")
        #expect(AutoLearnAIReviewer.canReview(candidate))
        #expect(AutoLearnAIReviewer.instructions.contains("including Chinese and English"))
        #expect(AutoLearnAIReviewer.instructions.contains("Do not translate"))
    }

}

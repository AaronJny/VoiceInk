import Testing
@testable import VoiceInk

@Suite("AutoLearn field identity")
struct AutoLearnFieldIdentityTests {
    private func field(role: String = "AXTextArea", identifier: String? = "composer",
        editable: Bool = true, placeholder: String? = "发送消息", count: Int? = nil
    ) -> AutoLearnFieldIdentity {
        AutoLearnFieldIdentity(role: role, subrole: nil, identifier: identifier,
            isEditable: editable, placeholder: placeholder, characterCount: count)
    }

    @Test func observedCorrectionSurvivesSendingButOriginalDoesNotBecomeCorrection() {
        var edited = AutoLearnObservedEdit(baseline: "联系张山", capturedIdentity: field())
        edited.observe("联系张三", identity: field())
        edited.observe("发送消息", identity: field(count: 0))
        #expect(edited.lastEditedText == "联系张三")
        edited.observe("", identity: field(count: 0))
        #expect(edited.lastEditedText == "联系张三")
        var untouched = AutoLearnObservedEdit(baseline: "联系张山", capturedIdentity: field())
        untouched.observe("联系张山", identity: field())
        untouched.observe("发送消息", identity: field(count: 0))
        #expect(untouched.lastEditedText == nil)
    }

    @Test func sendSealsCorrectionBeforeNextMessageUsesSameComposer() {
        var edited = AutoLearnObservedEdit(baseline: "联系张山", capturedIdentity: field())
        edited.observe("联系张三", identity: field())
        edited.observe("发送消息", identity: field())
        edited.observe("全新的下一条消息", identity: field())
        #expect(edited.ended)
        #expect(edited.lastEditedText == "联系张三")
        edited.observe("其他元素", identity: field(identifier: "other"))
        #expect(edited.invalidated)
        #expect(edited.lastEditedText == nil)

        var untouched = AutoLearnObservedEdit(baseline: "联系张山", capturedIdentity: field())
        untouched.observe("", identity: field(count: 0))
        untouched.observe("全新的下一条消息", identity: field())
        #expect(untouched.ended)
        #expect(untouched.lastEditedText == nil)
    }

    @Test func undoAndReusedControlDiscardPreviouslyObservedCorrection() {
        var undone = AutoLearnObservedEdit(baseline: "联系张山", capturedIdentity: field())
        undone.observe("联系张三", identity: field())
        undone.observe("联系张山", identity: field())
        undone.observe("发送消息", identity: field())
        #expect(undone.lastEditedText == nil)
        var reused = AutoLearnObservedEdit(baseline: "联系张山", capturedIdentity: field())
        reused.observe("联系张三", identity: field())
        reused.observe("Other", identity: field(identifier: "other"))
        reused.observe("联系张三", identity: field())
        #expect(reused.invalidated)
        #expect(reused.lastEditedText == nil)
    }

    @Test func sentFieldPlaceholderIsNotACorrection() {
        #expect(!field().acceptsFinalText("发送消息", captured: field()))
        #expect(!field(placeholder: "Write a message").acceptsFinalText(
            "Write a message", captured: field()))
        #expect(!field(count: 0).acceptsFinalText("发送消息", captured: field()))
    }

    @Test func capturedPlaceholderStillProtectsAfterAttributeDisappears() {
        #expect(!field(placeholder: nil).acceptsFinalText("发送消息", captured: field()))
        #expect(!field(placeholder: nil).acceptsFinalText(
            "Write\u{00A0}a message\u{200B}", captured: field(placeholder: "Write a message")))
        #expect(field(placeholder: nil).acceptsFinalText("真正修改的内容", captured: field()))
        #expect(field(placeholder: "").acceptsFinalText("", captured: field(placeholder: "")))
    }

    @Test func unchangedEditorAllowsRealManualCorrectionsAfterFocusLeaves() {
        #expect(field().acceptsFinalText("我改成公开的了。", captured: field()))
        #expect(!field(count: 4).acceptsFinalText("发送消息", captured: field()))
        #expect(field(count: 0).acceptsFinalText("", captured: field()))
    }

    @Test func repurposedOrNoneditableElementIsRejected() {
        #expect(!field(role: "AXButton").acceptsFinalText("发送消息", captured: field()))
        #expect(!field(identifier: "other-composer").acceptsFinalText("different", captured: field()))
        #expect(!field(editable: false).acceptsFinalText("different", captured: field()))
        #expect(!field(count: 0).acceptsFinalText("UI metadata", captured: field()))
    }
}

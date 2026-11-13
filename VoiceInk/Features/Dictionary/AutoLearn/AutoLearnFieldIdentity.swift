import Foundation

/// Metadata associated with the captured editor, not the currently focused control.
struct AutoLearnFieldIdentity: Equatable {
    let role: String?
    let subrole: String?
    let identifier: String?
    let isEditable: Bool
    let placeholder: String?
    let characterCount: Int?

    func matchesEditor(_ captured: AutoLearnFieldIdentity) -> Bool {
        isEditable && role == captured.role && subrole == captured.subrole
            && identifier == captured.identifier
    }

    func acceptsFinalText(_ text: String, captured: AutoLearnFieldIdentity) -> Bool {
        guard matchesEditor(captured) else { return false }
        // Some editors expose placeholder text even through text-range APIs.
        // A result equal to the editor's own placeholder is ambiguous: skip
        // learning rather than proposing a destructive replacement.
        let normalized = AutoLearnTextNormalizer.accessibilityComparable(text)
        let placeholders = [placeholder, captured.placeholder].compactMap { $0 }
            .map { AutoLearnTextNormalizer.accessibilityComparable($0) }
            .filter { !$0.isEmpty }
        if placeholders.contains(normalized) { return false }
        // A nonempty value for an explicitly empty document is UI metadata.
        return characterCount != 0 || normalized.isEmpty
    }
}

/// Keeps only observed edits, never an inferred correction from an empty editor.
struct AutoLearnObservedEdit {
    let baseline: String
    let capturedIdentity: AutoLearnFieldIdentity
    private(set) var lastEditedText: String?
    private(set) var invalidated = false
    private(set) var ended = false

    mutating func observe(_ text: String, identity: AutoLearnFieldIdentity) {
        guard !invalidated else { return }
        guard identity.matchesEditor(capturedIdentity) else {
            invalidated = true
            lastEditedText = nil
            return
        }
        guard !ended else { return }
        guard identity.acceptsFinalText(text, captured: capturedIdentity),
            !AutoLearnTextNormalizer.accessibilityComparable(text).isEmpty else {
            // Sending and clearing to rewrite cannot be distinguished safely.
            // Seal this observation so the next message cannot replace its edit.
            ended = true
            return
        }
        if AutoLearnTextNormalizer.accessibilityComparable(text)
            == AutoLearnTextNormalizer.accessibilityComparable(baseline) {
            lastEditedText = nil // An observed undo cancels the proposed learning.
        } else {
            lastEditedText = text
        }
    }
}

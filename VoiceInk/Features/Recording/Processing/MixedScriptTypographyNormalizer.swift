import Foundation

enum MixedScriptTypographyNormalizer {
    private static let punctuationMap: [Character: Character] = [
        ",": "，",
        ".": "。",
        "!": "！",
        "?": "？",
        ";": "；",
        ":": "：",
    ]

    private static let protectedPatterns = [
        #"(?s)(`{3,}).*?\1"#,
        #"(?s)(~{3,}).*?\1"#,
        #"(?s)(`+).*?\1"#,
    ]

    static func normalize(_ text: String) -> String {
        guard !text.isEmpty else { return text }

        let protected = protectSpans(in: text)
        let localized = localizePunctuation(in: protected.text)
        let spaced = insertSpaces(in: localized)
        return restoreSpans(in: spaced, replacements: protected.replacements)
    }

    private static func protectSpans(in text: String) -> (text: String, replacements: [(String, String)]) {
        var maskedText = text
        var replacements: [(String, String)] = []
        var tokenPrefix = "VOICEINKPROTECTEDSPAN"
        var tokenIndex = 0

        while text.contains(tokenPrefix) {
            tokenPrefix.append("X")
        }

        for pattern in protectedPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(maskedText.startIndex..., in: maskedText)
            let matches = regex.matches(in: maskedText, range: range)

            for match in matches.reversed() {
                let source = maskedText as NSString
                let original = source.substring(with: match.range)
                let token = "\(tokenPrefix)\(tokenIndex)TOKEN"
                tokenIndex += 1
                replacements.append((token, original))
                maskedText = source.replacingCharacters(in: match.range, with: token)
            }
        }

        return (maskedText, replacements)
    }

    private static func restoreSpans(in text: String, replacements: [(String, String)]) -> String {
        replacements.reversed().reduce(text) { result, replacement in
            result.replacingOccurrences(of: replacement.0, with: replacement.1)
        }
    }

    private static func localizePunctuation(in text: String) -> String {
        let characters = Array(text)
        return String(characters.indices.map { index in
            let character = characters[index]
            guard let replacement = punctuationMap[character] else { return character }
            guard !isInsideURL(at: index, in: characters) else { return character }

            let previous = index > characters.startIndex ? characters[index - 1] : nil
            let next = index < characters.index(before: characters.endIndex) ? characters[index + 1] : nil
            guard !isASCIIPunctuation(previous), !isASCIIPunctuation(next) else {
                return character
            }

            if character == "." {
                let endsHanSentence = isHan(previous) && (next == nil || next?.isWhitespace == true || isHan(next))
                return endsHanSentence ? replacement : character
            }

            return isHan(previous) || isHan(next) ? replacement : character
        })
    }

    private static func insertSpaces(in text: String) -> String {
        let characters = Array(text)
        guard characters.count > 1 else { return text }

        var result = ""
        result.reserveCapacity(text.count)

        for index in characters.indices {
            let current = characters[index]
            result.append(current)
            guard index < characters.index(before: characters.endIndex) else { continue }

            let next = characters[index + 1]
            if needsBoundarySpace(between: current, and: next) {
                result.append(" ")
            }
        }

        return result
    }

    private static func needsBoundarySpace(between left: Character, and right: Character) -> Bool {
        (isHan(left) && isLatinOrDigit(right)) || (isLatinOrDigit(left) && isHan(right))
    }

    private static func isASCIIPunctuation(_ character: Character?) -> Bool {
        character.map { punctuationMap[$0] != nil } == true
    }

    private static func isInsideURL(at index: Int, in characters: [Character]) -> Bool {
        var tokenStart = index
        while tokenStart > characters.startIndex, !characters[tokenStart - 1].isWhitespace {
            tokenStart -= 1
        }

        let prefix = String(characters[tokenStart...index]).lowercased()
        return prefix.contains("http://") || prefix.contains("https://")
    }

    private static func isHan(_ character: Character?) -> Bool {
        character?.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF,
                0x20000...0x2EBEF, 0x30000...0x3134F:
                return true
            default:
                return false
            }
        } == true
    }

    private static func isLatinOrDigit(_ character: Character?) -> Bool {
        character?.unicodeScalars.contains { scalar in
            CharacterSet.decimalDigits.contains(scalar) || isLatin(scalar)
        } == true
    }

    private static func isLatin(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x0041...0x005A, 0x0061...0x007A, 0x00C0...0x02AF, 0x1E00...0x1EFF, 0xAB30...0xAB6F:
            return true
        default:
            return false
        }
    }
}

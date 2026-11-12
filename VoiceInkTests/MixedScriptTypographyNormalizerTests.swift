import Testing
@testable import VoiceInk

@Suite("Mixed-script typography normalization")
struct MixedScriptTypographyNormalizerTests {
    @Test func formatsTypicalRefineOutput() {
        let input = "我测试了,Refine V1整体的效果还凑合,速度非常快."

        #expect(
            MixedScriptTypographyNormalizer.normalize(input)
                == "我测试了，Refine V1 整体的效果还凑合，速度非常快。"
        )
    }

    @Test func spacesHanLatinAndNumericBoundaries() {
        let input = "我在VoiceInk里测试qwen3.5版本2.1"

        #expect(
            MixedScriptTypographyNormalizer.normalize(input)
                == "我在 VoiceInk 里测试 qwen3.5 版本 2.1"
        )
    }

    @Test func leavesPureEnglishProseUnchanged() {
        let input = "Hello,world!Next sentence.Good"

        #expect(MixedScriptTypographyNormalizer.normalize(input) == input)
    }

    @Test func preservesStructuredNumbersAndVersions() {
        let input = "圆周率3.14,版本v2.1.0在12:30发布,共有1,000人"

        #expect(
            MixedScriptTypographyNormalizer.normalize(input)
                == "圆周率 3.14，版本 v2.1.0 在 12:30 发布，共有 1,000 人"
        )
    }

    @Test func preservesUnicodeURLsAndEmailAddresses() {
        let input = "访问https://example.com/中文?q=1然后发送到foo+tag@example.com联系我"

        #expect(
            MixedScriptTypographyNormalizer.normalize(input)
                == "访问 https://example.com/中文?q=1 然后发送到 foo+tag@example.com 联系我"
        )
    }

    @Test func protectsPathsAndInlineCode() {
        let input = "打开/Users/aaron/中文/file.swift然后调用`foo中文bar()`方法"

        #expect(
            MixedScriptTypographyNormalizer.normalize(input)
                == "打开/Users/aaron/中文/file.swift 然后调用 `foo中文bar()` 方法"
        )
    }

    @Test func preservesTechnicalDotTokens() {
        let input = "打开.env文件并读取对象.property和值"

        #expect(
            MixedScriptTypographyNormalizer.normalize(input)
                == "打开.env 文件并读取对象.property 和值"
        )
    }

    @Test func preservesPunctuationRuns() {
        let input = "等等...真的吗?!"

        #expect(MixedScriptTypographyNormalizer.normalize(input) == input)
    }

    @Test func protectsMultiBacktickCode() {
        let input = "调用``foo`中文bar``方法"

        #expect(
            MixedScriptTypographyNormalizer.normalize(input)
                == "调用 ``foo`中文bar`` 方法"
        )
    }

    @Test func preservesParagraphBreaks() {
        let input = "第一段VoiceInk。\n\n第二段2个。"

        #expect(
            MixedScriptTypographyNormalizer.normalize(input)
                == "第一段 VoiceInk。\n\n第二段 2 个。"
        )
    }

    @Test func isIdempotent() {
        let once = MixedScriptTypographyNormalizer.normalize("使用VoiceInk处理3个文件,很快.")

        #expect(MixedScriptTypographyNormalizer.normalize(once) == once)
    }

    @Test func leavesAlreadyFormattedChineseUnchanged() {
        let input = "这是已经正确排版的中文。下一句也正常！"

        #expect(MixedScriptTypographyNormalizer.normalize(input) == input)
    }

}

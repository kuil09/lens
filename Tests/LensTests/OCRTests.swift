import CoreGraphics
import Testing
@testable import Lens

private func line(_ text: String, x: CGFloat = 0.1, y: CGFloat = 0.8,
                  width: CGFloat = 0.35, language: LensLanguage? = .english,
                  confidence: Float = 0.9) -> TextBlock {
    TextBlock(text: text, bounds: CGRect(x: x, y: y, width: width, height: 0.03),
              language: language, confidence: confidence)
}

@Suite struct OCRTests {
@Test func recognitionLanguageValidation() throws {
    let supported = ["ko-KR", "ja-JP", "en-US", "fr-FR"]
    #expect(try OCRService.recognitionLanguages(supported: supported, source: nil) == supported)
    #expect(try OCRService.recognitionLanguages(supported: ["ja-JP"], source: .japanese) == ["ja-JP"])
    #expect(try OCRService.recognitionLanguages(supported: ["en-US"], source: nil) == ["en-US"])
    #expect(throws: OCRServiceError.unsupportedRecognitionLanguages(["ko"])) {
        try OCRService.recognitionLanguages(supported: ["en-US"], source: .korean)
    }
}

@Test func conservativeLanguageDetection() {
    #expect(OCRService.detectLanguage("설정") == .korean)
    #expect(OCRService.detectLanguage("カメラの設定") == .japanese)
    #expect(OCRService.detectLanguage("This is a complete sentence written in English.") == .english)
    for text in ["OK", "Oui", "設定", "12345", "", "Привет"] {
        #expect(OCRService.detectLanguage(text) == nil)
    }
    #expect(OCRService.detectLanguage("OK", source: .japanese) == .japanese)
    #expect(OCRService.detectLanguage("Bonjour tout le monde, comment allez vous aujourd'hui?")?.languageCode == "fr")
    #expect(OCRService.detectLanguage("这是一个中文句子")?.languageCode == "zh")
    #expect(OCRService.detectLanguage("Bonjour tout le monde, comment allez vous aujourd'hui?", languages: [.english, .korean]) == nil)
}

@Test func neighboringContextIsLocalAndDoesNotGuessLatin() {
    let lines = [line("これは日本語の説明です", y: 0.8), line("設定", y: 0.75),
                 line("設定", x: 0.6, y: 0.75), line("Oui", y: 0.60), line("設定", y: 0.3)]
    let result = OCRService.assignLanguages(to: lines)
    #expect(result.map(\.language) == [.japanese, .japanese, nil, nil, nil])
    #expect(result[1].id == lines[1].id)
    #expect(OCRService.assignLanguages(to: lines, source: .korean).allSatisfy { $0.language == .korean })
    let conflicting = [lines[0], lines[1], line("한국어 설명입니다", y: 0.70)]
    #expect(OCRService.assignLanguages(to: conflicting)[1].language == nil)
    let unknownNeighbor = [lines[0], lines[1], line("Oui", y: 0.70)]
    #expect(OCRService.assignLanguages(to: unknownNeighbor)[1].language == nil)
}

@Test func paragraphGroupingPreservesColumnsAndCoordinates() {
    let a = line("This is the first paragraph line.", y: 0.8, confidence: 0.8)
    let b = line("This is the second paragraph line.", y: 0.76)
    let c = line("This belongs to another column.", x: 0.6, y: 0.8)
    let d = line("This continues the other column.", x: 0.6, y: 0.76)
    let result = OCRService.groupParagraphs([d, b, c, a])
    #expect(result.count == 2)
    #expect(result[0].text == a.text + "\n" + b.text)
    #expect(result[0].bounds == a.bounds.union(b.bounds))
    #expect(result[0].bounds.minY == 0.76)
    #expect(result[0].id == a.id)
    #expect(result[0].confidence > 0.8 && result[0].confidence < 0.9)
    #expect(result[1].text == c.text + "\n" + d.text)
}

@Test func controlsGapsAndDifferentLanguagesStaySeparate() {
    #expect(OCRService.groupParagraphs([line("Settings"), line("Continue", y: 0.76)]).count == 2)
    let a = line("This is a sufficiently long sentence.")
    #expect(OCRService.groupParagraphs([a, line(a.text, y: 0.65)]).count == 2)
    #expect(OCRService.groupParagraphs([a, line(a.text, y: 0.76, language: .japanese)]).count == 2)
    #expect(OCRService.groupParagraphs([a, line(a.text, x: 0.5)]).count == 2)
    #expect(OCRService.groupParagraphs([]).isEmpty)
    #expect(OCRService.groupParagraphs([line("  ")]).isEmpty)
}
}

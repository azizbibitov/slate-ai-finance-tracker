import Foundation

enum ParserFactory {
    static func make() -> any InputParserProtocol {
        // Future: if #available(iOS 26, *), device eligible → FoundationModelsParser
        return GroqInputParser()
    }
}

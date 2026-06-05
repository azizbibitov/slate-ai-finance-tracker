import Foundation

struct ParserContext: Sendable {
    struct AccountInfo: Sendable {
        let name: String
        let currency: String
        let isDefault: Bool
    }
    let accounts: [AccountInfo]
    static let empty = ParserContext(accounts: [])
}

protocol InputParserProtocol: AnyObject {
    func parse(input: String, context: ParserContext) async throws -> ParsedInput
}

enum ParserError: Error {
    case apiError
    case emptyResponse
    case decodingFailed
    case notUnderstood
}

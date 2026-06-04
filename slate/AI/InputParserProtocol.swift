import Foundation

protocol InputParserProtocol: AnyObject {
    func parse(input: String) async throws -> ParsedInput
}

enum ParserError: Error {
    case apiError
    case emptyResponse
    case decodingFailed
    case notUnderstood
}

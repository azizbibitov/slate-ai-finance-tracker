import Foundation

protocol InputParserProtocol: AnyObject {
    func parse(input: String) async throws -> ParsedInput
}

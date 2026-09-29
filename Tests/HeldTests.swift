import Foundation
import Testing
@testable import AICLILimits

/// Counts its reads and answers with whatever it was given.
private final class FakeReader {
    private(set) var reads = 0
    var answer: Result<String, Error>

    init(_ answer: Result<String, Error>) { self.answer = answer }

    func read() throws -> String {
        reads += 1
        return try answer.get()
    }
}

private struct Unreadable: Error {}

@Suite("Held") struct HeldTests {

    @Test("should read once and answer later gets from the held value")
    func reuse() throws {
        let reader = FakeReader(.success("token-1"))
        let held = Held(read: reader.read)

        let first = try held.get()
        let second = try held.get()

        #expect(first == "token-1")
        #expect(second == "token-1")
        #expect(reader.reads == 1)
    }

    @Test("should read again when the held value was dropped")
    func rereadAfterDrop() throws {
        let reader = FakeReader(.success("token-1"))
        let held = Held(read: reader.read)
        _ = try held.get()
        reader.answer = .success("token-2")

        held.drop()
        let rotated = try held.get()

        #expect(rotated == "token-2")
        #expect(reader.reads == 2)
    }

    @Test("should hold nothing when the read throws")
    func failedReadHoldsNothing() throws {
        let reader = FakeReader(.failure(Unreadable()))
        let held = Held(read: reader.read)
        #expect(throws: Unreadable.self) { try held.get() }
        reader.answer = .success("token-1")

        let recovered = try held.get()

        #expect(recovered == "token-1")
        #expect(reader.reads == 2)
    }
}

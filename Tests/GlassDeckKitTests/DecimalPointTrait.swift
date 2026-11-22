import Testing
@testable import GlassDeckKit

/// Pins the decimal separator to a full stop for a suite whose expectations
/// are written that way, so the tests pass whatever region the machine is set
/// to (this one is Italian, and would otherwise print "1,5 GB").
struct DecimalPointTrait: SuiteTrait, TestTrait, TestScoping {
    func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        try await ValueFormatter.$decimalSeparator.withValue(".", operation: function)
    }
}

extension Trait where Self == DecimalPointTrait {
    static var decimalPoint: Self { Self() }
}

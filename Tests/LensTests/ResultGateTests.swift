import Testing
@testable import Lens

@Test func delayedResponseAfterScrollIsRejected() {
    var gate = ResultGate()
    let before = gate.version
    gate.contentChanged()
    #expect(!gate.accepts(before))
    let newer = gate.version
    #expect(gate.accepts(newer))
    gate.regionChanged()
    #expect(!gate.accepts(newer))
}
@Test func noiseAndGlyphChanges() {
    let blank = FrameFingerprint(bytes: Array(repeating: 120, count: 40))
    #expect(!blank.differs(from: FrameFingerprint(bytes: Array(repeating: 121, count: 40))))
    var changed = blank.bytes; changed[0] = 0; changed[4] = 0
    #expect(blank.differs(from: FrameFingerprint(bytes: changed)))
}

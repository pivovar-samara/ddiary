// Pure validation helpers for warning detection and confirmation decisions.
// These functions avoid UI and app-type dependencies so they can be unit tested easily.

import Foundation

enum BPConstraints {
    static let systolicRange: ClosedRange<Int> = 50...260
    static let diastolicRange: ClosedRange<Int> = 30...160
    static let pulseRange: ClosedRange<Int> = 30...220
}

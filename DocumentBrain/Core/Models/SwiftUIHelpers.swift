import SwiftUI

// MARK: - Binding helpers

extension Binding where Value == Bool {
    /// Creates a `Bool` binding that is `true` while `optional` is non-nil,
    /// and sets it to `nil` when the binding is set to `false`.
    static func isPresent<T>(_ optional: Binding<T?>) -> Binding<Bool> {
        Binding(
            get: { optional.wrappedValue != nil },
            set: { if !$0 { optional.wrappedValue = nil } }
        )
    }
}

import SwiftUI
import XCTest
@testable import BlindensportGraz

/// `Binding(isPresent:)` drives alerts from an optional: shown while it holds
/// a value, and dismissing the alert clears it.
@MainActor
final class BindingIsPresentTests: XCTestCase {
    private final class Box { var message: String? }

    private func binding(_ box: Box) -> Binding<String?> {
        Binding(get: { box.message }, set: { box.message = $0 })
    }

    func testIsPresentFollowsTheOptional() {
        let box = Box()
        let isPresented = Binding(isPresent: binding(box))

        XCTAssertFalse(isPresented.wrappedValue)
        box.message = "Export fehlgeschlagen"
        XCTAssertTrue(isPresented.wrappedValue)
    }

    func testDismissingClearsTheValue() {
        let box = Box()
        box.message = "Export fehlgeschlagen"
        let isPresented = Binding(isPresent: binding(box))

        isPresented.wrappedValue = false

        XCTAssertNil(box.message)
    }

    func testSettingTrueKeepsTheValue() {
        let box = Box()
        box.message = "Fehler"
        let isPresented = Binding(isPresent: binding(box))

        isPresented.wrappedValue = true

        XCTAssertEqual(box.message, "Fehler")
    }
}

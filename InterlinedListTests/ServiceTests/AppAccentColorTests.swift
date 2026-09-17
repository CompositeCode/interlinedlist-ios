import XCTest
import SwiftUI
import UIKit
@testable import InterlinedList

/// The app is branded by the `AccentColor` asset rather than by a `.tint`
/// modifier: the asset becomes the process-wide UIKit tint, so it reaches every
/// surface — sheets, alerts and UIKit-hosted chrome included — where a `.tint`
/// set inside `RootView` only reaches that view's own subtree (#102).
final class AppAccentColorTests: XCTestCase {
    private let light = UITraitCollection(userInterfaceStyle: .light)
    private let dark = UITraitCollection(userInterfaceStyle: .dark)

    func test_infoPlist_declaresTheAccentColorAsset() {
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "NSAccentColorName") as? String,
            "AccentColor"
        )
    }

    // `ILColor.primary` is `green` in light and `greenDark` in dark; the two halves
    // are compared separately because `UIColor(_: Color)` resolves a dynamic color
    // eagerly and loses the appearance provider.
    func test_accentAsset_matchesBrandGreen_inLight() throws {
        let accent = try XCTUnwrap(UIColor(named: "AccentColor"))
        assertSameColor(accent, UIColor(ILColor.green), with: light)
    }

    func test_accentAsset_matchesBrandGreenDark_inDark() throws {
        let accent = try XCTUnwrap(UIColor(named: "AccentColor"))
        assertSameColor(accent, UIColor(ILColor.greenDark), with: dark)
    }

    func test_processTint_isTheAccentAsset_notSystemBlue_inLight() throws {
        // Touching a UIAppearance proxy from `App.init()` makes UIKit fall back to
        // the system-blue tint for the whole process and silently ignore the asset;
        // that is why `configureNavigationBarAppearance()` runs from the app
        // delegate's launch callback instead.
        let accent = try XCTUnwrap(UIColor(named: "AccentColor"))
        assertSameColor(UIColor.tintColor, accent, with: light)
    }

    func test_processTint_isTheAccentAsset_notSystemBlue_inDark() throws {
        let accent = try XCTUnwrap(UIColor(named: "AccentColor"))
        assertSameColor(UIColor.tintColor, accent, with: dark)
    }

    private func assertSameColor(
        _ lhs: UIColor,
        _ rhs: UIColor,
        with traits: UITraitCollection,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let left = components(of: lhs.resolvedColor(with: traits))
        let right = components(of: rhs.resolvedColor(with: traits))
        XCTAssertEqual(left.red, right.red, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(left.green, right.green, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(left.blue, right.blue, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(left.alpha, right.alpha, accuracy: 0.01, file: file, line: line)
    }

    private func components(of color: UIColor) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return (red, green, blue, alpha)
    }
}

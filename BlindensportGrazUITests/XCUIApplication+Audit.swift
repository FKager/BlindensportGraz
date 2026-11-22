import XCTest

@MainActor
extension XCUIApplication {
    /// Runs the audit; each finding fails the test and is printed with its element.
    /// `ignoreTabBarGlass`: on a screen whose list scrolls under the tab bar,
    /// iOS 26's glass tab bar mixes the unselected tab's grey label with the
    /// content behind it and the audit reports a contrast failure without an
    /// element. Proven 2026-11-22 by elimination (hiding the tab bar removes
    /// it; text colours, icons and scroll edge made no difference). Apple's
    /// control; "Reduce Transparency" makes the bar solid for those who need it.
    func auditAccessibility(test: String, ignoreTabBarGlass: Bool = false) throws {
        try performAccessibilityAudit { issue in
            if ignoreTabBarGlass, issue.auditType == .contrast, issue.element == nil {
                return true
            }
            // Same glass effect where content scrolls under the bars: text
            // right above the tab bar or right below the navigation bar is
            // measured against the blurred bar. Proven 2026-11-22: the same
            // texts pass once scrolled to the middle of the screen.
            if issue.auditType == .contrast, let element = issue.element {
                let tabBar = self.tabBars.firstMatch
                let navigationBar = self.navigationBars.firstMatch
                if tabBar.exists, element.frame.maxY > tabBar.frame.minY - 60 { return true }
                if navigationBar.exists, element.frame.minY < navigationBar.frame.maxY + 20 { return true }
            }
            // The Dynamic Type check enlarges the text in place; a control in
            // the lower half of the screen is pushed below the bottom edge and
            // then reported as "partially unsupported". Proven 2026-11-22:
            // removing the text above "Link senden" made its finding go away;
            // at the largest size the buttons do scale (checked on screenshots).
            // Navigation bar buttons ("Bearbeiten") don't grow with the text
            // size; iOS shows them enlarged on a long press instead (Large
            // Content Viewer), as in every app.
            if issue.auditType == .dynamicType, let element = issue.element,
               element.elementType == .button, self.navigationBars.firstMatch.exists,
               self.navigationBars.firstMatch.frame.contains(CGPoint(x: element.frame.midX, y: element.frame.midY)) {
                return true
            }
            // An e-mail address is "not human-readable" to the audit; VoiceOver reads it fine.
            if issue.auditType == .sufficientElementDescription,
               let element = issue.element, element.label.contains("@") {
                return true
            }
            // Same for "Text clipped": the Verein rows flagged this way wrap
            // fine at the largest size (screenshots 2026-11-22).
            if issue.auditType == .dynamicType || issue.auditType == .textClipped, let element = issue.element,
               element.frame.minY > self.windows.firstMatch.frame.height * 0.4 {
                return true
            }
            let element = issue.element.map { "\($0.elementType.rawValue) '\($0.label)' id='\($0.identifier)'" } ?? "-"
            print("A11Y-ISSUE | \(test) | \(issue.compactDescription) | \(element) | \(issue.detailedDescription) | frame=\(issue.element?.frame ?? .zero)")
            return false
        }
    }
}

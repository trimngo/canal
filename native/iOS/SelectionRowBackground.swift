import SwiftUI

/// A solid fill and outline keep selection clear in both appearances without
/// adding a checkbox column or changing the compact outline layout.
struct SelectionRowBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    let selected: Bool

    var body: some View {
        if selected {
            Rectangle()
                .fill(colorScheme == .dark ? Color(red: 0.08, green: 0.30, blue: 0.26) : Color.accentColor.opacity(0.16))
                .overlay {
                    Rectangle().strokeBorder(colorScheme == .dark ? Color.mint : Color.accentColor, lineWidth: 2)
                }
        } else {
            Color.clear
        }
    }
}

import SwiftUI

/// A section's first row, like the cards in iOS Settings: its title, an info button that explains
/// what the section is for, and any actions on the right. The content follows below a separator.
struct SectionIntro<Accessory: View>: View {
    let title: String
    let info: String?
    let accessory: Accessory

    init(_ title: String, info: String? = nil, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.info = info
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.mono(.title3, weight: .bold))
                .accessibilityAddTraits(.isHeader)
            if let info {
                InfoButton(title: title, message: info)
            }
            Spacer(minLength: 0)
            accessory
                .font(.mono(.footnote, weight: .semibold))
        }
        // Each control takes its own taps, rather than the whole row acting as one button.
        .buttonStyle(.borderless)
        .padding(.vertical, 4)
        // Otherwise the separator below can start at the accessory's text instead of the title.
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
    }
}

extension SectionIntro where Accessory == EmptyView {
    init(_ title: String, info: String? = nil) {
        self.init(title, info: info) { EmptyView() }
    }
}

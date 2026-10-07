import SwiftUI

/// An ⓘ that opens an `InfoSheet` explaining `title`.
struct InfoButton: View {
    let title: String
    let message: String

    @State private var isPresented = false

    var body: some View {
        Button("About \(title)", systemImage: "info.circle") { isPresented = true }
            .labelStyle(.iconOnly)
            .foregroundStyle(.secondary)
            .buttonStyle(.borderless)
            .infoSheet(isPresented: $isPresented, title: title, message: message)
    }
}

extension View {
    /// Presents an `InfoSheet`, for triggers other than an `InfoButton`.
    func infoSheet(isPresented: Binding<Bool>, title: String, message: String) -> some View {
        sheet(isPresented: isPresented) {
            InfoSheet(title: title, message: message)
        }
    }
}

/// A short explanation, a few sentences at most. X, OK, a tap outside or a swipe down closes it.
struct InfoSheet: View {
    let title: String
    let message: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        PopUp(title, systemImage: "info.circle") {
            Text(message)
                .font(.mono(.subheadline))
                .fixedSize(horizontal: false, vertical: true)
            Button("OK") { dismiss() }
                .buttonStyle(.primary)
                .padding(.top, 4)
        }
    }
}

/// The app's pop-up: content in a sheet sized to fit it, under a title and an X. The X, a tap
/// outside or a swipe down closes it. Present it as a sheet's content.
struct PopUp<Content: View>: View {
    let title: String
    let systemImage: String?
    let content: Content

    @Environment(\.dismiss) private var dismiss
    @State private var height: CGFloat = 240

    init(_ title: String, systemImage: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                Group {
                    if let systemImage {
                        Label(title, systemImage: systemImage)
                    } else {
                        Text(title)
                    }
                }
                .font(.mono(.title3, weight: .bold))
                Spacer()
                CloseButton { dismiss() }
            }
            content
        }
        // Concrete black or white, whatever style the presenting view set.
        .foregroundStyle(Color.primary)
        .padding(24)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .presentationDetents([.height(height)])
    }
}

/// An X like the system's: Liquid Glass on iOS 26 and later, a plain symbol before, as toolbar
/// buttons are.
private struct CloseButton: View {
    let action: () -> Void

    var body: some View {
        if #available(iOS 26, *) {
            button.buttonStyle(.glass).buttonBorderShape(.circle)
        } else {
            button.buttonStyle(.borderless)
        }
    }

    private var button: some View {
        Button("Close", systemImage: "xmark", action: action)
            .labelStyle(.iconOnly)
    }
}

import SwiftUI

/// How a full-screen flow such as Create Wallet closes. Whatever presents the flow sets it.
struct FlowExit {
    /// Opened from a pop-up such as Manage, Back returns to it.
    var returnsToPopUp = false
    /// Closes the flow, and the pop-up it was opened from, back to the screen underneath. Flows call
    /// it when they finish, too.
    var close: @MainActor () -> Void = {}
}

extension EnvironmentValues {
    @Entry var flowExit = FlowExit()
}

extension View {
    /// Back, when the flow came from a pop-up, and X. Flows are full-screen covers, so a swipe or a
    /// stray tap can't close one and lose what's been typed; these are the only ways out.
    func flowToolbar() -> some View {
        modifier(FlowToolbar())
    }
}

private struct FlowToolbar: ViewModifier {
    @Environment(\.flowExit) private var exit
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content.toolbar {
            if exit.returnsToPopUp {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Back", systemImage: "chevron.backward") { dismiss() }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Close", systemImage: "xmark") { exit.close() }
            }
        }
    }
}

import SwiftUI

extension FocusedValues {
    /// The reader window's binding, available even when the inspector is
    /// collapsed or a different control in that window has focus.
    @Entry var isContextPresented: Binding<Bool>?
}

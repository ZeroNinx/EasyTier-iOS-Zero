import SwiftUI

struct LabeledContent<Content: View>: View {
    private let label: LocalizedStringKey
    private let content: Content

    init(_ label: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            content
                .multilineTextAlignment(.trailing)
        }
    }
}

extension LabeledContent where Content == Text {
    init<S: StringProtocol>(_ label: LocalizedStringKey, value: S) {
        self.init(label) {
            Text(String(value))
        }
    }
}

#if os(iOS)
    #if compiler(>=5.9)
        let ToolbarLeading = ToolbarItemPlacement.topBarLeading
        let ToolbarTrailing = ToolbarItemPlacement.topBarTrailing
    #else
        let ToolbarLeading = ToolbarItemPlacement.navigationBarLeading
        let ToolbarTrailing = ToolbarItemPlacement.navigationBarTrailing
    #endif
#else
    let ToolbarLeading = ToolbarItemPlacement.navigation
    let ToolbarTrailing = ToolbarItemPlacement.primaryAction
#endif

extension View {
    func decimalKeyboardType() -> some View {
#if os(iOS)
        return self.keyboardType(.decimalPad)
#else
        return self
#endif
    }
    
    func numberKeyboardType() -> some View {
#if os(iOS)
        return self.keyboardType(.numberPad)
#else
        return self
#endif
    }
    
    func adaptiveNavigationBarTitleInline() -> some View {
#if os(iOS)
        return self.navigationBarTitleDisplayMode(.inline)
#else
        return self
#endif
    }
    
    func adaptiveNoTextInputAutocapitalization() -> some View {
#if os(iOS)
        return self.textInputAutocapitalization(.never)
#else
        return self
#endif
    }

    @ViewBuilder
    func adaptiveScrollDismissesKeyboardImmediately() -> some View {
#if os(iOS)
        if #available(iOS 16.0, *) {
            self.scrollDismissesKeyboard(.immediately)
        } else {
            self
        }
#else
        self
#endif
    }

    @ViewBuilder
    func adaptiveGroupedFormStyle() -> some View {
#if os(iOS)
        if #available(iOS 16.0, *) {
            self.formStyle(.grouped)
        } else {
            self
        }
#else
        self.formStyle(.grouped)
#endif
    }
}

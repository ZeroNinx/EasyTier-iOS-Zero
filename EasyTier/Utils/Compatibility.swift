import SwiftUI

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
}

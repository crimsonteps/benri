import AppKit
import SwiftUI

private struct QuickVaultGlassModifier: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if reduceTransparency {
            content
                .background(Color(nsColor: .windowBackgroundColor), in: shape)
                .overlay {
                    shape.stroke(Color.primary.opacity(0.12), lineWidth: 1)
                }
        } else if #available(macOS 26.0, *) {
            let tint = colorScheme == .dark
                ? Color(red: 0.05, green: 0.06, blue: 0.08).opacity(0.72)
                : Color(red: 0.95, green: 0.97, blue: 0.99).opacity(0.45)
            content.glassEffect(
                .regular.tint(tint),
                in: .rect(cornerRadius: cornerRadius)
            )
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay {
                    shape.stroke(Color.primary.opacity(0.12), lineWidth: 1)
                }
        }
    }
}

extension View {
    func quickVaultGlass(cornerRadius: CGFloat) -> some View {
        modifier(QuickVaultGlassModifier(cornerRadius: cornerRadius))
    }
}

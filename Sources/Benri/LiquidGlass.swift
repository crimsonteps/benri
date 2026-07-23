import AppKit
import SwiftUI

private struct BenriGlassModifier: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if reduceTransparency {
            content
                .background(Color(nsColor: .windowBackgroundColor), in: shape)
                .overlay {
                    shape.stroke(Color.primary.opacity(0.12), lineWidth: 1)
                }
        } else {
#if canImport(SwiftUI, _version: 7.0)
            if #available(macOS 26.0, *) {
                content.glassEffect(
                    .regular,
                    in: .rect(cornerRadius: cornerRadius)
                )
            } else {
                content
                    .background(.ultraThinMaterial, in: shape)
                    .overlay {
                        shape.stroke(Color.primary.opacity(0.12), lineWidth: 1)
                    }
            }
#else
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay {
                    shape.stroke(Color.primary.opacity(0.12), lineWidth: 1)
                }
#endif
        }
    }
}

extension View {
    func benriGlass(cornerRadius: CGFloat) -> some View {
        modifier(BenriGlassModifier(cornerRadius: cornerRadius))
    }
}

import AppKit
import SwiftUI

private struct BenriVisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = false
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
    }
}

private struct BenriPaletteSurfaceModifier: ViewModifier {
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
                    shape.stroke(
                        BenriTheme.Colors.border(for: colorScheme),
                        lineWidth: 1
                    )
                }
                .clipShape(shape)
                .shadow(color: .black.opacity(0.10), radius: 8, y: 3)
        } else {
            content
                .background(BenriTheme.Colors.panelTint(for: colorScheme), in: shape)
                .background {
                    BenriVisualEffectView(
                        material: colorScheme == .dark ? .hudWindow : .popover
                    )
                    .clipShape(shape)
                }
                .overlay {
                    shape.stroke(
                        BenriTheme.Colors.border(for: colorScheme),
                        lineWidth: 1
                    )
                }
                .clipShape(shape)
                .shadow(
                    color: .black.opacity(colorScheme == .dark ? 0.20 : 0.10),
                    radius: 8,
                    y: 3
                )
        }
    }
}

private struct BenriFloatingSurfaceModifier<S: Shape>: ViewModifier {
    let shape: S

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(Color(nsColor: .controlBackgroundColor), in: shape)
                .overlay {
                    shape.stroke(
                        BenriTheme.Colors.border(for: colorScheme),
                        lineWidth: 1
                    )
                }
        } else {
#if canImport(SwiftUI, _version: 7.0)
            if #available(macOS 26.0, *) {
                content
                    .glassEffect(
                        .regular.interactive().tint(Color.white.opacity(0.04)),
                        in: shape
                    )
                    .tint(.clear)
            } else {
                content.background(.ultraThinMaterial, in: shape)
            }
#else
            content.background(.ultraThinMaterial, in: shape)
#endif
        }
    }
}

private struct BenriFloatingCircleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(
                width: BenriTheme.Size.floatingButton,
                height: BenriTheme.Size.floatingButton
            )
            .contentShape(Circle())
    }
}

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
    func benriPaletteSurface(cornerRadius: CGFloat) -> some View {
        modifier(BenriPaletteSurfaceModifier(cornerRadius: cornerRadius))
    }

    func benriCommandSurface(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .background(Color.black.opacity(0.40), in: shape)
            .background {
                BenriVisualEffectView(material: .hudWindow)
                    .clipShape(shape)
            }
            .overlay {
                shape.stroke(Color.white.opacity(0.12), lineWidth: 1)
            }
            .clipShape(shape)
    }

    func benriGlass(cornerRadius: CGFloat) -> some View {
        modifier(BenriGlassModifier(cornerRadius: cornerRadius))
    }

    func benriFloatingSurface<S: Shape>(in shape: S) -> some View {
        modifier(BenriFloatingSurfaceModifier(shape: shape))
    }

    func benriFloatingCircleButton() -> some View {
        self
            .buttonStyle(BenriFloatingCircleButtonStyle())
            .modifier(BenriFloatingSurfaceModifier(shape: Circle()))
    }

    @ViewBuilder
    func benriSheetBackground() -> some View {
        if #available(macOS 13.3, *) {
            presentationBackground(.clear)
        } else {
            self
        }
    }
}

import AppKit
import BenriCore
import SwiftUI

struct ClipboardPaletteView: View {
    @ObservedObject var store: ClipboardStore
    @ObservedObject var state: PaletteState
    let onPaste: (ClipboardItem) -> Void
    let onActions: (ClipboardItem) -> Void

    private var results: [ClipboardItem] {
        state.clipboardResults(in: store)
    }

    var body: some View {
        HStack(spacing: 0) {
            clipboardList
                .frame(width: 330)

            Rectangle()
                .fill(Color.primary.opacity(0.10))
                .frame(width: 1)
                .padding(.vertical, 10)

            ClipboardPreview(
                item: state.selectedClipboardItem(in: store),
                imageURL: state.selectedClipboardItem(in: store).flatMap(store.imageURL)
            )
        }
        .onAppear { state.ensureClipboardSelection(in: store) }
        .onChange(of: state.clipboardQuery) { _ in state.ensureClipboardSelection(in: store) }
        .onReceive(store.$items) { _ in state.ensureClipboardSelection(in: store) }
    }

    private var clipboardList: some View {
        Group {
            if results.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 28, weight: .light))
                    Text(state.clipboardQuery.isEmpty ? "剪贴板历史为空" : "没有匹配内容")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(Color.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 3) {
                            ForEach(results) { item in
                                ClipboardRow(
                                    item: item,
                                    imageURL: store.imageURL(for: item),
                                    selected: item.id == state.selectedClipboardID
                                )
                                .id(item.id)
                                .contentShape(Rectangle())
                                .onTapGesture { state.selectedClipboardID = item.id }
                                .simultaneousGesture(
                                    TapGesture(count: 2).onEnded {
                                        state.selectedClipboardID = item.id
                                        onPaste(item)
                                    }
                                )
                                .background {
                                    RightClickAction {
                                        state.selectedClipboardID = item.id
                                        onActions(item)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .onChange(of: state.selectedClipboardID) { id in
                        guard let id else { return }
                        withAnimation(.easeOut(duration: 0.12)) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
            }
        }
    }
}

private struct ClipboardRow: View {
    let item: ClipboardItem
    let imageURL: URL?
    let selected: Bool
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 11) {
            thumbnail
            Text(preview)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.88))
                .lineLimit(1)
            Spacer(minLength: 0)
            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.secondary)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 48)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    selected
                        ? Color.primary.opacity(0.16)
                        : hovering ? Color.primary.opacity(0.07) : Color.clear
                )
        )
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var preview: String {
        item.kind == .image
            ? "图片"
            : String((item.text ?? "").prefix(200))
                .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if item.kind == .image,
           let imageURL,
           let image = NSImage(contentsOf: imageURL) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.10))
                .frame(width: 32, height: 32)
                .overlay {
                    Image(systemName: item.kind == .image ? "photo" : "doc.text")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.secondary)
                }
        }
    }
}

private struct ClipboardPreview: View {
    let item: ClipboardItem?
    let imageURL: URL?

    var body: some View {
        if let item {
            VStack(alignment: .leading, spacing: 0) {
                preview(item)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                information(item)
                    .padding(.horizontal, 22)
                    .padding(.bottom, 18)
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 30, weight: .light))
                Text("选择一条历史记录以预览")
            }
            .foregroundStyle(Color.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func preview(_ item: ClipboardItem) -> some View {
        if item.kind == .text {
            ScrollView(.vertical, showsIndicators: false) {
                Text(item.text ?? "")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Color.primary.opacity(0.86))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(22)
            }
        } else if let imageURL, let image = NSImage(contentsOf: imageURL) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(22)
        } else {
            Image(systemName: "photo")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Color.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func information(_ item: ClipboardItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("信息")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.secondary)
            infoRow("来源", sourceName(item.sourceBundleID))
            infoRow("类型", item.kind == .image ? "图片" : "文本")
            if let text = item.text {
                infoRow("字符", text.count.formatted())
                infoRow("单词", text.split(whereSeparator: { $0.isWhitespace }).count.formatted())
            } else if let imageURL,
                      let size = imagePixelSize(at: imageURL) {
                infoRow("尺寸", "\(Int(size.width)) × \(Int(size.height))")
            }
            infoRow("复制时间", item.createdAt.formatted(date: .abbreviated, time: .standard))
        }
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(Color.secondary)
            Spacer()
            Text(value)
                .foregroundStyle(Color.primary.opacity(0.78))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.system(size: 11))
        .padding(.vertical, 3)
    }

    private func sourceName(_ bundleID: String?) -> String {
        guard let bundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return "未知" }
        return url.deletingPathExtension().lastPathComponent
    }

    private func imagePixelSize(at url: URL) -> NSSize? {
        guard let data = try? Data(contentsOf: url),
              let representation = NSBitmapImageRep(data: data)
        else { return nil }
        return NSSize(
            width: representation.pixelsWide,
            height: representation.pixelsHigh
        )
    }
}

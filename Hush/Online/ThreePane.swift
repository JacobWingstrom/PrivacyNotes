import SwiftUI

/// Thunderbird-style layout: sidebar | list | reading pane, for wide screens (iPad).
struct ThreePane<Sidebar: View, ListPane: View, Reader: View>: View {
    var sidebarWidth: CGFloat = 260
    var listWidth: CGFloat = 360
    @ViewBuilder var sidebar: Sidebar
    @ViewBuilder var list: ListPane
    @ViewBuilder var reader: Reader
    @Environment(\.palette) private var palette
    @AppStorage("threePaneSidebar") private var showSidebar = true

    var body: some View {
        HStack(spacing: 0) {
            if showSidebar {
                sidebar
                    .frame(width: sidebarWidth)
                    .background(palette.surface)
                    .transition(.move(edge: .leading))
                Rectangle().fill(palette.border).frame(width: 1)
            }
            list
                .frame(width: listWidth)
            Rectangle().fill(palette.border).frame(width: 1)
            reader
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation(.snappy) { showSidebar.toggle() }
                } label: { Image(systemName: "sidebar.left") }
                .accessibilityLabel(showSidebar ? "Hide folders" : "Show folders")
            }
        }
    }
}

/// Placeholder for an empty reading pane.
struct PaneEmpty: View {
    let symbol: String
    let text: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 40, weight: .light)).foregroundStyle(.tertiary)
            Text(text).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A sidebar row with an icon, name and count (folders, feeds).
struct PaneRow: View {
    let symbol: String
    let title: String
    var count: Int = 0
    var indent: Int = 0
    var selected = false
    var bold = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(.tint).frame(width: 22)
            Text(title).lineLimit(1).fontWeight(selected || bold ? .semibold : .regular)
            Spacer(minLength: 4)
            if count > 0 {
                Text("\(count)").font(.hush(.footnote).weight(.medium)).monospacedDigit().foregroundStyle(.secondary)
            }
        }
        .padding(.leading, CGFloat(indent) * 14)
        .padding(.vertical, 7)
        .padding(.horizontal, 10)
        .background {
            if selected { RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.tint.opacity(0.18)) }
        }
        .contentShape(Rectangle())
    }
}

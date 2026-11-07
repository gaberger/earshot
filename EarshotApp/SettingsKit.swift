// Small SwiftUI building blocks for Earshot's settings: cards with rows, a warning banner, a key chip.
// Pure SwiftUI + AppKit colors; no app dependencies.
import SwiftUI
import AppKit

struct SettingsSection<Content: View>: View {
    let title: String
    let content: Content
    let dimmed: Bool

    init(_ title: String, dimmed: Bool = false, @ViewBuilder content: () -> Content) {
        self.title = title
        self.dimmed = dimmed
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            VStack(spacing: 0) {
                Group(subviews: content) { subviews in
                    ForEach(subviews: subviews) { subview in
                        subview
                        if subview.id != subviews.last?.id {
                            Divider()
                        }
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .opacity(dimmed ? 0.65 : 1)
            .disabled(dimmed)
        }
    }
}

struct SettingsRow<Trailing: View>: View {
    let title: String
    let detail: String?
    let trailing: Trailing

    init(_ title: String, detail: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.detail = detail
        self.trailing = trailing()
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body.weight(.semibold))
                if let detail {
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 16)
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

struct SettingsBanner: View {
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?

    init(_ message: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    private func actionButton(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .controlSize(.small)
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                Text(message)
                    .lineLimit(1)
                Spacer(minLength: 16)
                if let actionTitle, let action {
                    actionButton(actionTitle, action)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                    Text(message)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let actionTitle, let action {
                    actionButton(actionTitle, action)
                }
            }
        }
        .foregroundStyle(Color.orange)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12))
    }
}

struct KeyChip: View {
    let text: String
    let onRemove: (() -> Void)?

    init(_ text: String, onRemove: (() -> Void)? = nil) {
        self.text = text
        self.onRemove = onRemove
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(text).font(.body.weight(.semibold))
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark").font(.caption)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }
}

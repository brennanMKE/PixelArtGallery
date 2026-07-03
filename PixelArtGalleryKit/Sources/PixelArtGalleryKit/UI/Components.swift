import SwiftUI

/// A section header: a headline title with an optional trailing action.
struct SectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    init(_ title: String, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack {
            Text(title)
                .font(.headline)
            Spacer()
            trailing()
        }
    }
}

/// A success/error status banner (icon + title + message on a tinted card).
/// Replaces the copy-pasted banners in the variant/export screens.
struct StatusBanner: View {
    enum Kind {
        case success
        case error

        var color: Color { self == .success ? .green : .red }
        var icon: String { self == .success ? "checkmark.circle.fill" : "exclamationmark.circle.fill" }
        var title: String { self == .success ? "Success" : "Error" }
    }

    let kind: Kind
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: kind.icon)
                    .foregroundStyle(kind.color)
                Text(kind.title)
                    .fontWeight(.semibold)
            }
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.m)
        .background(
            kind.color.opacity(0.12),
            in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
        )
        .transition(.opacity)
    }
}

/// A centered empty state: icon, title, message, and an optional primary CTA.
/// Unifies the previously divergent empty states across the app.
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionLabel: String? = nil
    var action: (() -> Void)? = nil
    /// When true, show the lively animated pixel block instead of the SF Symbol —
    /// used for prominent first-run empty states.
    var animatedHero: Bool = false

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            if animatedHero {
                AnimatedPixelsView(size: 132)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: Theme.Spacing.xs) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let actionLabel, let action {
                Button(actionLabel, action: action)
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.xl)
    }
}

/// An informational row: a tinted SF Symbol + caption text (form hints, etc.).
struct InfoRow: View {
    let icon: String
    let text: String

    init(_ text: String, icon: String = "info.circle.fill") {
        self.text = text
        self.icon = icon
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
            Image(systemName: icon)
                .foregroundStyle(.tint)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

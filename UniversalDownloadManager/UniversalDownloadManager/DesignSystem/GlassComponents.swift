import SwiftUI

/// Reusable Liquid Glass-styled components using iOS 27 `glassEffect` APIs.
struct GlassCard<Content: View>: View {
    let cornerRadius: CGFloat
    let padding: CGFloat
    let tint: Color?
    let content: Content
    
    init(
        cornerRadius: CGFloat = AppTheme.cornerRadius,
        padding: CGFloat = AppTheme.cardPadding,
        tint: Color? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.tint = tint
        self.content = content()
    }
    
    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(
                tint != nil ? .regular.tint(tint) : .regular,
                in: .rect(cornerRadius: cornerRadius)
            )
    }
}

/// A compact glass badge showing status or tags.
struct GlassBadge: View {
    let title: String
    let iconName: String?
    let color: Color
    
    init(_ title: String, iconName: String? = nil, color: Color = .blue) {
        self.title = title
        self.iconName = iconName
        self.color = color
    }
    
    var body: some View {
        HStack(spacing: 4) {
            if let iconName {
                Image(systemName: iconName)
                    .font(.caption2.bold())
            }
            Text(title)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .glassEffect(.clear.tint(color.opacity(0.15)), in: .capsule)
    }
}

/// A metric summary card used on dashboards.
struct GlassMetricCard: View {
    let title: String
    let value: String
    let iconName: String
    let color: Color
    var subtitle: String? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: iconName)
                    .font(.caption)
                    .foregroundStyle(color)
                Spacer()
                Text(value)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
            }
            
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(color.opacity(0.08)), in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }
}

/// A prominent or standard glass button.
struct GlassActionButton: View {
    let title: String
    let systemImage: String
    let color: Color
    let isProminent: Bool
    let action: () -> Void
    
    init(
        _ title: String,
        systemImage: String,
        color: Color = AppTheme.accentColor,
        isProminent: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.color = color
        self.isProminent = isProminent
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                Text(title)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isProminent ? .white : color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .if(isProminent) { view in
            view.buttonStyle(.glassProminent)
        }
        .if(!isProminent) { view in
            view.buttonStyle(.glass)
        }
        .accessibilityLabel(title)
    }
}

/// A glass-styled floating action button.
struct GlassFloatingButton: View {
    let systemImage: String
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.headline)
                Text(title)
                    .font(.headline)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(.glassProminent)
        .accessibilityLabel(title)
    }
}

/// A glass-styled section header that stays within screen margins.
struct GlassSectionHeader: View {
    let title: String
    let count: Int?
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    
    init(_ title: String, count: Int? = nil, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.count = count
        self.actionTitle = actionTitle
        self.action = action
    }
    
    var body: some View {
        HStack {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)
            
            if let count {
                Text("\(count)")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: .capsule)
            }
            
            Spacer()
            
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.accentColor)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Custom empty state view with glass styling.
struct GlassEmptyState: View {
    let title: String
    let message: String
    let systemImage: String
    var buttonTitle: String? = nil
    var action: (() -> Void)? = nil
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
                .padding(20)
                .glassEffect(.regular, in: .circle)
            
            VStack(spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            
            if let buttonTitle, let action {
                Button(buttonTitle, action: action)
                    .buttonStyle(.glass)
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - View Extension Helper

extension View {
    @ViewBuilder
    func `if`<Transform: View>(_ condition: Bool, transform: (Self) -> Transform) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

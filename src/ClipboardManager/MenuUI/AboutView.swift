//
//  AboutView.swift
//  ClipboardManager
//
//  SwiftUI About window: icon, name, version, author.
//

import SwiftUI

/// The contents of the About window.
struct AboutView: View {

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.tint)
                .padding(.top, 8)

            Text(AppInfo.name)
                .font(.title2.weight(.semibold))

            Text(AppInfo.versionDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("Clipboard history right in your menu bar.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            Text("Text & images • Favorites • Quick paste")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Divider()
                .padding(.horizontal, 40)

            Text(AppInfo.author)
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(width: 300, height: 300)
    }
}

#if DEBUG
#Preview {
    AboutView()
}
#endif
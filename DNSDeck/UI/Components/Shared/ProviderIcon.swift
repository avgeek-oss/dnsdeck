import SwiftUI

struct ProviderIcon: View {
    let provider: DNSProvider
    var size: CGFloat = 20

    var body: some View {
        Group {
            if let imageAssetName = provider.imageAssetName {
                Image(imageAssetName)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: provider.symbolName)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
                    .padding(2)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

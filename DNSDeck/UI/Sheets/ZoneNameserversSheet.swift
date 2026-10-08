#if os(macOS)
import AppKit
#else
import UIKit
#endif
import SwiftUI

struct ZoneNameserversSheet: View {
    @Environment(\.dismiss) private var dismiss

    let zoneName: String
    let nameservers: [String]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(
                    "The zone has been added. To complete the activation, you would need to copy the name servers and add it to your domain provider."
                )
                .foregroundStyle(.secondary)

                nameserversTable

                Spacer()
            }
            .padding(20)
            .frame(minWidth: 620, minHeight: 360)
            .navigationTitle("Complete Zone Activation")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                    .accessibilityIdentifier("zone.nameservers.close")
                }

                ToolbarItem(placement: .primaryAction) {
                    Button("Copy All") {
                        copyToClipboard(nameservers.joined(separator: "\n"))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var nameserversTable: some View {
        #if os(macOS)
        Table(nameserversRows) {
            TableColumn("Zone") { _ in
                Text(zoneName)
                    .textSelection(.enabled)
            }
            .width(min: 180, ideal: 220)

            TableColumn("Nameserver") { row in
                Text(row.value)
                    .textSelection(.enabled)
            }
            .width(min: 260, ideal: 320)

            TableColumn("") { row in
                Button("Copy") {
                    copyToClipboard(row.value)
                }
                .buttonStyle(.borderless)
            }
            .width(min: 70, ideal: 80, max: 90)
        }
        .frame(minHeight: 220)
        #else
        List(nameserversRows) { row in
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(zoneName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(row.value)
                        .textSelection(.enabled)
                }

                Spacer()

                Button("Copy") {
                    copyToClipboard(row.value)
                }
            }
        }
        #endif
    }

    private var nameserversRows: [NameserverRow] {
        nameservers.map { NameserverRow(value: $0) }
    }

    private func copyToClipboard(_ value: String) {
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
        #else
        UIPasteboard.general.string = value
        #endif
    }
}

private struct NameserverRow: Identifiable {
    let id = UUID()
    let value: String
}

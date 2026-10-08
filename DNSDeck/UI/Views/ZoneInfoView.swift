import SwiftUI

struct ZoneInfoView: View {
    @EnvironmentObject private var model: AppModel
    let zone: ProviderZone

    private static let timestampKeys: Set = [
        "boughtAt", "configVerifiedAt", "expiresAt", "nsVerifiedAt", "transferredAt", "txtVerifiedAt",
    ]
    private static let labels = [
        "autoRenew": "Auto-Renew",
        "cdnEnabled": "CDN Enabled",
        "configVerifiedAt": "Config Verified",
        "creatorEmail": "Creator Email",
        "creatorName": "Creator Name",
        "creatorUsername": "Creator Username",
        "intendedNameservers": "Intended Nameservers",
        "nsVerifiedAt": "NS Verified",
        "recordCount": "Resource Record Sets",
        "serviceType": "Service Type",
        "teamId": "Team ID",
        "txtVerifiedAt": "TXT Verified",
        "userId": "User ID",
    ]
    private static let year2000 = Date(timeIntervalSince1970: 946_684_800)
    private static let year2100 = Date(timeIntervalSince1970: 4_102_444_800)

    private var resolvedZone: ProviderZone {
        guard let selected = model.selectedZone, selected.id == zone.id else { return zone }
        return selected
    }

    private var snapshot: ProviderZoneSnapshot {
        resolvedZone.zoneData.snapshot
    }

    var body: some View {
        List {
            Section("Basic Information") {
                detail("Zone Name", snapshot.name)
                detail("Zone ID", snapshot.id)
                if let status = snapshot.status {
                    detail("Status", status.capitalized)
                }
                if let createdOn = snapshot.createdOn {
                    detail("Created", createdOn.formatted(date: .abbreviated, time: .shortened))
                }
            }

            if !snapshot.nameservers.isEmpty {
                Section("Nameservers") {
                    detail("Name Servers", snapshot.nameservers.joined(separator: "\n"))
                }
            }

            if !snapshot.metadata.isEmpty {
                Section("Provider Details") {
                    ForEach(snapshot.metadata.keys.sorted(), id: \.self) { key in
                        detail(
                            Self.labels[key] ?? key.capitalizedWords,
                            displayValue(snapshot.metadata[key] ?? "", for: key)
                        )
                    }
                }
            }
        }
        .listStyle(.automatic)
        .accessibilityIdentifier("zone.info")
        .task(id: zone.id) {
            await model.refreshZoneDetailsIfNeeded(for: zone)
        }
    }

    private func detail(_ label: String, _ value: String) -> some View {
        LabeledContent(label) {
            Text(value)
                .textSelection(.enabled)
        }
    }

    private func displayValue(_ value: String, for key: String) -> String {
        if Self.timestampKeys.contains(key), let timestamp = Double(value) {
            return formatted(milliseconds: timestamp)
        }
        if key == "creationTime", let date = DateFormatter.iso8601.date(from: value) {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
        if key == "privateZone" {
            return value == "true" ? "Private" : "Public"
        }
        if value == "true" || value == "false" {
            return value == "true" ? "Yes" : "No"
        }
        if key == "serviceType" || key == "visibility" {
            return value.capitalized
        }
        return value
    }

    private func formatted(milliseconds: Double) -> String {
        let date = Date(timeIntervalSince1970: milliseconds / 1000)
        guard date >= Self.year2000, date <= Self.year2100 else { return "Unknown" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

#Preview {
    NavigationStack {
        ZoneInfoView(
            zone: ProviderZone(
                provider: .vercel,
                snapshot: ProviderZoneSnapshot(
                    id: "test-id",
                    name: "example.com",
                    nameservers: ["ns1.example.com", "ns2.example.com"],
                    status: "verified",
                    createdOn: .now,
                    metadata: ["serviceType": "external", "autoRenew": "true"]
                ),
                environmentId: UUID()
            )
        )
        .environmentObject(AppModel(lockController: AppLockController()))
    }
}

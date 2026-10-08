import SwiftUI

struct TypeBadge: View {
    let type: String
    var filled: Bool?

    var body: some View {
        BadgeView(recordType: type, filled: filled)
    }
}

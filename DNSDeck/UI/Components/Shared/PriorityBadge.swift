import SwiftUI

struct PriorityBadge: View {
    let priority: Int?

    var body: some View {
        BadgeView(priority: priority)
    }
}

import SwiftUI

/// Top of the Account tab: profile photo (or the name's first letter),
/// name, email and role.
struct AccountProfileHeader: View {
    let user: User
    let photo: Data?
    let roleLabel: LocalizedStringKey

    var body: some View {
        Section {
            HStack(spacing: Theme.Spacing.l) {
                ZStack {
                    Circle()
                        .fill(Theme.brandFill)
                    if let photo, let image = UIImage(data: photo) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .clipShape(Circle())
                            .accessibilityLabel("Profilfoto")
                    } else {
                        Text(user.displayName.prefix(1).uppercased())
                            .font(.title)
                            .bold()
                            .foregroundStyle(.white)
                            // Decorative: the name follows.
                            .accessibilityHidden(true)
                    }
                }
                .frame(width: 70, height: 70)

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(user.displayName)
                        .font(.title3)
                        .bold()
                    Text(user.email)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TagLabel(roleLabel)
                }
            }
            .padding(.vertical, Theme.Spacing.s)
        }
    }
}

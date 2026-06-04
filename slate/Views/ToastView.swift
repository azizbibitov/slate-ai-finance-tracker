import SwiftUI

struct ToastView: View {
    let message: ToastMessage

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(message.isError ? Color.red : Color.brand)
                .frame(width: 7, height: 7)
            Text(message.text)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.08), radius: 16, x: 0, y: 4)
        .padding(.top, 4)
    }
}

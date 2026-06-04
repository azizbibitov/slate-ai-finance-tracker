import SwiftUI

struct ToastView: View {
    let message: ToastMessage

    var body: some View {
        Text(message.text)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(message.isError ? Color.red : Color.black.opacity(0.85), in: Capsule())
            .padding(.top, 8)
    }
}

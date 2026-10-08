import SwiftUI

/// The greeting window. "Start" opens the immersive space and closes this window.
struct WelcomeView: View {

    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var isOpening = false

    var body: some View {
        VStack(alignment: .center, spacing: 32) {
            VStack(alignment: .center, spacing: 16) {
                Text("Bark beetles")
                    .font(.system(size: 42, weight: .semibold, design: .serif))

                Text("Barely five millimetres long, yet able to destroy whole stands of spruce. They bore under the bark, where they feed, breed and cut the tree's supply lines.")
                    .font(.title3)

                Text("Pinch a layer of the log and pull it aside to see what lies beneath. Then tap any layer to dive deeper.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Button {
                guard !isOpening else { return }
                isOpening = true
                Task {
                    switch await openImmersiveSpace(id: AppConfig.immersiveSpaceID) {
                    case .opened:
                        dismissWindow(id: AppConfig.welcomeWindowID)
                    default:
                        isOpening = false
                    }
                }
            } label: {
                Text("Start")
                    .font(.title2.weight(.semibold))
                    .padding(.horizontal, 28)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isOpening)
        }
        .multilineTextAlignment(.center)
        .padding(48)
        .frame(width: 700, alignment: .center)
        .background(Color(red: 0.05, green: 0.25, blue: 0.1, opacity: 0.7))
        .cornerRadius(24)
    }
}

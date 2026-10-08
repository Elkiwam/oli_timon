import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openImmersiveSpace) private var openSpace
    @Environment(\.dismissImmersiveSpace) private var dismissSpace

    var body: some View {
        VStack(spacing: 20) {
            Text("Der Borkenkäfer")
                .font(.extraLargeTitle2)

            ProgressView(value: Double(model.phase.rawValue), total: Double(Phase.allCases.count - 1))
                .padding(.horizontal)

            phaseContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            if let item = model.selected, model.phase != .review {
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title).font(.headline)
                    Text(item.info).font(.callout)
                }
                
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.thinMaterial, in: .rect(cornerRadius: 16))
            }

            // Available in every phase after the intro
            if model.phase != .intro {
                Button("Back to start", systemImage: "arrow.counterclockwise") {
                    Task { await backToStart() }
                }
            }
        }
        .padding(30)
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch model.phase {
        case .intro:
            VStack(spacing: 16) {
                Text("Explore the layers of a tree trunk and learn where the bark beetle attacks.")
                    .multilineTextAlignment(.center)
                Button("Start") {
                    Task { await start() }
                }
                .buttonStyle(.borderedProminent)
            }

        case .dissect:
            VStack(spacing: 12) {
                Text("Phase 1: Dissect").font(.title2)
                Text("Pinch and pull the layers off the trunk, outside to inside.")
                if let next = model.nextToDetach {
                    Text("Next: \(next.title)").bold()
                }
                Text("\(model.detached.count) / \(TrunkLayer.allCases.count) removed")
                    .foregroundStyle(.secondary)
            }

        case .arrange:
            VStack(spacing: 12) {
                Text("Phase 2: Arrange").font(.title2)
                Text("Bring each layer close to the table. It snaps into place on its own.")
                Text("\(model.placed.count) / \(TrunkLayer.allCases.count) placed")
                    .foregroundStyle(.secondary)
            }

        case .review:
            VStack(spacing: 12) {
                Text("Phase 3: Inspect").font(.title2)
                Text("Well done! Tap any model on the table. An enlarged version appears in front of you, together with an explanation.")
                    .multilineTextAlignment(.center)
                Text("Drag the enlarged model sideways to rotate it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let item = model.inspected {
                    Text("Now viewing: \(item.title)").bold()
                }
            }
        }
    }

    private func start() async {
        switch await openSpace(id: AppConfig.immersiveSpaceID) {
        case .opened:
            model.phase = .dissect
        case .userCancelled:
            print("⚠️ Immersive space: user cancelled")
        case .error:
            print("⚠️ Immersive space failed to open (check Info.plist: UIApplicationSupportsMultipleScenes = YES)")
        @unknown default:
            break
        }
    }

    private func backToStart() async {
        model.reset()
        await dismissSpace()
    }
}

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var vm = InputViewModel()
    var body: some View {
        @Bindable var vm = vm

        FeedView()
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                InputBarView()
            }
            .overlay(alignment: .top) {
                if let toast = vm.toast {
                    ToastView(message: toast)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.3), value: vm.toast)
            .sheet(isPresented: Binding(
                get: { vm.activeSheet != nil },
                set: { if !$0 { vm.activeSheet = nil } }
            )) {
                GlobalSheet()
            }
            .environment(vm)
            .task {
                SampleData.seedIfNeeded(modelContext)
                vm.setup(storage: SwiftDataStorageRepository(context: modelContext))
            }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Transaction.self, PendingInput.self, Account.self], inMemory: true)
}

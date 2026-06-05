import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var vm = InputViewModel()
    @State private var selectedTab: FeedTab = .expense
    @State private var selectedPeriod: FeedPeriod = .month

    var body: some View {
        @Bindable var vm = vm

        FeedView(tab: selectedTab, selectedTab: $selectedTab, selectedPeriod: $selectedPeriod)
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
            .sheet(item: $vm.queryResult) { result in
                ResultsSheet(result: result)
            }
            .sheet(isPresented: $vm.showAccounts) {
                AccountsSheet()
            }
            .environment(vm)
            .task { vm.setup(storage: SwiftDataStorageRepository(context: modelContext)) }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Transaction.self, PendingInput.self, Account.self], inMemory: true)
}

import SwiftUI
import SwiftData

struct GlobalSheet: View {
    @Namespace private var ns
    @Environment(\.dismiss) private var dismiss
    @Environment(InputViewModel.self) private var vm

    var body: some View {
        NavigationStack {
            ZStack {
                if case .accounts = vm.activeSheet {
                    AccountsContent()
                        .matchedGeometryEffect(id: "content", in: ns)
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                }
                if case .results(let result) = vm.activeSheet {
                    ResultsSheet(result: result)
                        .matchedGeometryEffect(id: "content", in: ns)
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                }
            }
            .animation(.spring(duration: 0.42, bounce: 0.15), value: vm.activeSheet?.id)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .font(.system(.headline, design: .rounded))
                        .contentTransition(.opacity)
                        .animation(.spring(duration: 0.3), value: title)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.brand)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                InputBarView()
            }
        }
    }

    private var title: String {
        switch vm.activeSheet {
        case .accounts:  return "Wallets"
        case .results:   return "Results"
        case nil:        return ""
        }
    }
}

// MARK: - Accounts content

private struct AccountsContent: View {
    @Query(filter: #Predicate<Account> { !$0.isArchived },
           sort: \Account.sortOrder) private var accounts: [Account]
    @Query private var transactions: [Transaction]
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        List {
            if accounts.isEmpty {
                Section {
                    emptyState
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            } else {
                Section {
                    ForEach(accounts) { account in
                        accountRow(account)
                            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                            .listRowSeparatorTint(Color(.separator).opacity(0.5))
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    account.isArchived = true
                                    try? modelContext.save()
                                } label: {
                                    Label("Archive", systemImage: "archivebox")
                                }
                            }
                    }
                } header: {
                    Text("WALLETS")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .listStyle(.plain)
    }

    private func accountRow(_ account: Account) -> some View {
        let bal = balance(for: account)
        return HStack(spacing: 14) {
            ZStack(alignment: .bottomTrailing) {
                Text(account.emoji)
                    .font(.system(size: 24))
                    .frame(width: 44, height: 44)
                    .background(account.isDefault ? Color.brandMuted : Color(.secondarySystemBackground),
                                in: Circle())
                if account.isDefault {
                    Circle()
                        .fill(Color.brand)
                        .frame(width: 12, height: 12)
                        .overlay(
                            Image(systemName: "checkmark")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(.white)
                        )
                        .offset(x: 2, y: 2)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(account.name)
                    .font(.body.weight(.medium))
                Text(account.currency)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if account.isDefault {
                Text("Active")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.brand)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.brandMuted, in: Capsule())
            }

            VStack(alignment: .trailing, spacing: 2) {
                Text(CurrencyFormatter.format(bal, showSign: bal < 0))
                    .font(.body.monospacedDigit().weight(.semibold))
                    .foregroundStyle(bal >= 0 ? Color.brand : Color.primary)
                Text(account.currency)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 10)
    }

    private func balance(for account: Account) -> Double {
        transactions
            .filter { $0.accountID == account.id }
            .reduce(0) { $0 + $1.amount }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "creditcard")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.brand.opacity(0.5))
            VStack(spacing: 5) {
                Text("No wallets yet")
                    .font(.system(.headline, design: .rounded))
                Text("Say \"I have a cash wallet with 5000 tmt\"")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}

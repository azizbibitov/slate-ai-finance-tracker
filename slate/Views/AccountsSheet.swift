import SwiftUI
import SwiftData

struct AccountsSheet: View {
    @Query(filter: #Predicate<Account> { !$0.isArchived },
           sort: \Account.sortOrder) private var accounts: [Account]
    @Query private var transactions: [Transaction]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
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
                                .contentShape(Rectangle())
                                .onTapGesture { setDefault(account) }
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

                Section {
                    hintRow
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                }
            }
            .listStyle(.plain)
            .navigationTitle("Wallets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.brand)
                }
            }
        }
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
                HStack(spacing: 6) {
                    Text(account.name)
                        .font(.body.weight(.medium))
                    if account.isDefault {
                        Text("Active")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.brand)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.brandMuted, in: Capsule())
                    }
                }
                Text(account.currency)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

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

    private func setDefault(_ account: Account) {
        guard !account.isDefault else { return }
        for a in accounts { a.isDefault = false }
        account.isDefault = true
        try? modelContext.save()
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

    private var hintRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.brand)
            Text("Tap a wallet to set it as active. All transactions go there by default.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

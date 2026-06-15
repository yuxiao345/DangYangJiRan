import SwiftUI
@preconcurrency import CoreData

struct TransactionDetailContent: View {
    let transaction: Transaction

    var body: some View {
        MacAddTransactionSheet(editing: transaction, displayMode: true)
    }
}

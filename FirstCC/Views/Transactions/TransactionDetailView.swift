import SwiftUI

struct TransactionDetailView: View {
    let transaction: Transaction

    var body: some View {
        AddEditTransactionView(editing: transaction, displayMode: true)
    }
}

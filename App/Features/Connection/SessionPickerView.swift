import SwiftUI

struct SessionPickerView: View {
    let choice: RemoteSessionChoice
    let creatableBackends: [SessionBackendKind]
    let onSelect: (RemoteSessionEntry?) -> Void
    let onCreate: (SessionBackendKind, String) -> Void
    let onCancel: () -> Void

    var body: some View {
        EmptyView()
    }
}

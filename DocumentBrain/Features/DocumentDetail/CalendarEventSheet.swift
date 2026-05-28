import SwiftUI
import EventKitUI
import EventKit

// MARK: - Native iOS calendar event editor sheet

struct CalendarEventSheet: UIViewControllerRepresentable {
    let event: EKEvent
    let store: EKEventStore
    @Binding var isPresented: Bool

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let vc = EKEventEditViewController()
        vc.eventStore = store
        vc.event = event
        vc.editViewDelegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: EKEventEditViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(isPresented: $isPresented) }

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        @Binding var isPresented: Bool
        init(isPresented: Binding<Bool>) { _isPresented = isPresented }

        func eventEditViewController(
            _ controller: EKEventEditViewController,
            didCompleteWith action: EKEventEditViewAction
        ) {
            isPresented = false
        }
    }
}

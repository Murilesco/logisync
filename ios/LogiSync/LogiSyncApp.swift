import SwiftUI

@main
struct LogiSyncApp: App {
    @StateObject private var sync = SyncManager()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                Form {
                    Section("Devices") {
                        TextField("Keyboard name contains", text: $sync.keyboardName)
                        TextField("Mouse name contains", text: $sync.mouseName)
                        Stepper("Send mouse to channel \(sync.targetChannel)", value: $sync.targetChannel, in: 1...3)
                    }
                    Section {
                        Button("Test: send the mouse now") { sync.moveMouse() }
                    }
                    Section("Log") {
                        ForEach(sync.log.indices, id: \.self) { Text(sync.log[$0]).font(.caption.monospaced()) }
                    }
                }
                .navigationTitle("LogiSync")
            }
        }
    }
}

import SwiftUI
import UIKit

struct ReminderInboxSetupView: View {
    @ObservedObject private var reminders = ReminderInbox.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection = ""
    @State private var working = false

    var body: some View {
        Form {
            Section {
                Text("Siri, remind me to change wheels on bicycle.").font(.headline)
                Text("Apple Reminders captures the idea. Dash copies it into your inbox when opened, while running, and during background refresh when iOS permits.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                if reminders.authorized {
                    Label("Reminders access allowed", systemImage: "checkmark.circle")
                } else if reminders.accessDenied {
                    Button("Allow access in iPhone Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                } else {
                    Button("Allow Reminders access") {
                        Task { await reminders.requestAccess() }
                    }.accessibilityIdentifier("reminders.allow")
                }
            } header: { Text("1. Allow Reminders access") } footer: {
                Text("Apple requires Full Access to read reminders. Dash reads items only from the list you connect. Imported reminders are never edited, completed, or deleted in Apple Reminders.")
            }
            if reminders.authorized {
                Section {
                    Button("Create Dash Inbox") {
                        Task {
                            working = true; defer { working = false }
                            await reminders.createAndConnect(); selection = reminders.selectedListID
                        }
                    }.disabled(working || reminders.isRefreshing).accessibilityIdentifier("reminders.create")
                    Picker("Or choose an existing list", selection: $selection) {
                        Text("Choose a list").tag("")
                        ForEach(reminders.lists) { Text($0.label).tag($0.id) }
                    }.accessibilityIdentifier("reminders.list")
                    Button("Connect selected list") {
                        Task { await reminders.connect(selection) }
                    }.disabled(selection.isEmpty || working || reminders.isRefreshing)
                        .accessibilityIdentifier("reminders.connect")
                } header: { Text("2. Connect a list") } footer: {
                    Text("Unfinished items already in this list will also be copied. Use an iCloud list so reminders captured on your Watch can reach your iPhone.")
                }
            }
            if reminders.enabled {
                Section {
                    LabeledContent("Connected list", value: reminders.selectedListName)
                    Text(reminders.status).accessibilityIdentifier("reminders.status")
                    if let date = reminders.lastImportAt {
                        Text("Last checked \(date.formatted(date: .abbreviated, time: .shortened))")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Button(reminders.isRefreshing ? "Importing…" : "Import now") {
                        Task { await reminders.refresh() }
                    }.disabled(reminders.isRefreshing).accessibilityIdentifier("reminders.import")
                    Button("Disconnect list", role: .destructive) { reminders.disconnect() }
                        .accessibilityIdentifier("reminders.disconnect")
                } header: { Text("Import status") } footer: {
                    Text("\(reminders.backgroundStatus) Watch-to-iPhone sync can add a delay. Ideas keep the reminder’s creation time when available. Deleting or completing an idea in Dash will not cause it to be copied again.")
                }
            } else {
                Text(reminders.status).font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("reminders.status")
            }
            Section {
                Text(defaultListInstructions)
                Text("Choose \(reminders.enabled ? reminders.selectedListName : "Dash Inbox") as the default list, then say: ‘Siri, remind me to…’")
                Text("Reminders without a specified list will now go there. You can still name another list in a Siri command.")
                    .font(.footnote).foregroundStyle(.secondary)
            } header: { Text("3. Set your default list") }
        }
        .navigationTitle("Siri via Reminders").navigationBarTitleDisplayMode(.inline)
        .task { reminders.reloadLists(); selection = reminders.selectedListID }
        .onChange(of: reminders.selectedListID) { _, id in selection = id }
        .onChange(of: scenePhase) { _, phase in if phase == .active { reminders.reloadLists() } }
    }

    private var defaultListInstructions: String {
        if #available(iOS 18.0, *) { return "On your iPhone, open Settings → Apps → Reminders → Default List." }
        return "On your iPhone, open Settings → Reminders → Default List."
    }
}

import AppKit
import SwiftUI
import SANIVACore

private enum AppSection: String, CaseIterable, Identifiable {
    case overview = "Overview", duplicates = "Duplicates", cleanup = "Safe Cleanup", apps = "Applications", settings = "Settings"
    var id: Self { self }
    var icon: String {
        switch self { case .overview: "chart.pie"; case .duplicates: "doc.on.doc"; case .cleanup: "sparkles"; case .apps: "app.dashed"; case .settings: "gearshape" }
    }
}

struct ContentView: View {
    @EnvironmentObject private var cleaner: StorageCleanerModel
    @State private var selection: AppSection? = .overview
    @State private var confirmingCleanup = false
    @State private var confirmingDuplicateTrash = false
    @State private var showingHelp = false
    @State private var appDropTargeted = false

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 8) {
                sanivaLogo.frame(height: 58).padding(.horizontal, 16).padding(.top, 14)
                List(AppSection.allCases, selection: $selection) { section in
                    Label(section.rawValue, systemImage: section.icon).tag(section)
                }.listStyle(.sidebar)
                Text("SANIVA 1.4").font(.caption2).foregroundStyle(.tertiary).padding(.bottom, 12)
            }.navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 240)
        } detail: {
            Group {
                switch selection ?? .overview {
                case .overview: overview
                case .duplicates: duplicates
                case .cleanup: cleanup
                case .apps: applications
                case .settings: settings
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar {
                ToolbarItemGroup {
                    Button { showingHelp = true } label: { Label("Help", systemImage: "questionmark.circle") }
                    Button { Task { await cleaner.refresh() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }.disabled(cleaner.isScanning)
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .alert("Clear selected items permanently?", isPresented: $confirmingCleanup) {
            Button("Cancel", role: .cancel) { }
            Button("Clear \(format(cleaner.selectedBytes))", role: .destructive) { Task { await cleaner.cleanSelected() } }
        } message: { Text("Trash and cache cleanup is permanent. Protected or in-use items are left alone.") }
        .alert("Move selected duplicates to Trash?", isPresented: $confirmingDuplicateTrash) {
            Button("Cancel", role: .cancel) { }
            Button("Move to Trash", role: .destructive) { Task { await cleaner.moveSelectedDuplicatesToTrash() } }
        } message: { Text("\(format(cleaner.duplicateSelectedBytes)) will be moved to macOS Trash and can be restored. One file is always kept in each duplicate set.") }
        .alert("Delete app bundle permanently?", isPresented: Binding(get: { cleaner.appRemovalRequest != nil }, set: { if !$0 { cleaner.appRemovalRequest = nil } })) {
            Button("Cancel", role: .cancel) { cleaner.appRemovalRequest = nil }
            Button("Delete permanently", role: .destructive) { Task { await cleaner.removeRequestedApps() } }
        } message: { Text("\(cleaner.appRemovalRequest?.names ?? "Selected app") will be removed. Documents and settings outside the app remain untouched.") }
        .alert("Couldn’t complete that", isPresented: Binding(get: { cleaner.errorMessage != nil }, set: { if !$0 { cleaner.errorMessage = nil } })) {
            Button("OK") { cleaner.errorMessage = nil }
        } message: { Text(cleaner.errorMessage ?? "Unknown error") }
        .sheet(isPresented: $showingHelp) { HelpView() }
    }

    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                pageTitle("Mac overview", "Storage health and safe actions at a glance")
                storageCard
                HStack(spacing: 14) {
                    overviewAction("Find duplicates", "Review exact copies", "doc.on.doc", .duplicates)
                    overviewAction("Safe cleanup", format(cleaner.selectedBytes) + " ready", "sparkles", .cleanup)
                    overviewAction("Applications", "Remove selected apps", "app.dashed", .apps)
                }
                statusCard
            }.padding(28).frame(maxWidth: 1000, alignment: .leading)
        }
    }

    private var duplicates: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                pageTitle("Duplicate finder", "Choose folders, verify exact matches, then review every file")
                Spacer()
                if cleaner.isScanningDuplicates {
                    Button("Cancel", role: .cancel) { cleaner.cancelDuplicateScan() }
                } else {
                    Button("Choose folders or files…") { cleaner.chooseAndScanDuplicates() }.buttonStyle(.borderedProminent)
                }
            }.padding(28).padding(.bottom, 0)
            if cleaner.isScanningDuplicates {
                VStack(spacing: 10) {
                    ProgressView(value: Double(cleaner.duplicateProgress.completed), total: Double(max(cleaner.duplicateProgress.total, cleaner.duplicateProgress.completed + 1)))
                    HStack { Text(cleaner.duplicateProgress.phase.rawValue); Spacer(); Text(progressText).monospacedDigit() }.font(.caption).foregroundStyle(.secondary)
                }.padding(.horizontal, 28).padding(.bottom, 16)
            }
            if cleaner.duplicateGroups.isEmpty && !cleaner.isScanningDuplicates {
                ContentUnavailableView("No duplicate results", systemImage: "doc.on.doc", description: Text("Choose folders or files to start an exact-content scan."))
            } else {
                List {
                    ForEach(cleaner.duplicateGroups) { group in
                        Section("\(group.files.count) identical files • \(format(group.bytesPerFile)) each") {
                            ForEach(group.files) { file in duplicateRow(file, in: group) }
                        }
                    }
                }
            }
            if !cleaner.duplicateGroups.isEmpty {
                Divider()
                HStack {
                    Text("\(cleaner.duplicateGroups.count) sets • \(cleaner.duplicateFileCount) files • \(format(cleaner.duplicateSelectedBytes)) selected")
                    Spacer()
                    Button("Move selected to Trash", systemImage: "trash") { confirmingDuplicateTrash = true }
                        .buttonStyle(.borderedProminent).disabled(cleaner.duplicateSelectedBytes == 0)
                }.padding(16)
            }
        }
    }

    private func duplicateRow(_ file: DuplicateFile, in group: DuplicateGroup) -> some View {
        HStack(spacing: 12) {
            Button { cleaner.toggleDuplicate(groupID: group.id, fileID: file.id) } label: {
                Image(systemName: file.isSelected ? "checkmark.circle.fill" : "shield.checkered")
                    .foregroundStyle(file.isSelected ? Color.accentColor : .green)
            }.buttonStyle(.plain).help(file.isSelected ? "Move this copy to Trash" : "Keeper — one copy must remain")
            Image(nsImage: NSWorkspace.shared.icon(forFile: file.url.path)).resizable().frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(file.url.lastPathComponent).fontWeight(.medium).lineLimit(1)
                Text(file.url.deletingLastPathComponent().path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(format(file.bytes)).monospacedDigit()
                Text(file.modifiedAt?.formatted(date: .abbreviated, time: .shortened) ?? "Date unavailable").font(.caption).foregroundStyle(.secondary)
            }
            Button("Reveal", systemImage: "folder") { cleaner.reveal(file.url) }.labelStyle(.iconOnly).help("Reveal in Finder")
            QuickLookPreview(url: file.url)
        }.padding(.vertical, 4)
    }

    private var cleanup: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    pageTitle("Safe cleanup", "Only your Trash and temporary app caches")
                    ForEach(cleaner.targets) { target in
                        Button { cleaner.toggle(target) } label: {
                            HStack(spacing: 14) {
                                Image(systemName: target.isSelected ? "checkmark.circle.fill" : "circle").font(.title3)
                                Image(systemName: target.kind == .trash ? "trash" : "shippingbox").frame(width: 26)
                                VStack(alignment: .leading) { Text(target.kind.rawValue).fontWeight(.semibold); Text(target.detail).font(.caption).foregroundStyle(.secondary) }
                                Spacer(); Text(format(target.bytes)).font(.headline.monospacedDigit())
                            }.padding(18).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
                        }.buttonStyle(.plain).disabled(cleaner.isCleaning)
                    }
                    Label("Documents, Downloads, Photos, music, installed apps, browser history, and macOS files are excluded.", systemImage: "lock.shield")
                        .foregroundStyle(.green).padding(16).background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                }.padding(28).frame(maxWidth: 900)
            }
            Divider()
            HStack { Text("Selected: \(format(cleaner.selectedBytes))").font(.headline); Spacer(); Button("Clear selected permanently", role: .destructive) { confirmingCleanup = true }.disabled(!cleaner.canClean) }.padding(16)
        }
    }

    private var applications: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                pageTitle("Applications", "Remove only app bundles you explicitly choose")
                VStack(spacing: 18) {
                    Image(systemName: "app.dashed").font(.system(size: 54)).foregroundStyle(.tint)
                    Text("Drop .app bundles here").font(.title2.bold())
                    Text("System apps and SANIVA itself are protected. Personal documents and settings outside the app bundle are not touched.").foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 520)
                    Button("Choose applications…") { cleaner.chooseApps() }.buttonStyle(.borderedProminent)
                }.frame(maxWidth: .infinity, minHeight: 320)
                    .background(appDropTargeted ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(.tint.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [8])))
                    .dropDestination(for: URL.self) { urls, _ in cleaner.prepareAppRemoval(urls); return true } isTargeted: { appDropTargeted = $0 }
            }.padding(28).frame(maxWidth: 900)
        }
    }

    private var settings: some View {
        Form {
            Section("Reminders") { Toggle("Weekly storage review — Monday at 10 AM", isOn: $cleaner.weeklyReminderEnabled) }
            Section("All Mac users") {
                Text("This administrator-approved scan is read-only. It never enables deletion for another user.")
                HStack { Button(cleaner.isScanningAllUsers ? "Scanning…" : "Run read-only scan") { Task { await cleaner.scanAllUsers() } }.disabled(cleaner.isScanningAllUsers); if let bytes = cleaner.otherUsersSafeBytes { Text(format(bytes)).foregroundStyle(.secondary) } }
            }
            Section("Privacy") {
                Text("SANIVA works entirely on this Mac. It has no analytics, advertising, accounts, network service, or data upload.")
                Button("Read Privacy Policy") { openBundledDocument("PRIVACY", extension: "md") }
            }
            Section("About") { LabeledContent("Application", value: "SANIVA"); LabeledContent("Version", value: "1.4 (14)"); LabeledContent("Minimum macOS", value: "14 Sonoma") }
            Section("Updates") {
                Text("Version 1.4 adds a read-only Terminal scanner, a white-background master logo, and a transparent in-app wordmark. Version 1.3 introduced the complete duplicate review workflow.")
                Button("View complete release history") { openBundledDocument("CHANGELOG", extension: "md") }
            }
        }.formStyle(.grouped).padding(12)
    }

    private var storageCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("Mac storage").font(.headline); Spacer(); if cleaner.isScanning { ProgressView().controlSize(.small) } }
            ProgressView(value: Double(cleaner.usedBytes), total: Double(max(cleaner.totalBytes, 1))).tint(.blue)
            HStack { metric("Used", cleaner.usedBytes); Spacer(); metric("Available", cleaner.availableBytes); Spacer(); metric("Total", cleaner.totalBytes) }
        }.padding(20).background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    }

    private var statusCard: some View {
        Group { if let status = cleaner.statusMessage { Label(status, systemImage: "checkmark.circle").foregroundStyle(.secondary) } }
    }

    private func overviewAction(_ title: String, _ detail: String, _ icon: String, _ destination: AppSection) -> some View {
        Button { selection = destination } label: {
            VStack(alignment: .leading, spacing: 8) { Image(systemName: icon).font(.title2); Text(title).font(.headline); Text(detail).font(.caption).foregroundStyle(.secondary) }
                .frame(maxWidth: .infinity, alignment: .leading).padding(18).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain)
    }

    private func pageTitle(_ title: String, _ subtitle: String) -> some View { VStack(alignment: .leading, spacing: 4) { Text(title).font(.largeTitle.bold()); Text(subtitle).foregroundStyle(.secondary) } }
    private func metric(_ title: String, _ bytes: Int64) -> some View { VStack(alignment: .leading) { Text(title).font(.caption).foregroundStyle(.secondary); Text(format(bytes)).font(.headline.monospacedDigit()) } }
    private var progressText: String { cleaner.duplicateProgress.total > 0 ? "\(cleaner.duplicateProgress.completed) of \(cleaner.duplicateProgress.total)" : "\(cleaner.duplicateProgress.completed) files" }
    private func format(_ bytes: Int64) -> String { StorageCleanerModel.format(bytes) }
    private func openBundledDocument(_ name: String, extension ext: String) { if let url = Bundle.main.url(forResource: name, withExtension: ext) { NSWorkspace.shared.open(url) } }

    @ViewBuilder private var sanivaLogo: some View {
        if let url = Bundle.main.url(forResource: "SanivaLogo", withExtension: "png"), let image = NSImage(contentsOf: url) {
            Image(nsImage: image).resizable().scaledToFit().accessibilityLabel("SANIVA")
        } else { Text("SANIVA").font(.title.bold()).foregroundStyle(.blue) }
    }
}

private struct QuickLookPreview: View {
    let url: URL
    var body: some View { Button("Preview", systemImage: "eye") { NSWorkspace.shared.open(url) }.labelStyle(.iconOnly).help("Open preview") }
}

private struct HelpView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("SANIVA Help").font(.title.bold())
            help("Duplicates", "Choose folders or files. SANIVA compares samples for speed, verifies matches with full SHA-256, and lets you reveal, preview, and move selected copies to Trash.")
            help("Safe Cleanup", "Permanently clears only selected Trash and app-cache contents after confirmation.")
            help("Applications", "Removes only selected app bundles. Personal files outside them remain untouched.")
            help("Privacy", "All analysis stays on this Mac; SANIVA contains no analytics or network service.")
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(28).frame(width: 620)
    }
    private func help(_ title: String, _ body: String) -> some View { VStack(alignment: .leading, spacing: 3) { Text(title).font(.headline); Text(body).foregroundStyle(.secondary) } }
}

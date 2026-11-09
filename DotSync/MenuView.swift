import ServiceManagement
import Sparkle
import SwiftUI

struct MenuView: View {
    let service: DotService
    let updater: SPUUpdater
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            if service.uninstalled {
                uninstalledView
            } else if let error = service.error {
                Label(error, systemImage: "xmark.octagon").foregroundStyle(.red)
            } else if let status = service.status {
                details(status)
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
            if !service.lastOutput.isEmpty {
                DisclosureGroup("Sortie du dernier sync") {
                    ScrollView {
                        Text(service.lastOutput)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 120)
                }
                .font(.caption)
            }
            if !service.uninstalled {
                Divider()
                actions
            }
        }
        .padding(14)
        .frame(width: 320)
        .task { await service.refresh() }
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Image(systemName: service.health.symbol)
                .font(.title2)
                .foregroundStyle(color(service.health))
                .symbolEffect(.pulse, isActive: service.isSyncing)
            VStack(alignment: .leading, spacing: 2) {
                Text("Dotfiles").font(.headline)
                Text(service.status?.host ?? "—").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await service.sync() }
            } label: {
                if service.isSyncing {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Synchroniser", systemImage: "arrow.triangle.2.circlepath")
                }
            }
            .disabled(service.isSyncing || service.status?.syncing == true)
            .keyboardShortcut("s")
        }
    }

    @ViewBuilder
    private func details(_ s: DotStatus) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if s.syncing && !service.isSyncing {
                Label("Synchro automatique en cours…", systemImage: "clock.arrow.2.circlepath")
            }
            if let last = s.lastSync {
                Label {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(lastSyncTitle(last))
                        Text(last.message).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                } icon: {
                    Image(systemName: last.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(last.ok ? .green : .orange)
                }
            } else {
                Label("Aucune synchro enregistrée", systemImage: "questionmark.circle")
            }
            if s.pendingChanges > 0 {
                Label("\(s.pendingChanges) modification(s) locale(s) en attente", systemImage: "pencil.circle")
            }
            if s.ahead > 0 || s.behind > 0 {
                Label("\(s.ahead) commit(s) à pousser, \(s.behind) à récupérer", systemImage: "arrow.up.arrow.down.circle")
            }
            if !s.hasRemote {
                Label("Pas de dépôt distant configuré", systemImage: "icloud.slash").foregroundStyle(.orange)
            }
            if !s.problems.isEmpty {
                Label("\(s.problems.count) lien(s) à réparer", systemImage: "link.badge.plus").foregroundStyle(.orange)
                ForEach(s.problems.prefix(6)) { p in
                    Text("\(p.state) — \(p.path)")
                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                        .padding(.leading, 24)
                }
                Text("« Synchroniser » les répare.").font(.caption).padding(.leading, 24)
            }
        }
        .font(.callout)
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let s = service.status {
                Toggle("Synchro auto toutes les 30 min", isOn: Binding(
                    get: { s.autosync },
                    set: { on in Task { await service.setAutosync(on) } }
                ))
            }
            Toggle("Lancer à l'ouverture de session", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, on in
                    do {
                        try on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                    } catch {
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }
            HStack {
                Button("Journal") { open(service.status?.log) }
                Button("Dossier") { open(DotService.repo.path) }
                Button("GitHub") { NSWorkspace.shared.open(URL(string: "https://github.com/vincentlauriat/dotfiles")!) }
                Spacer()
                Button("Mises à jour…") { updater.checkForUpdates() }
                Button("Quitter") { NSApp.terminate(nil) }.keyboardShortcut("q")
            }
            .controlSize(.small)
            Button("Désinstaller les dotfiles de ce Mac…", role: .destructive) {
                Task { await confirmUninstall() }
            }
            .buttonStyle(.link)
            .foregroundStyle(.red)
            .font(.caption)
            .disabled(service.isSyncing || service.status?.syncing == true || service.error != nil)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }

    // MARK: - Uninstall

    private var uninstalledView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Dotfiles désinstallés de ce Mac", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("Les fichiers sont redevenus de vrais fichiers.")
                .font(.caption).foregroundStyle(.secondary)
            ScrollView {
                Text(service.lastOutput)
                    .font(.system(.caption2, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 120)
            HStack {
                Button("Supprimer DotSync") {
                    NSWorkspace.shared.recycle([Bundle.main.bundleURL]) { _, _ in
                        DispatchQueue.main.async { NSApp.terminate(nil) }
                    }
                }
                Spacer()
                Button("Quitter") { NSApp.terminate(nil) }.keyboardShortcut("q")
            }
            .controlSize(.small)
        }
        .font(.callout)
    }

    /// Shows the dry run, asks, then runs the real uninstall. The logic lives in `dot uninstall`.
    private func confirmUninstall() async {
        let preview = await service.uninstall(dryRun: true, restoreBackups: false)
        NSApp.activate()
        guard preview.code == 0 else {
            let text = preview.code == 2
                ? "Cette version de ~/.dotfiles/dot ne connaît pas « uninstall » : mets à jour le dépôt dotfiles."
                : preview.output
            showResult(title: "Désinstallation impossible pour l'instant", text: text)
            return
        }
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Désinstaller les dotfiles de ce Mac ?"
        alert.informativeText = "Une dernière synchro pousse d'abord les changements locaux sur GitHub. "
            + "Puis chaque lien vers ~/.dotfiles redevient un vrai fichier avec son contenu actuel, "
            + "la synchro auto s'arrête, et ~/.dotfiles, ~/.config/dotfiles (secrets compris) et le journal "
            + "partent à la Corbeille. Le dépôt GitHub et les autres Macs ne sont pas touchés."
        alert.accessoryView = outputView(preview.output)
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Restaurer les fichiers sauvegardés par « dot link » (~/.dotfiles-backup)"
        alert.suppressionButton?.state = .off
        alert.addButton(withTitle: "Désinstaller")
        alert.addButton(withTitle: "Annuler")
        alert.buttons[0].hasDestructiveAction = true
        alert.buttons[0].keyEquivalent = ""       // Return must not uninstall
        alert.buttons[1].keyEquivalent = "\r"
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let restore = alert.suppressionButton?.state == .on
        let result = await service.uninstall(dryRun: false, restoreBackups: restore)
        if result.code == 0 {
            if SMAppService.mainApp.status == .enabled {
                try? await SMAppService.mainApp.unregister()
            }
            launchAtLogin = SMAppService.mainApp.status == .enabled
        } else {
            showResult(title: "La désinstallation a échoué", text: result.output)
        }
    }

    private func showResult(title: String, text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.accessoryView = outputView(text)
        alert.runModal()
    }

    private func outputView(_ text: String) -> NSView {
        let scroll = NSTextView.scrollableTextView()
        scroll.frame = NSRect(x: 0, y: 0, width: 460, height: 200)
        if let textView = scroll.documentView as? NSTextView {
            textView.string = text
            textView.isEditable = false
            textView.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        }
        return scroll
    }

    // MARK: - Helpers

    private func lastSyncTitle(_ last: DotStatus.LastSync) -> String {
        let when = last.parsedDate.map { $0.formatted(.relative(presentation: .named).locale(Locale(identifier: "fr_FR"))) } ?? last.date
        let what = switch last.kind {
        case "ok": "Synchronisé"
        case "conflict": "Conflit avec un autre Mac"
        case "leak": "Bloqué : secret suspect"
        case "network": "Échec réseau"
        default: "Erreur"
        }
        return "\(what) \(when)"
    }

    private func color(_ health: Health) -> Color {
        switch health {
        case .ok: .green
        case .syncing: .blue
        case .attention: .orange
        case .broken: .red
        case .off: .secondary
        }
    }

    private func open(_ path: String?) {
        guard let path else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }
}

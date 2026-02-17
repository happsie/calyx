import SwiftUI
import SwiftTerm

// MARK: - Throttled Terminal View

/// Subclass that throttles terminal redraws to ~30fps by overriding `setNeedsDisplay(_:)`.
///
/// SwiftTerm's hot paths — `updateDisplay()` (output streaming) and `scrollTo()` (scroll) —
/// both call `setNeedsDisplay(rect)` which maps to Obj-C `setNeedsDisplayInRect:`.
/// On Big Sur+ every such call triggers a full-surface `draw()` with CoreText rendering
/// all visible cells. This override ensures that happens at most 30 times/second.
///
/// First mark after a quiet period (>33ms) is always immediate so interactive
/// typing feels instant. The `needsDisplay` property (separate Obj-C method) is NOT
/// overridden — AppKit uses it internally and overriding it breaks the display pipeline.
class ThrottledTerminalView: LocalProcessTerminalView {
    private static let minIntervalNanos: UInt64 = 33_000_000  // ~30fps

    private var lastDirtyTime: UInt64 = 0
    private var hasPendingDirty = false
    private var dirtyTimer: DispatchWorkItem?

    // Reset throttle on frame changes so resize/layout redraws are never deferred.
    // This fires during sidebar collapse, tab switches, and window resize.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        lastDirtyTime = 0
        dirtyTimer?.cancel()
        dirtyTimer = nil
        hasPendingDirty = false
    }

    override func setNeedsDisplay(_ invalidRect: NSRect) {
        let now = DispatchTime.now().uptimeNanoseconds

        if now - lastDirtyTime >= Self.minIntervalNanos {
            lastDirtyTime = now
            hasPendingDirty = false
            dirtyTimer?.cancel()
            dirtyTimer = nil
            superSetNeedsDisplay(invalidRect)
        } else {
            hasPendingDirty = true
            if dirtyTimer == nil {
                let remaining = Self.minIntervalNanos - (now - lastDirtyTime)
                let work = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    self.dirtyTimer = nil
                    guard self.hasPendingDirty else { return }
                    self.hasPendingDirty = false
                    self.lastDirtyTime = DispatchTime.now().uptimeNanoseconds
                    self.superSetNeedsDisplay(self.bounds)
                }
                dirtyTimer = work
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + .nanoseconds(Int(remaining)),
                    execute: work
                )
            }
        }
    }

    /// Helper: Swift disallows `super` in closures, so we need this trampoline.
    private func superSetNeedsDisplay(_ rect: NSRect) {
        super.setNeedsDisplay(rect)
    }
}

// MARK: - Terminal Container

/// Container NSView that forwards mouse clicks to the terminal subview
/// so it always becomes first responder. Using an AppKit-level mouseDown
/// avoids the SwiftUI `.onTapGesture` gesture recognizer, which can
/// intercept/delay events and prevent the terminal from gaining focus.
class TerminalContainerView: NSView {
    var onMouseDown: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        // Make the terminal subview first responder on any click inside the container
        if let terminal = subviews.first {
            window?.makeFirstResponder(terminal)
        }
        onMouseDown?()
        super.mouseDown(with: event)
    }

    override var acceptsFirstResponder: Bool { false }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override func makeBackingLayer() -> CALayer {
        let layer = super.makeBackingLayer()
        layer.masksToBounds = true
        return layer
    }
}

// MARK: - Terminal Wrapper

/// Thin NSViewRepresentable that hosts terminal views inside a stable container.
/// The container NSView is created once by SwiftUI; terminal subviews are swapped
/// in `updateNSView` when the session changes — no view destruction/recreation.
struct SessionTerminalView: NSViewRepresentable {
    let terminalView: LocalProcessTerminalView
    var isDark: Bool
    var onTap: (() -> Void)?

    class Coordinator {
        var lastIsDark: Bool?
        var currentTerminal: LocalProcessTerminalView?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> TerminalContainerView {
        let container = TerminalContainerView()
        container.wantsLayer = true
        container.onMouseDown = onTap
        installTerminal(terminalView, in: container)
        Session.applyTheme(to: terminalView, isDark: isDark)
        context.coordinator.lastIsDark = isDark
        context.coordinator.currentTerminal = terminalView
        return container
    }

    func updateNSView(_ container: TerminalContainerView, context: Context) {
        let coord = context.coordinator

        // Keep the tap callback up to date (closures may capture new state)
        container.onMouseDown = onTap

        // Swap terminal subview if the session changed
        if coord.currentTerminal !== terminalView {
            coord.currentTerminal?.removeFromSuperview()
            installTerminal(terminalView, in: container)
            coord.currentTerminal = terminalView
            // Force theme apply on swap since this is a different view
            coord.lastIsDark = nil
        }

        // Only apply theme when color scheme actually changed
        if coord.lastIsDark != isDark {
            coord.lastIsDark = isDark
            Session.applyTheme(to: terminalView, isDark: isDark)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: TerminalContainerView, context: Context) -> CGSize? {
        // Return the exact proposed size so the terminal never exceeds its allocated space
        CGSize(width: proposal.width ?? 400, height: proposal.height ?? 300)
    }

    private func installTerminal(_ terminal: LocalProcessTerminalView, in container: NSView) {
        terminal.wantsLayer = true
        terminal.layerContentsRedrawPolicy = .onSetNeedsDisplay

        if let layer = terminal.layer {
            layer.drawsAsynchronously = true
            layer.isOpaque = true
            layer.actions = [
                "contents": NSNull(),
                "bounds": NSNull(),
                "position": NSNull(),
            ]
        }

        terminal.translatesAutoresizingMaskIntoConstraints = false
        terminal.setContentHuggingPriority(.defaultLow, for: .horizontal)
        terminal.setContentHuggingPriority(.defaultLow, for: .vertical)
        terminal.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        terminal.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        // Hide SwiftTerm's legacy scrollbar
        if let scroller = terminal.subviews.first(where: { $0 is NSScroller }) as? NSScroller {
            scroller.isHidden = true
        }

        container.addSubview(terminal)
        terminal.layer?.masksToBounds = true
        NSLayoutConstraint.activate([
            terminal.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            terminal.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            terminal.topAnchor.constraint(equalTo: container.topAnchor),
            terminal.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }
}

// MARK: - Session Detail View

struct SessionDetailView: View {
    let session: Session
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedTab: SessionTab = .agent
    @Namespace private var tabNamespace

    var body: some View {
        VStack(spacing: 0) {
            sessionHeader
            Divider()

            ZStack {
                TerminalPanesView(session: session, isDark: colorScheme == .dark)
                    .transaction { $0.animation = nil }
                    .opacity(selectedTab == .agent ? 1 : 0)
                    .allowsHitTesting(selectedTab == .agent)

                if selectedTab == .diff {
                    DiffContentView(
                        fileDiffs: session.fileDiffs,
                        diffRevision: session.diffRevision,
                        workspace: session,
                        onSwitchToAgent: { selectedTab = .agent }
                    )
                    .transition(.opacity)
                }

                if selectedTab == .plan {
                    PlanView(session: session)
                        .transition(.opacity)
                }

                if selectedTab == .notes {
                    NotesView(session: session)
                        .transition(.opacity)
                }
            }
            .animation(nil, value: selectedTab)
        }
        .onChange(of: session.id) {
            selectedTab = .agent
            session.focusedPaneId = session.terminalPanes.first?.id
            DispatchQueue.main.async {
                let tv = session.terminalView
                tv.window?.makeFirstResponder(tv)
            }
        }
        .onChange(of: selectedTab, initial: true) { old, new in
            if old == .diff { session.stopDiffPolling() }
            if old == .plan { session.stopPlanPolling() }
            if new == .diff { session.startDiffPolling() }
            if new == .plan { session.startPlanPolling() }
            if new == .agent {
                DispatchQueue.main.async {
                    if let focusedId = session.focusedPaneId,
                       let pane = session.terminalPanes.first(where: { $0.id == focusedId }) {
                        pane.terminalView.window?.makeFirstResponder(pane.terminalView)
                    } else {
                        let tv = session.terminalView
                        tv.window?.makeFirstResponder(tv)
                    }
                }
            }
        }
        .onDisappear {
            session.stopDiffPolling()
            session.stopPlanPolling()
        }
    }

    // MARK: - Header

    private var sessionHeader: some View {
        HStack(spacing: 0) {
            tabButton(session.agent.rawValue, icon: session.agent.icon, tab: .agent)
            tabButton("Diff", icon: "doc.text.magnifyingglass", tab: .diff)
            tabButton("Plan", icon: "list.clipboard", tab: .plan)
            tabButton("Notes", icon: "note.text", tab: .notes)
            Spacer(minLength: 0)

            if selectedTab == .agent, session.terminalPanes.count < 3 {
                addPaneMenu
                    .padding(.trailing, 10)
            }
        }
        .frame(height: 36)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
    }

    private var addPaneMenu: some View {
        Menu {
            Button {
                session.addTerminalPane(kind: .shell)
            } label: {
                Label("Terminal", systemImage: "terminal")
            }

            Divider()

            ForEach(CodingAgent.allCases) { agent in
                Button {
                    session.addTerminalPane(kind: .agent, agent: agent)
                } label: {
                    Label(agent.rawValue, systemImage: agent.icon)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus.rectangle.on.rectangle")
                    .font(.system(size: 11, weight: .medium))
                Text("Split")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func tabButton(_ label: String, icon: String, tab: SessionTab) -> some View {
        let isSelected = selectedTab == tab

        return Button(action: {
            withAnimation(.easeInOut(duration: 0.25)) { selectedTab = tab }
        }) {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                HStack(spacing: 5) {
                    Image(systemName: icon)
                        .font(.system(size: 11))
                    Text(label)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                }
                .foregroundStyle(isSelected ? .primary : .secondary)
                Spacer(minLength: 0)

                if isSelected {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(height: 2)
                        .matchedGeometryEffect(id: "tab_underline", in: tabNamespace)
                } else {
                    Rectangle()
                        .fill(.clear)
                        .frame(height: 2)
                }
            }
            .padding(.horizontal, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Terminal Panes View

private struct TerminalPanesView: View {
    let session: Session
    let isDark: Bool

    var body: some View {
        let panes = session.terminalPanes

        if panes.count == 1 {
            // Single pane — no header, no divider
            SessionTerminalView(terminalView: panes[0].terminalView, isDark: isDark)
                .clipped()
        } else {
            // Multiple panes with HSplitView
            HSplitView {
                if panes.count >= 1 { paneView(panes[0]) }
                if panes.count >= 2 { paneView(panes[1]) }
                if panes.count >= 3 { paneView(panes[2]) }
            }
        }
    }

    private func paneView(_ pane: TerminalPane) -> some View {
        VStack(spacing: 0) {
            paneHeader(pane)
            Divider()
            SessionTerminalView(
                terminalView: pane.terminalView,
                isDark: isDark,
                onTap: { session.focusedPaneId = pane.id }
            )
            .clipped()
        }
        .frame(minWidth: 200)
    }

    private func paneHeader(_ pane: TerminalPane) -> some View {
        let isFocused = session.focusedPaneId == pane.id

        return HStack(spacing: 6) {
            if pane.kind == .agent, let agent = pane.agent {
                agentInitialsCircle(agent)
                Text(agent.rawValue)
                    .font(.system(size: 11, weight: .medium))
            } else {
                Image(systemName: "terminal")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text("Terminal")
                    .font(.system(size: 11, weight: .medium))
            }

            Spacer(minLength: 0)

            if session.terminalPanes.count > 1 {
                Button {
                    session.removeTerminalPane(id: pane.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isFocused ? Color.accentColor.opacity(0.08) : Color.clear)
    }

    private func agentInitialsCircle(_ agent: CodingAgent) -> some View {
        Text(agent.initials)
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 16, height: 16)
            .background(agent.tint, in: Circle())
    }

}

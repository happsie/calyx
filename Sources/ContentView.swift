import SwiftUI

struct ContentView: View {
    @State private var selection: SidebarSelection?
    @State private var showSplash = true

    @Environment(AppDelegate.self) private var appDelegate

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
        } detail: {
            DetailView(selection: selection)
        }
        .overlay {
            if showSplash {
                SplashOverlay(isPresented: $showSplash)
            }
        }
        .overlay {
            if appDelegate.isQuitting {
                QuittingOverlay()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
            selection = .settings
        }
    }
}

// MARK: - Quitting Overlay

private struct QuittingOverlay: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.small)
                Text("Closing sessions...")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Splash Overlay

private struct SplashOverlay: View {
    @Binding var isPresented: Bool

    @State private var iconScale: CGFloat = 0.6
    @State private var iconOpacity: Double = 0
    @State private var titleOpacity: Double = 0
    @State private var subtitleOpacity: Double = 0
    @State private var dismissing = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.background)
                .ignoresSafeArea()
                .opacity(dismissing ? 0 : 1)

            VStack(spacing: 16) {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 56, weight: .thin))
                    .foregroundStyle(
                        .linearGradient(
                            colors: [.teal, .green],
                            startPoint: .bottomLeading,
                            endPoint: .topTrailing
                        )
                    )
                    .scaleEffect(iconScale)
                    .opacity(iconOpacity)

                VStack(spacing: 6) {
                    Text("Calyx")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .opacity(titleOpacity)

                    Text("Multi-agent coding sessions")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .opacity(subtitleOpacity)
                }
            }
            .scaleEffect(dismissing ? 1.08 : 1)
            .opacity(dismissing ? 0 : 1)
        }
        .onAppear {
            // Phase 1: Icon springs in
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                iconScale = 1.0
                iconOpacity = 1
            }

            // Phase 2: Title fades in
            withAnimation(.easeOut(duration: 0.4).delay(0.25)) {
                titleOpacity = 1
            }

            // Phase 3: Subtitle fades in
            withAnimation(.easeOut(duration: 0.4).delay(0.45)) {
                subtitleOpacity = 1
            }

            // Phase 4: Dismiss the splash
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                withAnimation(.easeIn(duration: 0.35)) {
                    dismissing = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    isPresented = false
                }
            }
        }
    }
}

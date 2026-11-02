import SwiftUI

@main
struct RadiologyApp: App {
    @NSApplicationDelegateAdaptor(ViewerAppDelegate.self) private var appDelegate
    @State private var model = AppModel()
    /// The viewer's shared store: the open wordbase PR, notes, sessions and sidecar. Every
    /// window reads it; see plans/shell.md.
    @State private var viewer = ViewerStore(paths: ViewerPaths(arguments: ViewerLaunchArguments(CommandLine.arguments)))

    init() {
        guard CommandLine.arguments.contains("--verify-resources") else { return }
        let result = ResourceVerification.run()
        print(result.report)
        exit(result.isComplete ? 0 : 1)
    }

    var body: some Scene {
        Window("Radiology", id: "reader") {
            RootView()
                .environment(model)
                .environment(viewer)
                .environment(viewer.mainWindow)
                .frame(minWidth: Theme.windowMinWidth, minHeight: Theme.windowMinHeight)
                .task {
                    viewer.mainReader = model
                    appDelegate.viewer = viewer
                    let arguments = ViewerLaunchArguments(CommandLine.arguments)
                    if let number = arguments.pullRequest {
                        await viewer.openPR(number)
                        await ViewerAppDelegate.snapshotIfRequested(store: viewer)
                    } else {
                        await model.launch(using: LaunchArguments(CommandLine.arguments))
                    }
                }
        }
        .defaultSize(width: Theme.windowDefaultWidth, height: Theme.windowDefaultHeight)
        .windowResizability(.contentMinSize)
        .commands {
            SidebarCommands()
            ReaderCommands(model: model)
            ViewerCommands(store: viewer)
        }
        WindowGroup("Code", id: CodeWindowView.sceneID, for: CodeWindowRequest.self) { $request in
            if let request {
                CodeWindowView(request: request)
                    .environment(viewer)
            }
        }
        .defaultSize(width: 860, height: 640)
    }
}

//
//  pic_downApp.swift
//  pic_down
//
//  Created by 张三儿 on 2024/10/6.
//

import SwiftUI

struct pic_downApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(width: 400, height: 370)
        }
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let window = NSApplication.shared.windows.first {
            window.title = "图片批量下载器"
            window.setContentSize(NSSize(width: 400, height: 370))
            window.center()
            window.styleMask.remove(.resizable)
        }
    }
}

@main
struct MainApp {
    static func main() {
        NSApplication.shared.run {
            pic_downApp()
        }
    }
}

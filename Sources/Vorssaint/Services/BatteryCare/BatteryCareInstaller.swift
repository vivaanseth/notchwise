// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The administrator's one-time commands. The helper is copied out of the
/// app to where only root can change it, its signature checked there, and
/// its launchd job written in place, so nothing a user can edit runs as root.
enum BatteryCareInstaller {
    static func installCommand(helper source: String) -> String {
        let id = BatteryCareIdentifiers.helperID
        let destination = BatteryCareIdentifiers.installedHelper
        let plist = BatteryCareIdentifiers.launchDaemon
        let buddy = "/usr/libexec/PlistBuddy"
        let entries = [
            "Add :Label string \(id)",
            "Add :Program string \(destination)",
            "Add :MachServices dict",
            "Add :MachServices:\(id) bool true",
            "Add :RunAtLoad bool true",
            "Add :KeepAlive bool true",
        ]
        return [
            "/bin/launchctl bootout system/\(id) 2>/dev/null; true",
            "/bin/mkdir -p /Library/PrivilegedHelperTools",
            "/usr/bin/install -o root -g wheel -m 0755 \(quoted(source)) \(quoted(destination))",
            "/usr/bin/codesign --verify --strict \(quoted(destination))",
            "[ \"$(/usr/bin/codesign -d \(quoted(destination)) 2>&1 | /usr/bin/sed -n 's/^Identifier=//p')\" = '\(id)' ] || { /bin/rm -f \(quoted(destination)); exit 1; }",
            "/bin/rm -f \(quoted(plist))",
        ] .joined(separator: " && ")
            + " && " + entries.map { "\(buddy) -c '\($0)' \(quoted(plist)) >/dev/null" }.joined(separator: " && ")
            + " && /usr/sbin/chown root:wheel \(quoted(plist)) && /bin/chmod 0644 \(quoted(plist))"
            + " && /bin/launchctl bootstrap system \(quoted(plist))"
    }

    static func removeCommand() -> String {
        let id = BatteryCareIdentifiers.helperID
        return [
            // Stopping the helper hands charging back to macOS first.
            "/bin/launchctl bootout system/\(id) 2>/dev/null; true",
            "/bin/rm -f \(quoted(BatteryCareIdentifiers.launchDaemon)) \(quoted(BatteryCareIdentifiers.installedHelper))",
            "/bin/rm -rf \(quoted(BatteryCareIdentifiers.stateDirectory))",
        ].joined(separator: " && ")
    }

    /// One shell word, whatever the path holds.
    static func quoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

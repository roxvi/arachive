import Foundation
import Darwin

// A root-owned, per-user sudoers rule grants only these two exact argument lists.
// No shell, wildcard, app-writable executable, or general-purpose root helper is authorized.
enum SleepAccess {
    static let directory = "/private/etc/sudoers.d"
    static var rulePath: String { "\(directory)/archaive-\(getuid())" }
    static func rule(uid: UInt32) -> String {
        "# Archaive: keep-awake access for this local user only.\n#\(uid) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1\n"
    }
    static var isInstalled: Bool {
        var info = stat()
        guard lstat(rulePath, &info) == 0, info.st_uid == 0,
              (info.st_mode & S_IFMT) == S_IFREG, (info.st_mode & 0o022) == 0 else { return false }
        return (info.st_mode & 0o777) == 0o440
    }
    static func shellQuote(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    static func appleScriptQuote(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n") + "\""
    }
    static func administrator(_ command: String) -> CommandResult {
        System.run("/usr/bin/osascript", ["-e", "do shell script \(appleScriptQuote(command)) with administrator privileges"])
    }
    static func installScript(uid: UInt32) -> String {
        let destination = "\(directory)/archaive-\(uid)"
        return """
        set -eu
        /usr/sbin/visudo -cq
        /usr/bin/grep -Eq '^[#@]includedir[[:space:]]+(/private)?/etc/sudoers.d/?[[:space:]]*$' /private/etc/sudoers || { echo 'This Mac does not include sudoers.d; setup was not changed.' >&2; exit 1; }
        test -d \(directory) && test ! -L \(directory)
        test "$(/usr/bin/stat -f %u \(directory))" = 0
        test -z "$(/usr/bin/find \(directory) -prune -perm +022 -print)"
        umask 077
        archaive_rule=$(/usr/bin/mktemp \(directory)/.archaive.XXXXXX)
        archaive_created=0
        trap '/bin/rm -f "$archaive_rule"; if test "$archaive_created" = 1; then /bin/rm -f \(destination); fi' EXIT
        /usr/bin/printf '%s' \(shellQuote(rule(uid: uid))) > "$archaive_rule"
        /usr/sbin/visudo -cqf "$archaive_rule"
        /usr/sbin/chown root:wheel "$archaive_rule"
        /bin/chmod 0440 "$archaive_rule"
        if test -e \(destination) || test -L \(destination); then
            test ! -L \(destination)
            /usr/bin/cmp -s "$archaive_rule" \(destination) || { echo 'An existing rule differs; it was not overwritten.' >&2; exit 1; }
        else
            /bin/ln "$archaive_rule" \(destination)
            archaive_created=1
        fi
        /usr/sbin/visudo -cq
        archaive_created=0
        """
    }
    static func install() -> CommandResult {
        let result = administrator(installScript(uid: getuid()))
        guard result.status == 0 else { return result }
        return isInstalled ? CommandResult(status: 0, output: "") : CommandResult(status: 1, output: "The permission could not be verified. No sleep setting was changed.")
    }
    static func remove() -> CommandResult {
        administrator("set -eu; /bin/rm -f \(rulePath); /usr/sbin/visudo -cq")
    }
}

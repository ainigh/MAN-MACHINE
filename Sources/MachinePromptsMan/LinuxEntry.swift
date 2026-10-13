// The app is macOS only. On Linux the executable target still builds (CI checks the host and core
// there), and does nothing.
#if !os(macOS)
@main
enum LinuxEntry {
    static func main() {}
}
#endif

/// Where the platform accessibility bridges find the live widget tree.
public enum SemanticsRoot {
    public nonisolated(unsafe) static var provider: (() -> Element?)? = nil
}

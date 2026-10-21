package dalvik.system;

/** dalvik.system.CloseGuard: libcore's unclosed-resource tracker. Apps' networking
    stacks open one per stream and call close() when the resource closes; a no-op
    stand-in that never warns is the right guest behaviour. */
public final class CloseGuard {
    private CloseGuard() {}

    public interface Reporter { void report(String message, Throwable allocationSite); }

    public static CloseGuard get() { return new CloseGuard(); }
    public void setEnabled(boolean enabled) {}
    public void setReporter(Reporter reporter) {}
    public void open(String closer) {}
    public void close() {}
    public void warnIfOpen() {}
}

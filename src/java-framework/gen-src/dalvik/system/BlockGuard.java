package dalvik.system;

/** dalvik.system.BlockGuard: libcore's strict-mode hooks. OkHttp/okio and coroutines
    call getThreadPolicy()/CloseGuard for resource-leak tracking even inside a guest.
    A permissive stand-in: policies are accepted, nothing is enforced. */
public final class BlockGuard {
    private BlockGuard() {}

    public static final Policy LAX_POLICY = new Policy() {
        public void onWriteToDisk() {}
        public void onReadFromDisk() {}
        public void onNetwork() {}
        public int getPolicyMask() { return 0; }
    };

    public interface Policy {
        void onWriteToDisk();
        void onReadFromDisk();
        void onNetwork();
        int getPolicyMask();
    }

    public interface VmPolicy {}

    private static Policy threadPolicy = LAX_POLICY;
    private static VmPolicy vmPolicy;

    public static Policy getThreadPolicy() { return threadPolicy; }
    public static void setThreadPolicy(Policy policy) { threadPolicy = policy == null ? LAX_POLICY : policy; }
    public static VmPolicy getVmPolicy() { return vmPolicy; }
    public static void setVmPolicy(VmPolicy policy) { vmPolicy = policy; }
}

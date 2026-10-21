package dalvik.system;

/** dalvik.system.VMRuntime: libcore's runtime hooks. Apps that manage their own
    caches (stores, VMs-in-VMs) call newNonMovableArray/addressOf for pinning;
    the guest runtime needs the entry points, not the pinning semantics. */
public final class VMRuntime {
    private static final VMRuntime THE_ONE = new VMRuntime();
    private int targetSdkVersion = 35;
    private VMRuntime() {}

    public static VMRuntime getRuntime() { return THE_ONE; }

    public Object newNonMovableArray(Class<?> componentType, int length) {
        return java.lang.reflect.Array.newInstance(componentType, length);
    }
    public Object newUnpaddedArray(Class<?> componentType, int minLength) {
        return java.lang.reflect.Array.newInstance(componentType, minLength);
    }
    public long addressOf(Object obj) { return 0; }
    public long sizeOf(Object obj) { return 0; }
    public void trim() {}
    public void clearGrowthLimit() {}
    public void notifyNativeAllocations() {}
    public void clampGrowthLimit() {}
    public void registerNativeAllocation(int bytes) {}
    public void registerNativeFree(int bytes) {}
    public void setTargetSdkVersion(int targetSdkVersion) { this.targetSdkVersion = targetSdkVersion; }
    public int getTargetSdkVersion() { return targetSdkVersion; }
    public boolean is64Bit() { return true; }
    public String vmInstructionSet() { return "arm64"; }
    public boolean isCheckJniEnabled() { return false; }
    public String getRuntimeMappedFileNames() { return ""; }
    public String getCurrentInstructionSet() { return "arm64"; }
    public String[] getProperties() { return new String[0]; }
    public String bootClassPath() { return ""; }
    public String classPath() { return ""; }
    public String vmLibrary() { return "libjavacore.so"; }
    public long getFinalizerTimeoutMs() { return 0; }
}

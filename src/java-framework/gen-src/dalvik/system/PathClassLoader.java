package dalvik.system;

/** dalvik.system.PathClassLoader: the class loader every app process runs
    under. Same behaviour contract as BaseDexClassLoader on the guest. */
public class PathClassLoader extends dalvik.system.BaseDexClassLoader {
    public PathClassLoader(java.lang.String dexPath, java.lang.ClassLoader parent) {
        super(dexPath, null, null, parent);
    }
    public PathClassLoader(java.lang.String dexPath, java.lang.String librarySearchPath, java.lang.ClassLoader parent) {
        super(dexPath, null, librarySearchPath, parent);
    }
    PathClassLoader() { this((java.lang.String) null, (java.lang.ClassLoader) null); }
}

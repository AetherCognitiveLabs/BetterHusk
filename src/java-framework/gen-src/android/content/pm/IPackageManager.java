package android.content.pm;

/** android.content.pm.IPackageManager: the hidden system interface behind
    PackageManager. Package-manager apps bind to it through
    IPackageManager.Stub.asInterface(). */
public interface IPackageManager extends android.os.IInterface {
    android.content.pm.PackageInfo getPackageInfo(String packageName, long flags, int userId) throws android.os.RemoteException;
    android.content.pm.PackageInfo getPackageInfo(android.content.pm.VersionedPackage versionedPackage, long flags, int userId) throws android.os.RemoteException;
    android.content.pm.ApplicationInfo getApplicationInfo(String packageName, long flags, int userId) throws android.os.RemoteException;
    android.content.pm.ParceledListSlice getInstalledPackages(long flags, int userId) throws android.os.RemoteException;
    android.content.pm.ParceledListSlice getInstalledApplications(long flags, int userId) throws android.os.RemoteException;
    android.content.pm.ParceledListSlice queryIntentActivities(android.content.Intent intent, String resolvedType, long flags, int userId) throws android.os.RemoteException;
    android.content.pm.IPackageInstaller getPackageInstaller() throws android.os.RemoteException;
    boolean isPackageAvailable(String packageName, int userId) throws android.os.RemoteException;
    int getPackageUid(String packageName, long flags, int userId) throws android.os.RemoteException;
    int installExistingPackageAsUser(String packageName, int userId, int installFlags, int installReason, java.util.List<String> whiteListedPermissions) throws android.os.RemoteException;
    void deletePackageAsUser(String packageName, int versionCode, android.content.pm.IPackageDeleteObserver observer, int userId, int deleteFlags) throws android.os.RemoteException;
    void deletePackageVersioned(android.content.pm.VersionedPackage versionedPackage, android.content.pm.IPackageDeleteObserver2 observer, int userId, int deleteFlags) throws android.os.RemoteException;
    void freeStorage(long freeStorageSize, android.content.IntentSender pi) throws android.os.RemoteException;

    abstract class Stub extends android.os.Binder implements IPackageManager {
        private static final String DESCRIPTOR = "android.content.pm.IPackageManager";
        public Stub() { attachInterface(this, DESCRIPTOR); }
        public static IPackageManager asInterface(android.os.IBinder obj) {
            if (obj == null) return null;
            android.os.IInterface iin = obj.queryLocalInterface(DESCRIPTOR);
            if (iin instanceof IPackageManager) return (IPackageManager) iin;
            return null;
        }
        public android.os.IBinder asBinder() { return this; }
        public boolean onTransact(int code, android.os.Parcel data, android.os.Parcel reply, int flags) throws android.os.RemoteException {
            return super.onTransact(code, data, reply, flags);
        }
    }
}

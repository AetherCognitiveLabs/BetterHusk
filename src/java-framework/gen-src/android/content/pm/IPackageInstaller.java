package android.content.pm;

/** android.content.pm.IPackageInstaller: the hidden binder interface behind
    PackageInstaller. Stores that manage installs (Aurora, F-Droid privileged
    paths) reach it via IPackageManager.getPackageInstaller(). */
public interface IPackageInstaller extends android.os.IInterface {
    int createSession(android.content.pm.PackageInstaller.SessionParams params) throws android.os.RemoteException;
    void updateSessionAppIcon(int sessionId, android.graphics.Bitmap appIcon) throws android.os.RemoteException;
    void updateSessionAppLabel(int sessionId, CharSequence appLabel) throws android.os.RemoteException;
    void abandonSession(int sessionId) throws android.os.RemoteException;
    android.content.pm.IPackageInstallerSession openSession(int sessionId) throws android.os.RemoteException;
    android.content.pm.PackageInstaller.SessionInfo getSessionInfo(int sessionId) throws android.os.RemoteException;
    android.content.pm.ParceledListSlice getAllSessions(int userId) throws android.os.RemoteException;
    android.content.pm.ParceledListSlice getMySessions(String installerPackageName, int userId) throws android.os.RemoteException;
    android.content.pm.ParceledListSlice getStagedSessions() throws android.os.RemoteException;
    void registerCallback(android.content.pm.IPackageInstallerCallback callback) throws android.os.RemoteException;
    void registerCallback(android.content.pm.IPackageInstallerCallback callback, int userId) throws android.os.RemoteException;
    void unregisterCallback(android.content.pm.IPackageInstallerCallback callback) throws android.os.RemoteException;
    void uninstall(android.content.pm.VersionedPackage versionedPackage, String callerPackageName, int flags, android.content.IntentSender statusReceiver, int userId) throws android.os.RemoteException;
    void uninstallExisting(android.content.pm.VersionedPackage versionedPackage, String callerPackageName, android.content.IntentSender statusReceiver, int userId) throws android.os.RemoteException;
    void installExisting(String packageName, int installFlags, int installReason, android.content.IntentSender statusReceiver, int userId) throws android.os.RemoteException;
    void setPermissionsResult(int sessionId, boolean accepted) throws android.os.RemoteException;

    abstract class Stub extends android.os.Binder implements IPackageInstaller {
        private static final String DESCRIPTOR = "android.content.pm.IPackageInstaller";
        public Stub() { attachInterface(this, DESCRIPTOR); }
        public static IPackageInstaller asInterface(android.os.IBinder obj) {
            if (obj == null) return null;
            android.os.IInterface iin = obj.queryLocalInterface(DESCRIPTOR);
            if (iin instanceof IPackageInstaller) return (IPackageInstaller) iin;
            return null;
        }
        public android.os.IBinder asBinder() { return this; }
        public boolean onTransact(int code, android.os.Parcel data, android.os.Parcel reply, int flags) throws android.os.RemoteException {
            return super.onTransact(code, data, reply, flags);
        }
    }
}

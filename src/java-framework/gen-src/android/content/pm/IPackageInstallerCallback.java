package android.content.pm;

/** android.content.pm.IPackageInstallerCallback: hidden binder callbacks for
    session lifecycle events. */
public interface IPackageInstallerCallback extends android.os.IInterface {
    void onSessionCreated(int sessionId) throws android.os.RemoteException;
    void onSessionBadgingChanged(int sessionId) throws android.os.RemoteException;
    void onSessionActiveChanged(int sessionId, boolean active) throws android.os.RemoteException;
    void onSessionProgressChanged(int sessionId, float progress) throws android.os.RemoteException;
    void onSessionFinished(int sessionId, boolean success) throws android.os.RemoteException;

    abstract class Stub extends android.os.Binder implements IPackageInstallerCallback {
        private static final String DESCRIPTOR = "android.content.pm.IPackageInstallerCallback";
        public Stub() { attachInterface(this, DESCRIPTOR); }
        public static IPackageInstallerCallback asInterface(android.os.IBinder obj) {
            if (obj == null) return null;
            android.os.IInterface iin = obj.queryLocalInterface(DESCRIPTOR);
            if (iin instanceof IPackageInstallerCallback) return (IPackageInstallerCallback) iin;
            return null;
        }
        public android.os.IBinder asBinder() { return this; }
        public boolean onTransact(int code, android.os.Parcel data, android.os.Parcel reply, int flags) throws android.os.RemoteException {
            return super.onTransact(code, data, reply, flags);
        }
    }
}

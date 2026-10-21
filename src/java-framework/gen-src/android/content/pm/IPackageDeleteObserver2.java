package android.content.pm;

/** android.content.pm.IPackageDeleteObserver2: VersionedPackage-era delete callback. */
public interface IPackageDeleteObserver2 extends android.os.IInterface {
    void onUserActionRequired(android.content.Intent intent) throws android.os.RemoteException;
    void onPackageDeleted(String packageName, int returnCode, String msg) throws android.os.RemoteException;

    abstract class Stub extends android.os.Binder implements IPackageDeleteObserver2 {
        private static final String DESCRIPTOR = "android.content.pm.IPackageDeleteObserver2";
        public Stub() { attachInterface(this, DESCRIPTOR); }
        public static IPackageDeleteObserver2 asInterface(android.os.IBinder obj) {
            if (obj == null) return null;
            android.os.IInterface iin = obj.queryLocalInterface(DESCRIPTOR);
            if (iin instanceof IPackageDeleteObserver2) return (IPackageDeleteObserver2) iin;
            return null;
        }
        public android.os.IBinder asBinder() { return this; }
        public boolean onTransact(int code, android.os.Parcel data, android.os.Parcel reply, int flags) throws android.os.RemoteException {
            return super.onTransact(code, data, reply, flags);
        }
    }
}

package android.content.pm;

/** android.content.pm.ParceledListSlice: the hidden Parcelable that
    IPackageManager/IPackageInstaller return instead of List (binder-size
    safety). Locals here, so a plain list wrapper carries the data through. */
public class ParceledListSlice<T extends android.os.Parcelable> extends android.content.pm.BaseParceledListSlice<T> {
    public ParceledListSlice(java.util.List<T> list) { super(list); }
    ParceledListSlice(android.os.Parcel in, ClassLoader loader) { super(in, loader); }
    public static final android.os.Parcelable.ClassLoaderCreator<ParceledListSlice> CREATOR =
        new android.os.Parcelable.ClassLoaderCreator<ParceledListSlice>() {
            public ParceledListSlice createFromParcel(android.os.Parcel in) { return new ParceledListSlice(in, null); }
            public ParceledListSlice createFromParcel(android.os.Parcel in, ClassLoader loader) { return new ParceledListSlice(in, loader); }
            public ParceledListSlice[] newArray(int size) { return new ParceledListSlice[size]; }
        };
}

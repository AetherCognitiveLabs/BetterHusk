package android.content.pm;

/** android.content.pm.BaseParceledListSlice: shared base of ParceledListSlice
    carrying the real list. getList() is how every caller reads results. */
public class BaseParceledListSlice<T> implements android.os.Parcelable {
    private final java.util.List<T> list;
    public BaseParceledListSlice(java.util.List<T> list) { this.list = list; }
    BaseParceledListSlice(android.os.Parcel in, ClassLoader loader) { this.list = new java.util.ArrayList<>(); }
    public java.util.List<T> getList() { return list; }
    public int describeContents() { return 0; }
    public void writeToParcel(android.os.Parcel dest, int flags) {}
}

package husk;

import android.app.ActionBar;
import android.app.Activity;
import android.graphics.drawable.Drawable;
import android.view.View;
import android.app.FragmentTransaction;
import android.widget.LinearLayout;
import android.widget.TextView;
import java.util.ArrayList;

/** The platform action bar a plain Activity gets from its theme: a title bar (husk.DecorView's), its menu shown as actions when there is room. */
public final class SimpleActionBar extends ActionBar {
    private final Activity mActivity;
    private final DecorView mDecor;
    private CharSequence mTitle, mSubtitle;
    private int mOptions = DISPLAY_SHOW_TITLE | DISPLAY_SHOW_HOME;
    private View mCustom;
    private boolean mShowing = true;
    public SimpleActionBar(Activity a, DecorView d) { mActivity = a; mDecor = d; mTitle = a.getTitle(); }
    public void setCustomView(View v) { mCustom = v; } public void setCustomView(View v, LayoutParams p) { mCustom = v; } public void setCustomView(int r) { mCustom = android.view.LayoutInflater.from(mActivity).inflate(r, null); }
    public void setIcon(int r) {} public void setIcon(Drawable d) {} public void setLogo(int r) {} public void setLogo(Drawable d) {}
    public void setDisplayOptions(int o) { mOptions = o; } public void setDisplayOptions(int o, int mask) { mOptions = (mOptions & ~mask) | (o & mask); }
    public void setDisplayUseLogoEnabled(boolean e) {} public void setDisplayShowHomeEnabled(boolean e) {} public void setDisplayHomeAsUpEnabled(boolean e) {}
    public void setDisplayShowTitleEnabled(boolean e) { mDecor.setTitle(e ? mTitle : ""); } public void setDisplayShowCustomEnabled(boolean e) {}
    public void setBackgroundDrawable(Drawable d) { View v = mDecor.actionBarView(); if (v != null) v.setBackground(d); }
    public View getCustomView() { return mCustom; }
    public CharSequence getTitle() { return mTitle; } public CharSequence getSubtitle() { return mSubtitle; }
    public void setTitle(CharSequence t) { mTitle = t; mDecor.setTitle(t); } public void setTitle(int r) { setTitle(mActivity.getText(r)); }
    public void setSubtitle(CharSequence s) { mSubtitle = s; } public void setSubtitle(int r) { mSubtitle = mActivity.getText(r); }
    public int getDisplayOptions() { return mOptions; }
    public int getHeight() { View v = mDecor.actionBarView(); return v == null ? 0 : v.getHeight(); }
    public void show() { mShowing = true; mDecor.showActionBar(true); } public void hide() { mShowing = false; mDecor.showActionBar(false); }
    public boolean isShowing() { return mShowing; }
    public void addOnMenuVisibilityListener(OnMenuVisibilityListener l) {} public void removeOnMenuVisibilityListener(OnMenuVisibilityListener l) {}
    public android.content.Context getThemedContext() { return mActivity; }

    /* ---- navigation tabs (NAVIGATION_MODE_TABS): a row under the bar; selecting one runs the app's TabListener with a transaction
       on the activity's fragments, committed after, as the platform's does */
    private int mNavMode = NAVIGATION_MODE_STANDARD;
    private final ArrayList<TabImpl> mTabs = new ArrayList<>();
    private TabImpl mSelected;
    private LinearLayout mStrip;
    @Override public void setNavigationMode(int m) { mNavMode = m; updateStrip(); }
    @Override public int getNavigationMode() { return mNavMode; }
    @Override public Tab newTab() { return new TabImpl(); }
    @Override public void addTab(Tab t) { addTab(t, mTabs.size(), mTabs.isEmpty()); }
    @Override public void addTab(Tab t, boolean s) { addTab(t, mTabs.size(), s); }
    @Override public void addTab(Tab t, int p) { addTab(t, p, mTabs.isEmpty()); }
    @Override public void addTab(Tab t, int p, boolean s) {
        TabImpl ti = (TabImpl) t;
        mTabs.add(p, ti);
        updateStrip();
        if (s) selectTab(ti);
    }
    @Override public void removeTab(Tab t) { mTabs.remove(t); if (mSelected == t) mSelected = null; updateStrip(); }
    @Override public void removeTabAt(int p) { removeTab(mTabs.get(p)); }
    @Override public void removeAllTabs() { mTabs.clear(); mSelected = null; updateStrip(); }
    @Override public Tab getSelectedTab() { return mSelected; }
    @Override public Tab getTabAt(int i) { return mTabs.get(i); }
    @Override public int getTabCount() { return mTabs.size(); }
    @Override public int getSelectedNavigationIndex() { return mNavMode == NAVIGATION_MODE_TABS && mSelected != null ? mTabs.indexOf(mSelected) : -1; }
    @Override public int getNavigationItemCount() { return mNavMode == NAVIGATION_MODE_TABS ? mTabs.size() : 0; }
    @Override public void setSelectedNavigationItem(int p) { if (mNavMode == NAVIGATION_MODE_TABS && p >= 0 && p < mTabs.size()) selectTab(mTabs.get(p)); }
    @Override public void selectTab(Tab t) {
        TabImpl ti = (TabImpl) t;
        FragmentTransaction ft = mActivity.getFragmentManager().beginTransaction();
        if (mSelected == ti) { if (ti.listener != null) ti.listener.onTabReselected(ti, ft); }
        else {
            if (mSelected != null && mSelected.listener != null) mSelected.listener.onTabUnselected(mSelected, ft);
            mSelected = ti;
            if (ti != null && ti.listener != null) ti.listener.onTabSelected(ti, ft);
        }
        ft.commit();
        updateStrip();
    }
    private void updateStrip() {
        if (mNavMode != NAVIGATION_MODE_TABS || mTabs.isEmpty()) { mDecor.setTabStrip(null); return; }
        if (mStrip == null) {
            mStrip = new LinearLayout(mActivity);
            mStrip.setOrientation(LinearLayout.HORIZONTAL);
            View bar = mDecor.actionBarView();
            if (bar != null && bar.getBackground() != null) mStrip.setBackground(bar.getBackground().getConstantState() != null ? bar.getBackground().getConstantState().newDrawable() : null);
            else mStrip.setBackgroundColor(0xFF212121);
        }
        mStrip.removeAllViews();
        for (TabImpl t : mTabs) {
            View v = t.custom;
            if (v == null) {
                TextView tv = new TextView(mActivity);
                tv.setText(t.text != null ? t.text.toString().toUpperCase(java.util.Locale.getDefault()) : "");
                tv.setGravity(android.view.Gravity.CENTER);
                tv.setTextColor(t == mSelected ? 0xFFFFFFFF : 0xB3FFFFFF);
                tv.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, 14);
                v = tv;
            }
            final TabImpl tab = t;
            v.setOnClickListener(x -> selectTab(tab));
            if (v.getParent() instanceof android.view.ViewGroup) ((android.view.ViewGroup) v.getParent()).removeView(v);
            mStrip.addView(v, new LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.MATCH_PARENT, 1f));
        }
        mDecor.setTabStrip(mStrip);
    }
    private final class TabImpl extends Tab {
        CharSequence text, desc; Drawable icon; View custom; Object tag; TabListener listener;
        public int getPosition() { return mTabs.indexOf(this); }
        public Drawable getIcon() { return icon; }
        public CharSequence getText() { return text; }
        public Tab setIcon(Drawable d) { icon = d; return this; }
        public Tab setIcon(int r) { icon = mActivity.getDrawable(r); return this; }
        public Tab setText(CharSequence t) { text = t; if (mStrip != null) updateStrip(); return this; }
        public Tab setText(int r) { return setText(mActivity.getText(r)); }
        public Tab setCustomView(View v) { custom = v; return this; }
        public Tab setCustomView(int r) { custom = android.view.LayoutInflater.from(mActivity).inflate(r, null); return this; }
        public View getCustomView() { return custom; }
        public Tab setTag(Object t) { tag = t; return this; }
        public Object getTag() { return tag; }
        public Tab setTabListener(TabListener l) { listener = l; return this; }
        public void select() { selectTab(this); }
        public Tab setContentDescription(int r) { desc = mActivity.getText(r); return this; }
        public Tab setContentDescription(CharSequence c) { desc = c; return this; }
        public CharSequence getContentDescription() { return desc; }
    }
}

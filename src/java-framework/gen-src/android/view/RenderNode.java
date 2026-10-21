package android.view;

/** android.view.RenderNode (API 21-28 hidden API, superseded by android.graphics.RenderNode):
    apps built against full framework jars still reference it. Records its properties so the
    getters read back what the setters wrote; nothing is rendered. */
public class RenderNode {
    private final java.lang.String mName;
    private float mAlpha = 1f, mCameraDistance, mElevation, mPivotX, mPivotY,
        mRotation, mRotationX, mRotationY, mScaleX = 1f, mScaleY = 1f, mTranslationX, mTranslationY;
    private int mLeft, mTop, mRight, mBottom, mLayerType, mAmbientShadowColor, mSpotShadowColor;
    private boolean mClipToBounds = true, mClipToOutline, mOverlapping = true;
    private android.graphics.Outline mOutline;
    private android.graphics.Paint mLayerPaint;

    private RenderNode(String name) { mName = name; }
    public static RenderNode create(String name, View owner) { return new RenderNode(name); }

    public DisplayListCanvas start(int width, int height) { return new DisplayListCanvas(); }
    public void end(DisplayListCanvas c) {}
    public void discardDisplayList() {}
    public boolean isValid() { return true; }
    public boolean hasOverlappingRendering() { return mOverlapping; }
    public boolean hasIdentityMatrix() { return true; }
    public void getMatrix(android.graphics.Matrix out) { if (out != null) out.reset(); }
    public void getInverseMatrix(android.graphics.Matrix out) { if (out != null) out.reset(); }

    public int getLeft() { return mLeft; }
    public int getTop() { return mTop; }
    public int getRight() { return mRight; }
    public int getBottom() { return mBottom; }
    public int getWidth() { return mRight - mLeft; }
    public int getHeight() { return mBottom - mTop; }
    public boolean setLeftTopRightBottom(int l, int t, int r, int b) { mLeft = l; mTop = t; mRight = r; mBottom = b; return true; }
    public boolean offsetLeftAndRight(int offset) { mLeft += offset; mRight += offset; return true; }
    public boolean offsetTopAndBottom(int offset) { mTop += offset; mBottom += offset; return true; }

    public float getAlpha() { return mAlpha; }
    public boolean setAlpha(float a) { mAlpha = a; return true; }
    public float getCameraDistance() { return mCameraDistance; }
    public boolean setCameraDistance(float d) { mCameraDistance = d; return true; }
    public boolean getClipToBounds() { return mClipToBounds; }
    public boolean setClipToBounds(boolean c) { mClipToBounds = c; return true; }
    public boolean getClipToOutline() { return mClipToOutline; }
    public boolean setClipToOutline(boolean c) { mClipToOutline = c; return true; }
    public float getElevation() { return mElevation; }
    public boolean setElevation(float e) { mElevation = e; return true; }
    public boolean setHasOverlappingRendering(boolean o) { mOverlapping = o; return true; }
    public int getLayerType() { return mLayerType; }
    public boolean setLayerType(int t) { mLayerType = t; return true; }
    public boolean setLayerPaint(android.graphics.Paint p) { mLayerPaint = p; return true; }
    public android.graphics.Paint getLayerPaint() { return mLayerPaint; }
    public boolean setOutline(android.graphics.Outline o) { mOutline = o == null ? null : new android.graphics.Outline(o); return true; }
    public android.graphics.Outline getOutline(android.graphics.Outline out) { if (out != null && mOutline != null) out.set(mOutline); return out; }
    public float getPivotX() { return mPivotX; }
    public boolean setPivotX(float v) { mPivotX = v; return true; }
    public float getPivotY() { return mPivotY; }
    public boolean setPivotY(float v) { mPivotY = v; return true; }
    public float getRotation() { return mRotation; }
    public boolean setRotation(float v) { mRotation = v; return true; }
    public float getRotationX() { return mRotationX; }
    public boolean setRotationX(float v) { mRotationX = v; return true; }
    public float getRotationY() { return mRotationY; }
    public boolean setRotationY(float v) { mRotationY = v; return true; }
    public float getScaleX() { return mScaleX; }
    public boolean setScaleX(float v) { mScaleX = v; return true; }
    public float getScaleY() { return mScaleY; }
    public boolean setScaleY(float v) { mScaleY = v; return true; }
    public float getTranslationX() { return mTranslationX; }
    public boolean setTranslationX(float v) { mTranslationX = v; return true; }
    public float getTranslationY() { return mTranslationY; }
    public boolean setTranslationY(float v) { mTranslationY = v; return true; }
    public float getTranslationZ() { return 0f; }
    public boolean setTranslationZ(float v) { return true; }
    public int getAmbientShadowColor() { return mAmbientShadowColor; }
    public boolean setAmbientShadowColor(int c) { mAmbientShadowColor = c; return true; }
    public int getSpotShadowColor() { return mSpotShadowColor; }
    public boolean setSpotShadowColor(int c) { mSpotShadowColor = c; return true; }
    public boolean setProjectBackwards(boolean v) { return true; }
    public boolean setProjectionReceiver(boolean v) { return true; }
    public boolean setRevealClip(boolean v, float x, float y, float r) { return true; }
    public boolean setStaticMatrix(android.graphics.Matrix m) { return true; }
    public boolean setAnimationMatrix(android.graphics.Matrix m) { return true; }
}

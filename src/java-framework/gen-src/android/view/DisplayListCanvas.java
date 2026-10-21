package android.view;

/** android.view.DisplayListCanvas (API 21-28 hidden API, superseded by
    android.graphics.BaseRecordingCanvas/RecordingCanvas): the canvas RenderNode.start hands out.
    A plain Canvas subclass — recording draws nothing. */
public class DisplayListCanvas extends android.graphics.Canvas {
    public void drawRenderNode(RenderNode renderNode) {}
    public void insertReorderBarrier() {}
    public void insertInorderBarrier() {}
}

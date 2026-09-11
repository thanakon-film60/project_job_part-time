import React, { useCallback, useEffect, useRef } from "react";
import {
  ANNOTATION_TOOLS,
  createStroke,
  drawAnnotations,
  mediaContentRect,
  pointFromEvent,
} from "@/lib/annotations";
import { cn } from "@/lib/utils";

// ลากสั้นกว่านี้ (สัดส่วนของความกว้างเฟรม) ถือว่ามือสั่น ไม่เก็บเป็นจุดใหม่
// ช่วยลดจำนวนข้อความที่ส่งข้ามสายลงมาก โดยที่เส้นยังดูลื่นเหมือนเดิม
const MIN_STEP = 0.004;

/** ชั้นวาดทับวิดีโอ
 *
 * ฝั่งผู้ช่วยส่ง readOnly={false} เพื่อวาด ฝั่งผู้ใช้ส่ง readOnly เพื่อดูอย่างเดียว
 * ทั้งสองฝั่งวาดด้วยฟังก์ชันเดียวกัน ภาพที่เห็นจึงตรงกันแน่นอน
 *
 * onDraw จะถูกเรียกด้วย "ข้อความแบบเดียวกับที่ส่งข้ามสาย" หน้าเว็บจึงเอาไป
 * ทั้งวาดลงจอตัวเองและส่งต่อได้ในทางเดียว ไม่ต้องแปลงรูปแบบสองรอบ
 */
export default function AnnotationLayer({
  mediaRef,
  strokes,
  readOnly = false,
  tool = ANNOTATION_TOOLS.PEN,
  color = "#ff3b30",
  width = 0.9,
  onDraw,
  className,
}) {
  const canvasRef = useRef(null);
  const activeRef = useRef(null); // เส้นที่กำลังลากอยู่

  const redraw = useCallback(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const box = canvas.getBoundingClientRect();
    if (!box.width || !box.height) return;

    const dpr = window.devicePixelRatio || 1;
    const pixelWidth = Math.round(box.width * dpr);
    const pixelHeight = Math.round(box.height * dpr);
    if (canvas.width !== pixelWidth || canvas.height !== pixelHeight) {
      canvas.width = pixelWidth;
      canvas.height = pixelHeight;
    }

    const ctx = canvas.getContext("2d");
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, box.width, box.height);
    drawAnnotations(ctx, strokes, mediaContentRect(mediaRef.current, box.width, box.height));
  }, [strokes, mediaRef]);

  useEffect(redraw, [redraw]);

  // ขนาดกล่องเปลี่ยน (หมุนจอ/ย่อหน้าต่าง) หรือเพิ่งรู้ขนาดเฟรมวิดีโอ ต้องวาดใหม่
  // ไม่งั้นเส้นจะค้างอยู่ที่ตำแหน่งของขนาดเดิมจนกว่าจะมีการวาดเส้นถัดไป
  useEffect(() => {
    const canvas = canvasRef.current;
    const media = mediaRef.current;
    if (!canvas) return undefined;

    const observer = new ResizeObserver(redraw);
    observer.observe(canvas);
    media?.addEventListener("loadedmetadata", redraw);
    media?.addEventListener("load", redraw);
    return () => {
      observer.disconnect();
      media?.removeEventListener("loadedmetadata", redraw);
      media?.removeEventListener("load", redraw);
    };
  }, [redraw, mediaRef]);

  function pointAt(event) {
    return pointFromEvent(event, canvasRef.current, mediaRef.current);
  }

  function handlePointerDown(event) {
    if (readOnly || event.button === 2) return;
    event.currentTarget.setPointerCapture?.(event.pointerId);
    const stroke = createStroke({ tool, color, width, point: pointAt(event) });
    activeRef.current = stroke;
    onDraw?.({ type: "draw", stroke });
  }

  function handlePointerMove(event) {
    const active = activeRef.current;
    if (readOnly || !active) return;
    const point = pointAt(event);

    if (active.tool !== ANNOTATION_TOOLS.PEN) {
      active.points = [active.points[0], point];
      onDraw?.({ type: "draw_move", id: active.id, point });
      return;
    }

    const last = active.points[active.points.length - 1];
    if (Math.hypot(point[0] - last[0], point[1] - last[1]) < MIN_STEP) return;
    active.points.push(point);
    onDraw?.({ type: "draw_append", id: active.id, points: [point] });
  }

  function handlePointerUp() {
    const active = activeRef.current;
    if (!active) return;
    activeRef.current = null;
    onDraw?.({ type: "draw_end", id: active.id });
  }

  return (
    <canvas
      ref={canvasRef}
      onPointerDown={handlePointerDown}
      onPointerMove={handlePointerMove}
      onPointerUp={handlePointerUp}
      onPointerCancel={handlePointerUp}
      onPointerLeave={handlePointerUp}
      className={cn(
        "absolute inset-0 size-full",
        // touch-none: กันมือถือเลื่อนหน้าจอตอนลากนิ้ววาด
        readOnly ? "pointer-events-none" : "touch-none cursor-crosshair",
        className,
      )}
    />
  );
}

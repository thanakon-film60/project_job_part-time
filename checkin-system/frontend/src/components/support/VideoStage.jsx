import React from "react";
import AnnotationLayer from "@/components/support/AnnotationLayer.jsx";
import { cn } from "@/lib/utils";

const TONE_CLASS = {
  live: "bg-emerald-500/90",
  wait: "bg-amber-500/90",
  bad: "bg-red-500/90",
};

/** เวทีวิดีโอหลัก — ภาพ + เส้นที่วาด + ป้ายสถานะ + ช่องภาพเล็ก
 *
 * ฝั่งผู้ช่วยใช้แสดงภาพจากผู้ใช้ (วาดได้) ฝั่งผู้ใช้ใช้แสดงภาพกล้องตัวเอง (ดูอย่างเดียว)
 * ทั้งสองฝั่งใช้คอมโพเนนต์เดียวกัน เส้นจึงตกลงตำแหน่งเดียวกันเป๊ะ
 */
export default function VideoStage({
  videoRef,
  imageRef,
  frozenSrc,
  muted = false,
  mirrored = false,
  strokes = [],
  readOnly = true,
  tool,
  color,
  width,
  onDraw,
  statusText,
  statusTone = "wait",
  placeholder,
  pip,
  children,
  className,
}) {
  const frozen = Boolean(frozenSrc);

  return (
    <div
      className={cn(
        "relative w-full overflow-hidden rounded-xl bg-slate-950 select-none",
        className,
      )}
    >
      {/* วิดีโอยังอยู่ในหน้าเสมอแม้ตอนหยุดภาพ — ถ้าถอดออกจะต้องต่อ stream ใหม่ตอนเลิกหยุด */}
      <video
        ref={videoRef}
        autoPlay
        playsInline
        muted={muted}
        className={cn(
          "absolute inset-0 size-full object-contain transition-opacity",
          frozen && "opacity-0",
          mirrored && "-scale-x-100",
        )}
      />

      {frozen && (
        <img
          ref={imageRef}
          src={frozenSrc}
          alt="ภาพที่หยุดไว้เพื่อชี้จุด"
          className="absolute inset-0 size-full object-contain"
        />
      )}

      {placeholder && (
        <div className="absolute inset-0 flex items-center justify-center p-6 text-center">
          {placeholder}
        </div>
      )}

      <AnnotationLayer
        mediaRef={frozen ? imageRef : videoRef}
        strokes={strokes}
        readOnly={readOnly}
        tool={tool}
        color={color}
        width={width}
        onDraw={onDraw}
      />

      {statusText && (
        <div className="pointer-events-none absolute top-3 left-3 flex items-center gap-2">
          <span
            className={cn(
              "rounded-full px-2.5 py-1 text-xs font-medium text-white shadow-sm backdrop-blur",
              TONE_CLASS[statusTone] || TONE_CLASS.wait,
            )}
          >
            {statusText}
          </span>
          {frozen && (
            <span className="rounded-full bg-sky-500/90 px-2.5 py-1 text-xs font-medium text-white backdrop-blur">
              ภาพนิ่ง
            </span>
          )}
        </div>
      )}

      {pip && (
        <div className="absolute top-3 right-3 w-24 overflow-hidden rounded-lg border border-white/25 bg-slate-900 shadow-lg sm:w-36">
          {pip}
        </div>
      )}

      {children && (
        <div className="pointer-events-none absolute inset-x-0 bottom-0 flex justify-center p-2 sm:p-3">
          {children}
        </div>
      )}
    </div>
  );
}

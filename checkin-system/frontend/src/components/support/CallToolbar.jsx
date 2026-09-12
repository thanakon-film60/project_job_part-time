import React from "react";
import {
  Circle,
  Eraser,
  MicOff,
  Mic,
  MoveUpRight,
  Pencil,
  PhoneOff,
  Play,
  Snowflake,
  Square,
  Undo2,
  Video,
  VideoOff,
} from "lucide-react";
import { ANNOTATION_COLORS, ANNOTATION_TOOLS, ANNOTATION_WIDTHS } from "@/lib/annotations";
import { cn } from "@/lib/utils";

const TOOL_BUTTONS = [
  { value: ANNOTATION_TOOLS.PEN, label: "วาดอิสระ", icon: Pencil },
  { value: ANNOTATION_TOOLS.CIRCLE, label: "วงกลม", icon: Circle },
  { value: ANNOTATION_TOOLS.ARROW, label: "ลูกศรชี้", icon: MoveUpRight },
  { value: ANNOTATION_TOOLS.RECT, label: "กรอบสี่เหลี่ยม", icon: Square },
];

/** ปุ่มบนแถบเครื่องมือ — เขียนเองแทน Button ของ ui เพราะแถบนี้ลอยอยู่บนวิดีโอสีดำ
 *  ต้องใช้พื้นหลังโปร่งขาวเพื่อให้ยังเห็นภาพข้างหลัง ซึ่งไม่มีใน variant มาตรฐาน
 */
function BarButton({ active, title, disabled, onClick, children, tone = "default" }) {
  return (
    <button
      type="button"
      title={title}
      aria-label={title}
      aria-pressed={active}
      disabled={disabled}
      onClick={onClick}
      className={cn(
        "inline-flex size-10 shrink-0 items-center justify-center rounded-lg border backdrop-blur transition-colors",
        "disabled:pointer-events-none disabled:opacity-40 [&_svg]:size-4.5",
        active
          ? "border-white/70 bg-white text-slate-900"
          : "border-white/25 bg-white/10 text-white hover:bg-white/25",
        tone === "danger" && "border-red-400/40 bg-red-500/80 text-white hover:bg-red-500",
      )}
    >
      {children}
    </button>
  );
}

export default function CallToolbar({
  tool,
  onToolChange,
  color,
  onColorChange,
  width,
  onWidthChange,
  onUndo,
  onClear,
  canUndo,
  frozen,
  onToggleFreeze,
  canFreeze,
  micOn,
  onToggleMic,
  camOn,
  onToggleCam,
  onHangUp,
}) {
  return (
    <div className="pointer-events-auto flex flex-wrap items-center justify-center gap-1.5 rounded-xl bg-black/45 p-2 backdrop-blur-sm sm:gap-2">
      {TOOL_BUTTONS.map(({ value, label, icon: Icon }) => (
        <BarButton
          key={value}
          active={tool === value}
          title={label}
          onClick={() => onToolChange(value)}
        >
          <Icon />
        </BarButton>
      ))}

      <span className="mx-0.5 h-8 w-px bg-white/25" />

      {ANNOTATION_COLORS.map((item) => (
        <button
          key={item.value}
          type="button"
          title={item.label}
          aria-label={`สี${item.label}`}
          aria-pressed={color === item.value}
          onClick={() => onColorChange(item.value)}
          className={cn(
            "size-7 shrink-0 rounded-full border-2 transition-transform",
            color === item.value ? "scale-115 border-white" : "border-white/40 hover:scale-110",
          )}
          style={{ backgroundColor: item.value }}
        />
      ))}

      <span className="mx-0.5 h-8 w-px bg-white/25" />

      {ANNOTATION_WIDTHS.map((item) => (
        <BarButton
          key={item.value}
          active={width === item.value}
          title={`เส้น${item.label}`}
          onClick={() => onWidthChange(item.value)}
        >
          <span
            className="rounded-full bg-current"
            style={{ width: 4 + item.value * 6, height: 4 + item.value * 6 }}
          />
        </BarButton>
      ))}

      <span className="mx-0.5 h-8 w-px bg-white/25" />

      <BarButton title="ย้อนเส้นล่าสุด" onClick={onUndo} disabled={!canUndo}>
        <Undo2 />
      </BarButton>
      <BarButton title="ลบทั้งหมด" onClick={onClear} disabled={!canUndo}>
        <Eraser />
      </BarButton>
      <BarButton
        title={frozen ? "กลับไปดูภาพสด" : "หยุดภาพไว้วาด (ผู้ใช้จะเห็นภาพนิ่งเดียวกัน)"}
        active={Boolean(frozen)}
        onClick={onToggleFreeze}
        disabled={!canFreeze}
      >
        {frozen ? <Play /> : <Snowflake />}
      </BarButton>

      <span className="mx-0.5 h-8 w-px bg-white/25" />

      <BarButton title={micOn ? "ปิดไมค์" : "เปิดไมค์"} onClick={onToggleMic}>
        {micOn ? <Mic /> : <MicOff />}
      </BarButton>
      <BarButton title={camOn ? "ปิดกล้องของฉัน" : "เปิดกล้องของฉัน"} onClick={onToggleCam}>
        {camOn ? <Video /> : <VideoOff />}
      </BarButton>
      <BarButton title="วางสายและปิดห้อง" tone="danger" onClick={onHangUp}>
        <PhoneOff />
      </BarButton>
    </div>
  );
}

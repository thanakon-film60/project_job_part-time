// เครื่องมือวาดชี้จุดบนภาพวิดีโอ — ใช้ร่วมกันทั้งฝั่งผู้ช่วย (คนวาด) และฝั่งผู้ใช้ (คนดู)
//
// พิกัดทุกจุดเก็บเป็นสัดส่วน 0..1 ของ "เฟรมวิดีโอ" ไม่ใช่พิกเซลบนจอ
// เพราะจอสองฝั่งขนาดไม่เท่ากัน (ผู้ช่วยนั่งจอคอม ผู้ใช้ถือมือถือแนวตั้ง)
// ถ้าส่งเป็นพิกเซล วงกลมที่วาดรอบปุ่มจะไปโผล่คนละที่บนจออีกฝั่งทันที

export const ANNOTATION_TOOLS = {
  PEN: "pen",
  CIRCLE: "circle",
  ARROW: "arrow",
  RECT: "rect",
};

export const ANNOTATION_COLORS = [
  { value: "#ff3b30", label: "แดง" },
  { value: "#ffd60a", label: "เหลือง" },
  { value: "#32d74b", label: "เขียว" },
  { value: "#0a84ff", label: "ฟ้า" },
  { value: "#ffffff", label: "ขาว" },
];

// ความหนาเก็บเป็น % ของความกว้างเฟรม จะได้หนาเท่ากันทั้งสองจอ
export const ANNOTATION_WIDTHS = [
  { value: 0.5, label: "บาง" },
  { value: 0.9, label: "กลาง" },
  { value: 1.6, label: "หนา" },
];

const clamp01 = (value) => Math.min(1, Math.max(0, value));

export function createStroke({ tool, color, width, point }) {
  return {
    id: `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`,
    tool,
    color,
    width,
    points: [point],
  };
}

/** ใช้ข้อความที่ได้จากสาย (หรือที่ตัวเองเพิ่งวาด) กับรายการเส้นปัจจุบัน
 *
 * ฝั่งคนวาดกับฝั่งคนดูเรียกฟังก์ชันเดียวกัน ภาพสองฝั่งจึงตรงกันเสมอ
 * โดยไม่ต้องเขียน logic ซ้ำสองชุดให้หลุดกันทีหลัง
 */
export function applyAnnotationMessage(strokes, message) {
  switch (message.type) {
    case "draw": {
      if (!message.stroke?.id) return strokes;
      return [...strokes.filter((s) => s.id !== message.stroke.id), message.stroke];
    }
    case "draw_append":
      return strokes.map((s) =>
        s.id === message.id ? { ...s, points: [...s.points, ...(message.points || [])] } : s,
      );
    case "draw_move":
      // รูปทรง (วงกลม/ลูกศร/สี่เหลี่ยม) เก็บแค่จุดเริ่มกับจุดปลาย ลากอยู่ก็แทนที่จุดปลายไป
      return strokes.map((s) =>
        s.id === message.id ? { ...s, points: [s.points[0], message.point] } : s,
      );
    case "undo":
      return message.id ? strokes.filter((s) => s.id !== message.id) : strokes.slice(0, -1);
    case "clear":
      return [];
    default:
      return strokes;
  }
}

/** กรอบของ "ภาพจริง" ในกล่องที่ใช้ object-fit: contain
 *
 * วิดีโอแนวตั้งจากมือถือวางในกล่องแนวนอนจะมีแถบดำซ้ายขวา
 * ถ้าคิดพิกัดจากขนาดกล่องตรง ๆ เส้นที่วาดจะเลื่อนไปตามความกว้างของแถบดำ
 */
export function mediaContentRect(element, boxWidth, boxHeight) {
  const mediaWidth = element?.videoWidth || element?.naturalWidth || 0;
  const mediaHeight = element?.videoHeight || element?.naturalHeight || 0;
  if (!mediaWidth || !mediaHeight || !boxWidth || !boxHeight) {
    return { x: 0, y: 0, w: boxWidth || 0, h: boxHeight || 0 };
  }
  const scale = Math.min(boxWidth / mediaWidth, boxHeight / mediaHeight);
  const w = mediaWidth * scale;
  const h = mediaHeight * scale;
  return { x: (boxWidth - w) / 2, y: (boxHeight - h) / 2, w, h };
}

export function pointFromEvent(event, canvas, media) {
  const box = canvas.getBoundingClientRect();
  const rect = mediaContentRect(media, box.width, box.height);
  if (!rect.w || !rect.h) return [0, 0];
  return [
    clamp01((event.clientX - box.left - rect.x) / rect.w),
    clamp01((event.clientY - box.top - rect.y) / rect.h),
  ];
}

function arrowHead(ctx, from, to, size) {
  const angle = Math.atan2(to[1] - from[1], to[0] - from[0]);
  const spread = Math.PI / 7;
  ctx.beginPath();
  ctx.moveTo(to[0], to[1]);
  ctx.lineTo(to[0] - size * Math.cos(angle - spread), to[1] - size * Math.sin(angle - spread));
  ctx.moveTo(to[0], to[1]);
  ctx.lineTo(to[0] - size * Math.cos(angle + spread), to[1] - size * Math.sin(angle + spread));
  ctx.stroke();
}

/** วาดเส้นทั้งหมดลง canvas ตามกรอบภาพจริงที่ส่งมา */
export function drawAnnotations(ctx, strokes, rect) {
  ctx.save();
  ctx.lineCap = "round";
  ctx.lineJoin = "round";
  // เงาดำใต้เส้น — ทำให้เส้นสีเหลือง/ขาวยังเห็นชัดบนพื้นหลังสว่าง
  ctx.shadowColor = "rgba(0,0,0,0.55)";
  ctx.shadowBlur = 6;

  for (const stroke of strokes) {
    const pts = (stroke.points || []).map(([x, y]) => [rect.x + x * rect.w, rect.y + y * rect.h]);
    if (!pts.length) continue;

    ctx.strokeStyle = stroke.color || "#ff3b30";
    ctx.lineWidth = Math.max(2, ((stroke.width || 0.9) * rect.w) / 100);

    if (stroke.tool === ANNOTATION_TOOLS.PEN) {
      ctx.beginPath();
      ctx.moveTo(pts[0][0], pts[0][1]);
      for (const [x, y] of pts.slice(1)) ctx.lineTo(x, y);
      // จิ้มจุดเดียวไม่ลาก ก็ให้เห็นเป็นจุดกลม ๆ ไม่ใช่หายไปเฉย ๆ
      if (pts.length === 1) ctx.lineTo(pts[0][0] + 0.01, pts[0][1]);
      ctx.stroke();
      continue;
    }

    const [start, end] = [pts[0], pts[pts.length - 1]];
    if (stroke.tool === ANNOTATION_TOOLS.ARROW) {
      ctx.beginPath();
      ctx.moveTo(start[0], start[1]);
      ctx.lineTo(end[0], end[1]);
      ctx.stroke();
      arrowHead(ctx, start, end, Math.max(12, ctx.lineWidth * 3.5));
      continue;
    }
    if (stroke.tool === ANNOTATION_TOOLS.RECT) {
      ctx.beginPath();
      ctx.rect(start[0], start[1], end[0] - start[0], end[1] - start[1]);
      ctx.stroke();
      continue;
    }
    // วงกลม/วงรี — ลากจากมุมหนึ่งไปอีกมุม แล้ววาดวงรีที่พอดีกรอบนั้น
    ctx.beginPath();
    ctx.ellipse(
      (start[0] + end[0]) / 2,
      (start[1] + end[1]) / 2,
      Math.abs(end[0] - start[0]) / 2,
      Math.abs(end[1] - start[1]) / 2,
      0,
      0,
      Math.PI * 2,
    );
    ctx.stroke();
  }
  ctx.restore();
}

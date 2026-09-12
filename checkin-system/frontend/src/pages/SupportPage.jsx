import React, { useCallback, useEffect, useRef, useState } from "react";
import { toast } from "sonner";
import {
  Copy,
  LifeBuoy,
  Link as LinkIcon,
  Loader2,
  QrCode,
  Snowflake,
  Trash2,
  WifiOff,
} from "lucide-react";
import AppLayout from "../components/AppLayout.jsx";
import CallToolbar from "@/components/support/CallToolbar.jsx";
import VideoStage from "@/components/support/VideoStage.jsx";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  ANNOTATION_COLORS,
  ANNOTATION_TOOLS,
  ANNOTATION_WIDTHS,
  applyAnnotationMessage,
} from "@/lib/annotations";
import { createSupportCall, requestMedia, stopStream } from "@/lib/support-call";
import {
  createSupportSession,
  endSupportSession,
  fetchSupportQr,
  getSupportSessions,
  getToken,
  supportJoinLink,
} from "../api";

const STATUS_TEXT = {
  idle: ["ยังไม่ได้เปิดห้อง", "wait"],
  connecting: ["กำลังเชื่อมต่อ...", "wait"],
  waiting: ["รอผู้ใช้กดลิงก์และอนุญาตกล้อง", "wait"],
  calling: ["ผู้ใช้เข้าห้องแล้ว กำลังต่อสาย...", "wait"],
  connected: ["เชื่อมต่อแล้ว", "live"],
  reconnecting: ["สายหลุด กำลังต่อใหม่...", "bad"],
  failed: ["เชื่อมต่อไม่สำเร็จ", "bad"],
  ended: ["ห้องนี้ถูกปิดแล้ว", "bad"],
  closed: ["ปิดห้องแล้ว", "bad"],
};

const SESSION_BADGE = {
  waiting: { label: "รอผู้ใช้", className: "bg-amber-100 text-amber-800" },
  active: { label: "กำลังคุย", className: "bg-emerald-100 text-emerald-800" },
  ended: { label: "ปิดแล้ว", className: "bg-slate-100 text-slate-600" },
};

/** คัดลอกลิงก์ — clipboard API ใช้ไม่ได้บน http ธรรมดา จึงมีทางถอยไว้ด้วย */
async function copyText(text) {
  try {
    await navigator.clipboard.writeText(text);
    return true;
  } catch {
    const field = document.createElement("textarea");
    field.value = text;
    field.style.position = "fixed";
    field.style.opacity = "0";
    document.body.appendChild(field);
    field.select();
    const ok = document.execCommand?.("copy");
    document.body.removeChild(field);
    return Boolean(ok);
  }
}

export default function SupportPage() {
  const [sessions, setSessions] = useState([]);
  const [active, setActive] = useState(null);
  const [creating, setCreating] = useState(false);
  const [title, setTitle] = useState("");
  const [guestLabel, setGuestLabel] = useState("");

  const [status, setStatus] = useState("idle");
  const [statusDetail, setStatusDetail] = useState("");
  const [strokes, setStrokes] = useState([]);
  const [frozen, setFrozen] = useState(null);
  const [tool, setTool] = useState(ANNOTATION_TOOLS.CIRCLE);
  const [color, setColor] = useState(ANNOTATION_COLORS[0].value);
  const [width, setWidth] = useState(ANNOTATION_WIDTHS[1].value);
  const [micOn, setMicOn] = useState(true);
  const [camOn, setCamOn] = useState(true);
  const [qr, setQr] = useState(null);

  const callRef = useRef(null);
  const localStreamRef = useRef(null);
  const remoteVideoRef = useRef(null);
  const selfVideoRef = useRef(null);
  const frozenImageRef = useRef(null);

  const refreshSessions = useCallback(() => {
    getSupportSessions()
      .then((data) => setSessions(data.sessions || []))
      .catch(() => {});
  }, []);

  useEffect(refreshSessions, [refreshSessions]);

  // ---------------------------------------------------------------- ต่อสาย
  useEffect(() => {
    const code = active?.code;
    if (!code) return undefined;

    let cancelled = false;
    setStrokes([]);
    setFrozen(null);
    setStatus("connecting");
    setStatusDetail("");
    setMicOn(true);
    setCamOn(true);

    const call = createSupportCall({
      code,
      role: "host",
      token: getToken(),
      handlers: {
        onStatus: (next, detail) => {
          if (cancelled) return;
          setStatus(next);
          setStatusDetail(detail || "");
          if (next === "connected") refreshSessions();
        },
        onRemoteStream: (stream) => {
          const video = remoteVideoRef.current;
          if (!video || video.srcObject === stream) return;
          video.srcObject = stream;
          video.play().catch(() => {});
        },
        onPeerLeft: () => {
          if (cancelled) return;
          // เส้นที่วาดไว้อ้างอิงภาพเก่า พอผู้ใช้กลับเข้ามาภาพคนละเฟรมแล้ว ต้องล้างทิ้ง
          setStrokes([]);
          setFrozen(null);
          toast.info("ผู้ใช้ออกจากห้องแล้ว");
        },
        onMessage: (message) => {
          if (message.type === "chat" && message.text) toast.info(`ผู้ใช้: ${message.text}`);
        },
        onError: (error) => console.warn("[support]", error),
      },
    });
    callRef.current = call;

    // กล้องของเราไว้ให้ผู้ใช้เห็นหน้าคนที่คุยด้วย — ไม่มีกล้องก็ยังช่วยงานได้ตามปกติ
    requestMedia({ video: true, audio: true })
      .catch(() => requestMedia({ audio: true }))
      .then((stream) => {
        if (cancelled) {
          stopStream(stream);
          return;
        }
        localStreamRef.current = stream;
        call.setLocalStream(stream);
        if (selfVideoRef.current) {
          selfVideoRef.current.srcObject = stream;
          selfVideoRef.current.play().catch(() => {});
        }
        setCamOn(stream.getVideoTracks().length > 0);
      })
      .catch((error) => {
        if (cancelled) return;
        setCamOn(false);
        setMicOn(false);
        toast.warning(`${error.message} — ยังดูภาพและวาดชี้จุดให้ผู้ใช้ได้ตามปกติ`);
      });

    return () => {
      cancelled = true;
      call.close();
      stopStream(localStreamRef.current);
      localStreamRef.current = null;
      callRef.current = null;
    };
  }, [active?.code, refreshSessions]);

  // เลิกใช้ object URL ของ QR ไม่งั้นรูปเก่าค้างอยู่ในหน่วยความจำไปเรื่อย ๆ
  useEffect(() => () => qr && URL.revokeObjectURL(qr), [qr]);

  // ---------------------------------------------------------------- การวาด
  const handleDraw = useCallback((message) => {
    setStrokes((prev) => applyAnnotationMessage(prev, message));
    callRef.current?.send(message);
  }, []);

  function undo() {
    const last = strokes[strokes.length - 1];
    if (!last) return;
    setStrokes((prev) => prev.filter((item) => item.id !== last.id));
    callRef.current?.send({ type: "undo", id: last.id });
  }

  function clearAll() {
    setStrokes([]);
    callRef.current?.send({ type: "clear" });
  }

  /** หยุดภาพไว้แล้วส่งเฟรมเดียวกันให้ผู้ใช้ดู
   *
   * จำเป็นมากเวลาผู้ใช้ถือมือถือส่องของ: พอเราวงกลมเสร็จ มือเขาขยับไปแล้ว
   * วงกลมเลยไปคร่อมที่ว่าง การตรึงเฟรมเดียวกันทั้งสองฝั่งทำให้ชี้จุดได้ตรงจริง
   */
  function toggleFreeze() {
    if (frozen) {
      setFrozen(null);
      setStrokes([]);
      callRef.current?.send({ type: "unfreeze" });
      return;
    }
    const video = remoteVideoRef.current;
    if (!video?.videoWidth) {
      toast.error("ยังไม่มีภาพจากผู้ใช้");
      return;
    }
    // ย่อไม่เกิน 1280px ก่อนส่ง — ภาพเต็มความละเอียดทำให้ข้อความใหญ่เกินจำเป็น
    const scale = Math.min(1, 1280 / video.videoWidth);
    const canvas = document.createElement("canvas");
    canvas.width = Math.round(video.videoWidth * scale);
    canvas.height = Math.round(video.videoHeight * scale);
    canvas.getContext("2d").drawImage(video, 0, 0, canvas.width, canvas.height);
    const image = canvas.toDataURL("image/jpeg", 0.72);
    setFrozen(image);
    setStrokes([]);
    callRef.current?.send({ type: "freeze", image });
  }

  function toggleTrack(kind, next) {
    localStreamRef.current?.getTracks()
      .filter((track) => track.kind === kind)
      .forEach((track) => {
        track.enabled = next;
      });
    callRef.current?.send({ type: "media", kind, enabled: next });
  }

  // ---------------------------------------------------------------- ห้อง
  async function openRoom(event) {
    event.preventDefault();
    setCreating(true);
    try {
      const session = await createSupportSession({ title: title.trim(), guest_label: guestLabel.trim() });
      setQr(null);
      setActive(session);
      setTitle("");
      setGuestLabel("");
      refreshSessions();
      const copied = await copyText(supportJoinLink(session));
      toast.success(copied ? "สร้างห้องแล้ว คัดลอกลิงก์ให้เรียบร้อย" : "สร้างห้องแล้ว");
    } catch (error) {
      toast.error(String(error.message || error));
    } finally {
      setCreating(false);
    }
  }

  async function closeRoom(code) {
    try {
      await endSupportSession(code);
      if (active?.code === code) setActive(null);
      setStatus("idle");
      refreshSessions();
      toast.success("ปิดห้องแล้ว ลิงก์เดิมใช้ไม่ได้อีก");
    } catch (error) {
      toast.error(String(error.message || error));
    }
  }

  async function copyLink() {
    if (await copyText(link)) toast.success("คัดลอกลิงก์แล้ว");
    else toast.error("คัดลอกไม่สำเร็จ — กดค้างที่ลิงก์เพื่อคัดลอกเองได้");
  }

  async function showQr() {
    if (qr) {
      URL.revokeObjectURL(qr);
      setQr(null);
      return;
    }
    try {
      setQr(await fetchSupportQr(active.code));
    } catch {
      toast.error("สร้าง QR ไม่ได้ — ให้ส่งลิงก์ให้ผู้ใช้แทน");
    }
  }

  const [statusText, statusTone] = STATUS_TEXT[status] || STATUS_TEXT.idle;
  const link = active ? supportJoinLink(active) : "";

  return (
    <AppLayout>
      <div className="space-y-4">
        <div className="hidden lg:block">
          <h2 className="text-2xl font-bold">ช่วยเหลือระยะไกล</h2>
          <p className="text-muted-foreground text-sm">
            เปิดห้อง ส่งลิงก์ให้ผู้ใช้ แล้วชี้จุดที่ต้องแก้บนภาพจากกล้องของเขาได้เลย
            — ผู้ใช้ไม่ต้องมีบัญชีหรือติดตั้งอะไรเพิ่ม
          </p>
        </div>

        {!active && (
          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2">
                <LifeBuoy className="size-5" />
                เปิดห้องช่วยเหลือใหม่
              </CardTitle>
              <CardDescription>
                ผู้ใช้แค่กดลิงก์แล้วกดอนุญาตกล้อง ก็เห็นหน้ากันและคุยกันได้ทันที
              </CardDescription>
            </CardHeader>
            <CardContent>
              <form onSubmit={openRoom} className="grid gap-3 sm:grid-cols-2">
                <div className="space-y-1.5">
                  <Label htmlFor="support-title">เรื่องที่ต้องแก้</Label>
                  <Input
                    id="support-title"
                    value={title}
                    onChange={(event) => setTitle(event.target.value)}
                    placeholder="เช่น ปริ้นเตอร์ไม่ออกกระดาษ"
                    maxLength={160}
                  />
                </div>
                <div className="space-y-1.5">
                  <Label htmlFor="support-guest">ชื่อผู้ใช้ (ไว้ดูย้อนหลัง)</Label>
                  <Input
                    id="support-guest"
                    value={guestLabel}
                    onChange={(event) => setGuestLabel(event.target.value)}
                    placeholder="เช่น คุณสมชาย ฝ่ายบัญชี"
                    maxLength={120}
                  />
                </div>
                <div className="sm:col-span-2">
                  <Button type="submit" loading={creating} className="w-full sm:w-auto">
                    <LinkIcon />
                    สร้างห้องและคัดลอกลิงก์
                  </Button>
                </div>
              </form>
            </CardContent>
          </Card>
        )}

        {active && (
          <>
            <Card>
              <CardHeader>
                <CardTitle className="text-base">
                  {active.title || "ห้องช่วยเหลือ"}
                  {active.guest_label ? ` — ${active.guest_label}` : ""}
                </CardTitle>
                <CardDescription>ส่งลิงก์นี้ให้ผู้ใช้ทางแชทหรือ LINE</CardDescription>
              </CardHeader>
              <CardContent className="space-y-3">
                <div className="flex flex-wrap items-center gap-2">
                  <code className="bg-muted min-w-0 flex-1 truncate rounded-md px-3 py-2 text-xs">
                    {link}
                  </code>
                  <Button variant="outline" onClick={copyLink}>
                    <Copy />
                    คัดลอก
                  </Button>
                  <Button variant="outline" onClick={showQr}>
                    <QrCode />
                    {qr ? "ซ่อน QR" : "QR"}
                  </Button>
                  <Button variant="destructive" onClick={() => closeRoom(active.code)}>
                    <Trash2 />
                    ปิดห้อง
                  </Button>
                </div>

                {qr && (
                  <div className="flex items-center gap-3 rounded-lg border p-3">
                    <img src={qr} alt="QR ลิงก์เข้าห้อง" className="size-32 shrink-0" />
                    <p className="text-muted-foreground text-sm">
                      ให้ผู้ใช้สแกนด้วยกล้องมือถือ เหมาะกับตอนที่เขานั่งอยู่หน้าคอม
                      แต่ต้องใช้มือถือส่องอุปกรณ์ที่มีปัญหาให้เราดู
                    </p>
                  </div>
                )}

                {statusDetail && (
                  <p className="flex items-start gap-2 text-sm text-red-600">
                    <WifiOff className="mt-0.5 size-4 shrink-0" />
                    {statusDetail}
                  </p>
                )}
              </CardContent>
            </Card>

            <VideoStage
              className="aspect-[3/4] max-h-[70svh] sm:aspect-video"
              videoRef={remoteVideoRef}
              imageRef={frozenImageRef}
              frozenSrc={frozen}
              strokes={strokes}
              readOnly={false}
              tool={tool}
              color={color}
              width={width}
              onDraw={handleDraw}
              statusText={statusText}
              statusTone={statusTone}
              placeholder={
                status === "connected" ? null : (
                  <div className="space-y-2 text-white/80">
                    {["connecting", "calling", "reconnecting"].includes(status) && (
                      <Loader2 className="mx-auto size-8 animate-spin" />
                    )}
                    <p className="text-sm">{statusText}</p>
                    {status === "waiting" && (
                      <p className="text-xs text-white/60">
                        ลิงก์ส่งให้ผู้ใช้แล้วใช่ไหม? เขาต้องเปิดลิงก์แล้วกด “อนุญาตกล้อง”
                      </p>
                    )}
                  </div>
                )
              }
              pip={
                <video
                  ref={selfVideoRef}
                  autoPlay
                  playsInline
                  muted
                  className="aspect-video w-full -scale-x-100 object-cover"
                />
              }
            >
              <CallToolbar
                tool={tool}
                onToolChange={setTool}
                color={color}
                onColorChange={setColor}
                width={width}
                onWidthChange={setWidth}
                onUndo={undo}
                onClear={clearAll}
                canUndo={strokes.length > 0}
                frozen={frozen}
                onToggleFreeze={toggleFreeze}
                canFreeze={status === "connected"}
                micOn={micOn}
                onToggleMic={() => {
                  toggleTrack("audio", !micOn);
                  setMicOn(!micOn);
                }}
                camOn={camOn}
                onToggleCam={() => {
                  toggleTrack("video", !camOn);
                  setCamOn(!camOn);
                }}
                onHangUp={() => closeRoom(active.code)}
              />
            </VideoStage>

            <p className="text-muted-foreground text-xs">
              เคล็ดลับ: กดปุ่ม <Snowflake className="inline size-3.5" /> เพื่อ “หยุดภาพ”
              ก่อนวาด ผู้ใช้จะเห็นภาพนิ่งใบเดียวกับเรา วงกลมที่วาดจะไม่เลื่อนตามมือที่สั่น
            </p>
          </>
        )}

        <Card>
          <CardHeader>
            <CardTitle className="text-base">ห้องล่าสุด</CardTitle>
          </CardHeader>
          <CardContent>
            {sessions.length === 0 ? (
              <p className="text-muted-foreground text-sm">ยังไม่เคยเปิดห้องช่วยเหลือ</p>
            ) : (
              <ul className="divide-y">
                {sessions.map((session) => {
                  const badge = SESSION_BADGE[session.status] || SESSION_BADGE.ended;
                  return (
                    <li key={session.code} className="flex flex-wrap items-center gap-2 py-2.5">
                      <span className={`rounded-full px-2 py-0.5 text-xs font-medium ${badge.className}`}>
                        {badge.label}
                      </span>
                      <span className="min-w-0 flex-1 truncate text-sm">
                        {session.title || "ไม่ได้ตั้งชื่อเรื่อง"}
                        {session.guest_label ? ` — ${session.guest_label}` : ""}
                      </span>
                      {session.status !== "ended" && (
                        <>
                          <Button
                            size="sm"
                            variant={active?.code === session.code ? "secondary" : "outline"}
                            onClick={() => setActive(session)}
                            disabled={active?.code === session.code}
                          >
                            {active?.code === session.code ? "กำลังเปิด" : "เข้าห้อง"}
                          </Button>
                          <Button size="sm" variant="ghost" onClick={() => closeRoom(session.code)}>
                            ปิด
                          </Button>
                        </>
                      )}
                    </li>
                  );
                })}
              </ul>
            )}
          </CardContent>
        </Card>
      </div>
    </AppLayout>
  );
}

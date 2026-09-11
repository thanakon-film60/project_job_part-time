import React, { useCallback, useEffect, useRef, useState } from "react";
import { useParams } from "react-router-dom";
import { toast } from "sonner";
import {
  Camera,
  CircleCheck,
  Loader2,
  Mic,
  MicOff,
  MonitorUp,
  PhoneOff,
  ShieldCheck,
  SwitchCamera,
  Video,
  VideoOff,
} from "lucide-react";
import VideoStage from "@/components/support/VideoStage.jsx";
import { Button } from "@/components/ui/button";
import { applyAnnotationMessage } from "@/lib/annotations";
import { createSupportCall, isMediaSupported, requestMedia, stopStream } from "@/lib/support-call";
import { getSupportGuestInfo } from "../api";
import { cn } from "@/lib/utils";

const STATUS_TEXT = {
  connecting: ["กำลังเชื่อมต่อ...", "wait"],
  waiting: ["รอผู้ช่วยเข้าห้อง...", "wait"],
  calling: ["กำลังต่อสาย...", "wait"],
  connected: ["คุยกันได้แล้ว", "live"],
  reconnecting: ["สัญญาณหลุด กำลังต่อใหม่...", "bad"],
  failed: ["เชื่อมต่อไม่สำเร็จ", "bad"],
  closed: ["จบการช่วยเหลือแล้ว", "bad"],
};

function RoundButton({ label, onClick, active = true, tone = "default", children }) {
  return (
    <button
      type="button"
      title={label}
      aria-label={label}
      onClick={onClick}
      className={cn(
        "inline-flex size-12 items-center justify-center rounded-full border backdrop-blur transition-colors [&_svg]:size-5",
        tone === "danger"
          ? "border-red-400/40 bg-red-500 text-white hover:bg-red-600"
          : active
            ? "border-white/25 bg-white/15 text-white hover:bg-white/30"
            : "border-white/30 bg-white text-slate-900",
      )}
    >
      {children}
    </button>
  );
}

export default function RemoteHelpPage() {
  const { code } = useParams();

  const [info, setInfo] = useState(null);
  const [loadError, setLoadError] = useState("");
  const [joined, setJoined] = useState(false);
  const [granting, setGranting] = useState(false);
  const [status, setStatus] = useState("connecting");
  const [statusDetail, setStatusDetail] = useState("");
  const [strokes, setStrokes] = useState([]);
  const [frozen, setFrozen] = useState(null);
  const [micOn, setMicOn] = useState(true);
  const [camOn, setCamOn] = useState(true);
  const [sharing, setSharing] = useState(false);

  const callRef = useRef(null);
  const audioTrackRef = useRef(null);
  const videoTrackRef = useRef(null);
  const streamRef = useRef(null);
  const facingRef = useRef("environment");

  const selfVideoRef = useRef(null);
  const helperVideoRef = useRef(null);
  const frozenImageRef = useRef(null);

  useEffect(() => {
    let cancelled = false;
    getSupportGuestInfo(code)
      .then((data) => !cancelled && setInfo(data))
      .catch(() => !cancelled && setLoadError("ลิงก์นี้ใช้ไม่ได้แล้ว กรุณาขอลิงก์ใหม่จากผู้ช่วย"));
    return () => {
      cancelled = true;
    };
  }, [code]);

  // วางสายเมื่อออกจากหน้า — ไฟกล้องต้องดับจริง ไม่ใช่แค่ปิดแท็บแล้วยังติดอยู่
  useEffect(
    () => () => {
      callRef.current?.close();
      stopStream(streamRef.current);
      audioTrackRef.current?.stop();
      videoTrackRef.current?.stop();
    },
    [],
  );

  /** รวมไมค์กับกล้องปัจจุบันเป็นสายเดียว แล้วส่งเข้าสายที่ต่ออยู่
   *
   * ใช้ replaceTrack ข้างใน จึงสลับกล้องหน้า/หลังหรือแชร์หน้าจอได้โดยไม่ต้องต่อสายใหม่
   * (ถ้าต่อใหม่ ภาพจะดำไปสองสามวินาทีทุกครั้งที่สลับ)
   */
  const applyTracks = useCallback(() => {
    const stream = new MediaStream(
      [audioTrackRef.current, videoTrackRef.current].filter(Boolean),
    );
    streamRef.current = stream;
    callRef.current?.setLocalStream(stream);
    const video = selfVideoRef.current;
    if (video) {
      video.srcObject = stream;
      video.play().catch(() => {});
    }
  }, []);

  // ต่อภาพเข้ากับ <video> อีกครั้งหลัง React วาดหน้าจอสายจริงเสร็จ
  // ตอนกดอนุญาต element ตัวนี้ยังไม่มีในหน้า (setJoined เพิ่งถูกสั่ง ยังไม่ commit)
  // ถ้าไม่ทำตรงนี้ ผู้ใช้จะเห็นจอดำทั้งที่ไฟกล้องติดและอีกฝั่งเห็นภาพปกติ
  useEffect(() => {
    if (joined) applyTracks();
  }, [joined, applyTracks]);

  function swapVideoTrack(track) {
    videoTrackRef.current?.stop();
    videoTrackRef.current = track || null;
    applyTracks();
  }

  const handleMessage = useCallback((message) => {
    switch (message.type) {
      case "freeze":
        setFrozen(message.image || null);
        setStrokes([]);
        break;
      case "unfreeze":
        setFrozen(null);
        setStrokes([]);
        break;
      case "chat":
        if (message.text) toast.info(message.text);
        break;
      default:
        setStrokes((prev) => applyAnnotationMessage(prev, message));
    }
  }, []);

  async function grantAccess() {
    setGranting(true);
    try {
      const stream = await requestMedia({
        // กล้องหลังก่อน เพราะผู้ใช้ต้องส่องอุปกรณ์ที่มีปัญหาให้ดู ไม่ใช่ถ่ายหน้าตัวเอง
        video: { facingMode: { ideal: "environment" } },
        audio: true,
      });
      audioTrackRef.current = stream.getAudioTracks()[0] || null;
      videoTrackRef.current = stream.getVideoTracks()[0] || null;
      setJoined(true);

      const call = createSupportCall({
        code,
        role: "guest",
        handlers: {
          onStatus: (next, detail) => {
            setStatus(next);
            setStatusDetail(detail || "");
          },
          onRemoteStream: (remote) => {
            const video = helperVideoRef.current;
            if (!video || video.srcObject === remote) return;
            video.srcObject = remote;
            video.play().catch(() => {});
          },
          onPeerLeft: () => {
            setStrokes([]);
            setFrozen(null);
          },
          onMessage: handleMessage,
          onError: (error) => console.warn("[support]", error),
        },
      });
      callRef.current = call;
      applyTracks();
    } catch (error) {
      toast.error(String(error.message || error));
    } finally {
      setGranting(false);
    }
  }

  async function switchCamera() {
    const next = facingRef.current === "environment" ? "user" : "environment";
    try {
      const stream = await requestMedia({ video: { facingMode: { ideal: next } } });
      facingRef.current = next;
      setSharing(false);
      swapVideoTrack(stream.getVideoTracks()[0]);
      setCamOn(true);
    } catch (error) {
      toast.error(String(error.message || error));
    }
  }

  async function shareScreen() {
    if (!navigator.mediaDevices?.getDisplayMedia) {
      toast.error("อุปกรณ์นี้แชร์หน้าจอไม่ได้ ใช้กล้องส่องแทนได้");
      return;
    }
    try {
      const display = await navigator.mediaDevices.getDisplayMedia({ video: true });
      const track = display.getVideoTracks()[0];
      // กดหยุดแชร์จากแถบของเบราว์เซอร์ ต้องกลับไปกล้องเอง ไม่ใช่ปล่อยให้ภาพดับ
      track.addEventListener("ended", () => {
        setSharing(false);
        switchCameraTo(facingRef.current);
      });
      setSharing(true);
      setCamOn(true);
      swapVideoTrack(track);
    } catch {
      /* ผู้ใช้กดยกเลิกหน้าต่างเลือกหน้าจอ — ไม่ใช่ข้อผิดพลาด */
    }
  }

  async function switchCameraTo(facing) {
    try {
      const stream = await requestMedia({ video: { facingMode: { ideal: facing } } });
      swapVideoTrack(stream.getVideoTracks()[0]);
    } catch {
      swapVideoTrack(null);
    }
  }

  function toggleMic() {
    const track = audioTrackRef.current;
    if (!track) return;
    track.enabled = !track.enabled;
    setMicOn(track.enabled);
  }

  function toggleCam() {
    const track = videoTrackRef.current;
    if (!track) return;
    track.enabled = !track.enabled;
    setCamOn(track.enabled);
  }

  function hangUp() {
    callRef.current?.close();
    callRef.current = null;
    stopStream(streamRef.current);
    audioTrackRef.current?.stop();
    videoTrackRef.current?.stop();
    audioTrackRef.current = null;
    videoTrackRef.current = null;
    setJoined(false);
    setStatus("closed");
  }

  // ---------------------------------------------------------------- หน้าจอ
  if (loadError) return <Notice tone="bad" title="เข้าห้องไม่ได้" detail={loadError} />;
  if (!info) {
    return (
      <Notice
        title="กำลังเปิดห้อง..."
        detail="รอสักครู่"
        icon={<Loader2 className="size-10 animate-spin" />}
      />
    );
  }
  if (!info.joinable) {
    return <Notice tone="bad" title="เข้าห้องไม่ได้" detail={info.reason || "ลิงก์นี้ใช้ไม่ได้แล้ว"} />;
  }
  if (status === "closed" && !joined) {
    return (
      <Notice
        title="จบการช่วยเหลือแล้ว"
        detail="ปิดหน้านี้ได้เลย กล้องและไมโครโฟนถูกปิดเรียบร้อยแล้ว"
        icon={<CircleCheck className="size-10 text-emerald-400" />}
      />
    );
  }

  if (!joined) {
    return (
      <div className="flex min-h-svh items-center justify-center bg-slate-950 p-4 text-white">
        <div className="w-full max-w-md space-y-5 rounded-2xl bg-slate-900 p-6 shadow-xl">
          <div className="space-y-2 text-center">
            <Camera className="mx-auto size-10 text-sky-400" />
            <h1 className="text-xl font-bold">ขออนุญาตเปิดกล้องเพื่อช่วยแก้ปัญหา</h1>
            <p className="text-sm text-white/70">
              <strong className="text-white">{info.host_name}</strong> ขอคุยกับคุณผ่านวิดีโอ
              {info.title ? ` เรื่อง “${info.title}”` : ""}
            </p>
          </div>

          <ul className="space-y-2 rounded-xl bg-white/5 p-4 text-sm text-white/80">
            <li className="flex gap-2">
              <ShieldCheck className="mt-0.5 size-4 shrink-0 text-emerald-400" />
              ภาพและเสียงส่งตรงถึงกันสองฝ่ายเท่านั้น ไม่มีการบันทึกเก็บไว้
            </li>
            <li className="flex gap-2">
              <ShieldCheck className="mt-0.5 size-4 shrink-0 text-emerald-400" />
              ผู้ช่วยจะวาดวงกลมหรือลูกศรบนภาพ เพื่อชี้ว่าต้องกดตรงไหน
            </li>
            <li className="flex gap-2">
              <ShieldCheck className="mt-0.5 size-4 shrink-0 text-emerald-400" />
              คุณกดปิดกล้อง ปิดไมค์ หรือวางสายได้ตลอดเวลา
            </li>
          </ul>

          {!isMediaSupported() && (
            <p className="rounded-lg bg-red-500/15 p-3 text-sm text-red-300">
              เบราว์เซอร์นี้เปิดกล้องไม่ได้ — ต้องเปิดลิงก์ผ่าน https
              ลองเปิดใน Chrome หรือ Safari อีกครั้ง
            </p>
          )}

          <Button
            size="lg"
            className="w-full"
            loading={granting}
            disabled={!isMediaSupported()}
            onClick={grantAccess}
          >
            <Video />
            อนุญาตกล้องและไมโครโฟน
          </Button>
          <p className="text-center text-xs text-white/50">
            ถ้าไม่รู้จักชื่อด้านบน อย่ากดอนุญาต และแจ้งฝ่ายไอทีของบริษัท
          </p>
        </div>
      </div>
    );
  }

  const [statusText, statusTone] = STATUS_TEXT[status] || STATUS_TEXT.connecting;

  return (
    <div className="flex min-h-svh flex-col bg-slate-950">
      <VideoStage
        className="min-h-0 flex-1 rounded-none"
        videoRef={selfVideoRef}
        imageRef={frozenImageRef}
        frozenSrc={frozen}
        muted
        strokes={strokes}
        readOnly
        statusText={statusText}
        statusTone={statusTone}
        placeholder={
          status === "connected" ? null : (
            <div className="space-y-2 text-white/80">
              <Loader2 className="mx-auto size-8 animate-spin" />
              <p className="text-sm">{statusText}</p>
              {statusDetail && <p className="text-xs text-white/60">{statusDetail}</p>}
            </div>
          )
        }
        pip={
          <video
            ref={helperVideoRef}
            autoPlay
            playsInline
            className="aspect-video w-full object-cover"
          />
        }
      />

      <div className="safe-bottom flex items-center justify-center gap-3 bg-slate-900 p-3">
        <RoundButton label={micOn ? "ปิดไมค์" : "เปิดไมค์"} active={micOn} onClick={toggleMic}>
          {micOn ? <Mic /> : <MicOff />}
        </RoundButton>
        <RoundButton label={camOn ? "ปิดกล้อง" : "เปิดกล้อง"} active={camOn} onClick={toggleCam}>
          {camOn ? <Video /> : <VideoOff />}
        </RoundButton>
        <RoundButton label="สลับกล้องหน้า/หลัง" onClick={switchCamera}>
          <SwitchCamera />
        </RoundButton>
        <RoundButton label="แชร์หน้าจอ" active={!sharing} onClick={shareScreen}>
          <MonitorUp />
        </RoundButton>
        <RoundButton label="วางสาย" tone="danger" onClick={hangUp}>
          <PhoneOff />
        </RoundButton>
      </div>
    </div>
  );
}

function Notice({ title, detail, tone = "default", icon }) {
  return (
    <div className="flex min-h-svh items-center justify-center bg-slate-950 p-6 text-center text-white">
      <div className="max-w-sm space-y-3">
        {icon}
        <h1 className={cn("text-lg font-bold", tone === "bad" && "text-red-400")}>{title}</h1>
        <p className="text-sm text-white/70">{detail}</p>
      </div>
    </div>
  );
}

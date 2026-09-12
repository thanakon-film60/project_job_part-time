// ตัวจัดการสายวิดีโอของห้องช่วยเหลือระยะไกล — ใช้ร่วมกันทั้งฝั่งผู้ช่วยและฝั่งผู้ใช้
//
// ภาพ/เสียงวิ่งตรงระหว่างเบราว์เซอร์สองฝั่งด้วย WebRTC (ไม่ผ่านเซิร์ฟเวอร์)
// ส่วน WebSocket ที่ backend ใช้ส่งแค่ "คำนัดพบ" (SDP/ICE) กับเส้นที่ผู้ช่วยวาด
//
// ⚠️ WebRTC ใช้ได้เฉพาะหน้าเว็บที่เป็น https หรือ localhost เท่านั้น
//    เปิดผ่าน http://<ไอพี> เบราว์เซอร์จะไม่ยอมให้เข้าถึงกล้องเลย

const BASE = import.meta.env.VITE_API_BASE ?? "";

const FALLBACK_ICE = [{ urls: ["stun:stun.l.google.com:19302"] }];

// รหัสปิดสายจาก backend (ดู CLOSE_* ใน app/routers/support.py) — ต่อใหม่ไม่ช่วยอะไร
export const FATAL_CLOSE_REASONS = {
  4400: "คำขอเข้าห้องไม่ถูกต้อง",
  4401: "ไม่มีสิทธิ์เข้าห้องนี้ กรุณาเข้าสู่ระบบใหม่",
  4404: "ไม่พบห้องช่วยเหลือนี้",
  4409: "ห้องนี้ถูกเปิดจากอุปกรณ์อื่นแล้ว",
  4410: "ห้องนี้ปิดหรือหมดอายุแล้ว",
};

function socketUrl(code, role, token) {
  const origin = BASE.startsWith("http") ? BASE : window.location.origin;
  const url = new URL(`/support/ws/${encodeURIComponent(code)}`, origin);
  url.protocol = url.protocol === "https:" ? "wss:" : "ws:";
  url.searchParams.set("role", role);
  if (token) url.searchParams.set("token", token);
  return url.toString();
}

async function loadIceServers() {
  try {
    const res = await fetch(`${BASE}/support/ice-servers`, {
      headers: { "ngrok-skip-browser-warning": "true" },
    });
    if (!res.ok) return FALLBACK_ICE;
    const data = await res.json();
    return data.ice_servers?.length ? data.ice_servers : FALLBACK_ICE;
  } catch {
    return FALLBACK_ICE;
  }
}

/** เปิดสายหนึ่งสาย
 *
 * สถานะที่ส่งกลับทาง onStatus:
 *   connecting   กำลังต่อ WebSocket
 *   waiting      ต่อแล้วแต่ยังไม่มีอีกฝ่ายในห้อง
 *   calling      อีกฝ่ายเข้ามาแล้ว กำลังจับมือกัน
 *   connected    เห็นภาพกันแล้ว
 *   reconnecting สายหลุดชั่วคราว กำลังต่อใหม่
 *   failed       ต่อไม่ได้/ถูกปฏิเสธ (ดู error ที่ส่งมาด้วย)
 *   ended        ห้องถูกปิดจากอีกฝั่ง — จบแล้วจริง ๆ ต่อใหม่ไม่ได้
 *   closed       ปิดเอง
 */
export function createSupportCall({ code, role, token = "", handlers = {} }) {
  const polite = role === "guest"; // ผู้ช่วยเป็นฝ่ายยื่นข้อเสนอ ผู้ใช้เป็นฝ่ายยอมถอยเมื่อชนกัน

  let ws = null;
  let pc = null;
  let pcSetup = null;
  let remoteStream = null;
  let localStream = null;
  let senders = { audio: null, video: null };
  let pendingIce = [];
  let makingOffer = false;
  let ignoreOffer = false;
  let peerOnline = false;
  let disposed = false;
  let retries = 0;
  let retryTimer = null;
  let heartbeat = null;
  let status = "connecting";

  function setStatus(next, detail) {
    if (disposed || status === next) return;
    status = next;
    handlers.onStatus?.(next, detail);
  }

  function send(message) {
    if (ws?.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify(message));
      return true;
    }
    return false;
  }

  // ------------------------------------------------------------ สื่อของเราเอง
  function bindSenders() {
    // จับคู่ sender ที่มีอยู่แล้วกับชนิดสื่อ — ตั้งใจไม่ addTrack เพิ่มทีหลัง
    // เพราะการเพิ่ม track ใหม่บังคับให้เจรจา SDP กันใหม่ทุกครั้ง
    // สลับกล้องหน้า/หลังหรือแชร์หน้าจอจึงใช้ replaceTrack แทน ภาพไม่สะดุด
    for (const transceiver of pc.getTransceivers()) {
      const kind = transceiver.receiver?.track?.kind || transceiver.sender?.track?.kind;
      if (kind && !senders[kind]) {
        senders[kind] = transceiver.sender;
        try {
          transceiver.direction = "sendrecv";
        } catch {
          /* เบราว์เซอร์เก่าบางตัวตั้งไม่ได้ ปล่อยให้ใช้ค่าที่เจรจามา */
        }
      }
    }
    applyLocalTracks();
  }

  function applyLocalTracks() {
    for (const kind of ["audio", "video"]) {
      const sender = senders[kind];
      if (!sender) continue;
      const track = localStream?.getTracks().find((t) => t.kind === kind) || null;
      if (sender.track !== track) sender.replaceTrack(track).catch(() => {});
    }
  }

  // ข้อความหลายอันมาถึงพร้อมกันได้ (offer แล้ว ice ตามติด) — ล็อกไว้ให้สร้างตัวเดียว
  function ensurePeerConnection() {
    if (!pcSetup) pcSetup = buildPeerConnection();
    return pcSetup;
  }

  async function buildPeerConnection() {
    if (pc) return pc;
    pc = new RTCPeerConnection({ iceServers: await loadIceServers() });

    pc.onicecandidate = (event) => {
      if (event.candidate) send({ type: "ice", candidate: event.candidate.toJSON() });
    };
    pc.ontrack = (event) => {
      // ⚠️ event.streams เป็นอาเรย์ว่างได้ และเป็นแบบนั้น "เกือบตลอด" ในฟีเจอร์นี้
      //
      // เราส่งสื่อด้วย replaceTrack บน transceiver ที่เปิดไว้ล่วงหน้า (เพื่อให้สลับ
      // กล้องหน้า/หลังได้โดยไม่ต้องเจรจา SDP ใหม่) แต่ replaceTrack ไม่ผูก track
      // เข้ากับ MediaStream ไหนเลย SDP จึงไม่มี msid ติดไปด้วย
      // ฝั่งรับเลยได้ event.streams = [] — ถ้าเชื่อค่านั้นตรง ๆ แล้วข้ามไป
      // จะกลายเป็น "ต่อสายติดแต่จอดำทั้งสองฝั่ง" ซึ่งไล่หาสาเหตุยากมาก
      const [stream] = event.streams;
      if (stream) {
        remoteStream = stream;
      } else {
        if (!remoteStream) remoteStream = new MediaStream();
        remoteStream.addTrack(event.track);
      }
      handlers.onRemoteStream?.(remoteStream);
    };
    pc.onconnectionstatechange = () => {
      if (pc?.connectionState === "connected") setStatus("connected");
      else if (pc?.connectionState === "failed") {
        // ต่อตรงไม่ได้จริง ๆ — ส่วนใหญ่คือเน็ตฝั่งใดฝั่งหนึ่งบล็อก UDP ต้องใช้ TURN
        setStatus("failed", "ต่อสายไม่สำเร็จ (เน็ตอาจบล็อกอยู่ — ดูเรื่อง TURN ใน .env.example)");
      }
    };
    pc.onnegotiationneeded = async () => {
      if (role !== "host") {
        send({ type: "renegotiate" }); // ให้ฝั่งผู้ช่วยเป็นคนยื่นข้อเสนอเสมอ
        return;
      }
      await makeOffer();
    };

    if (role === "host") {
      // ผู้ช่วยเปิดช่องเสียง+ภาพไว้ล่วงหน้า ทั้งที่อาจยังไม่มีกล้อง
      // จะได้รับภาพจากผู้ใช้ได้แม้ตัวเองไม่มีกล้องเลย
      pc.addTransceiver("audio", { direction: "sendrecv" });
      pc.addTransceiver("video", { direction: "sendrecv" });
      bindSenders();
    }
    return pc;
  }

  function teardownPeerConnection() {
    if (!pc) return;
    try {
      pc.ontrack = null;
      pc.onicecandidate = null;
      pc.onnegotiationneeded = null;
      pc.onconnectionstatechange = null;
      pc.close();
    } catch {
      /* ปิดไปแล้วก็ไม่เป็นไร */
    }
    pc = null;
    pcSetup = null;
    remoteStream = null;
    senders = { audio: null, video: null };
    pendingIce = [];
  }

  // ------------------------------------------------------------ การเจรจา
  async function makeOffer() {
    if (!pc) return;
    try {
      makingOffer = true;
      const offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      send({ type: "offer", sdp: pc.localDescription });
    } catch (error) {
      handlers.onError?.(error);
    } finally {
      makingOffer = false;
    }
  }

  async function handleDescription(description) {
    if (!description) return;
    await ensurePeerConnection();

    const collision =
      description.type === "offer" && (makingOffer || pc.signalingState !== "stable");
    ignoreOffer = !polite && collision;
    if (ignoreOffer) return;

    if (collision) await pc.setRemoteDescription({ type: "rollback" });
    await pc.setRemoteDescription(description);

    if (description.type === "offer") {
      bindSenders(); // ตอนนี้ transceiver ครบแล้ว ค่อยยัดกล้อง/ไมค์ของเราเข้าไป
      const answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      send({ type: "answer", sdp: pc.localDescription });
    }

    for (const candidate of pendingIce.splice(0)) {
      await pc.addIceCandidate(candidate).catch(() => {});
    }
  }

  async function handleIce(candidate) {
    if (!candidate) return;
    // ICE มาถึงก่อน SDP ได้เป็นเรื่องปกติ — พักไว้ก่อนแล้วค่อยใส่ทีหลัง
    if (!pc || !pc.remoteDescription) {
      pendingIce.push(candidate);
      return;
    }
    try {
      await pc.addIceCandidate(candidate);
    } catch (error) {
      if (!ignoreOffer) handlers.onError?.(error);
    }
  }

  async function startCallIfHost() {
    if (role !== "host") return;
    await ensurePeerConnection();
    await makeOffer();
  }

  // ------------------------------------------------------------ WebSocket
  async function handleMessage(message) {
    switch (message.type) {
      case "ready":
        peerOnline = Boolean(message.peer_online);
        handlers.onHostName?.(message.host_name || "");
        setStatus(peerOnline ? "calling" : "waiting");
        if (peerOnline) await startCallIfHost();
        break;

      case "peer":
        if (message.state === "joined") {
          peerOnline = true;
          setStatus("calling");
          teardownPeerConnection(); // อีกฝั่งเพิ่งเปิดใหม่ ต้องจับมือกันใหม่ทั้งชุด
          await startCallIfHost();
        } else {
          peerOnline = false;
          teardownPeerConnection();
          setStatus("waiting");
          handlers.onPeerLeft?.();
        }
        break;

      case "offer":
      case "answer":
        await handleDescription(message.sdp);
        break;

      case "ice":
        await handleIce(message.candidate);
        break;

      case "renegotiate":
        if (role === "host" && pc) await makeOffer();
        break;

      // ⚠️ ต้องแจ้งสถานะ "ก่อน" ตั้ง disposed เพราะ setStatus จะเงียบทันทีที่ disposed
      // เป็น true — เคยสลับลำดับกันแล้วฝั่งผู้ใช้ไม่รู้เลยว่าห้องปิดไปแล้ว
      // หน้าจอค้างเหมือนยังคุยกันอยู่ทั้งที่สายตายแล้ว และกล้องยังเปิดค้าง
      case "ended":
        teardownPeerConnection();
        setStatus("ended", "ห้องนี้ถูกปิดแล้ว");
        disposed = true;
        break;

      case "replaced":
        teardownPeerConnection();
        setStatus("ended", FATAL_CLOSE_REASONS[4409]);
        disposed = true;
        break;

      case "pong":
        break;

      default:
        // เส้นที่วาด / ภาพที่หยุดไว้ / ข้อความแชท — ให้หน้าเว็บจัดการเอง
        handlers.onMessage?.(message);
    }
  }

  let queue = Promise.resolve();

  function connect() {
    if (disposed) return;
    ws = new WebSocket(socketUrl(code, role, token));

    ws.onopen = () => {
      retries = 0;
      setStatus("connecting");
      clearInterval(heartbeat);
      // กัน reverse proxy ตัดสายตอนที่ไม่มีใครพิมพ์/วาดอะไรนาน ๆ
      heartbeat = setInterval(() => send({ type: "ping" }), 25000);
    };

    ws.onmessage = (event) => {
      let message;
      try {
        message = JSON.parse(event.data);
      } catch {
        return;
      }
      // ต่อท้ายคิวเสมอ — ถ้าปล่อยให้ทำงานคู่ขนาน ice อาจถูกใส่ก่อน setRemoteDescription
      // เสร็จ แล้วสายจะค้างอยู่ที่ "กำลังจับมือ" โดยไม่มี error ให้เห็น
      queue = queue
        .then(() => handleMessage(message))
        .catch((error) => handlers.onError?.(error));
    };

    ws.onclose = (event) => {
      clearInterval(heartbeat);
      if (disposed) return;
      const fatal = FATAL_CLOSE_REASONS[event.code];
      if (fatal) {
        disposed = true;
        teardownPeerConnection();
        setStatus("failed", fatal);
        return;
      }
      setStatus("reconnecting");
      retries += 1;
      retryTimer = setTimeout(connect, Math.min(1000 * 2 ** retries, 10000));
    };
  }

  connect();

  return {
    send,
    getStatus: () => status,
    isPeerOnline: () => peerOnline,

    /** เปลี่ยนกล้อง/ไมค์ที่ส่งออกไป โดยไม่ต้องจับมือกันใหม่ */
    setLocalStream(stream) {
      localStream = stream;
      if (pc) applyLocalTracks();
    },

    close() {
      disposed = true;
      clearInterval(heartbeat);
      clearTimeout(retryTimer);
      send({ type: "hangup" });
      teardownPeerConnection();
      try {
        ws?.close();
      } catch {
        /* ปิดไปแล้วก็ไม่เป็นไร */
      }
      ws = null;
      status = "closed";
    },
  };
}

export function isMediaSupported() {
  return Boolean(navigator.mediaDevices?.getUserMedia);
}

/** ขอกล้อง/ไมค์ พร้อมข้อความไทยที่บอกสาเหตุจริงว่าทำไมไม่ได้
 *
 * เคสที่เจอบ่อยที่สุดคือเปิดหน้าเว็บผ่าน http ธรรมดา แล้ว navigator.mediaDevices
 * หายไปทั้งก้อน ซึ่งถ้าไม่ดักไว้ผู้ใช้จะเห็นแค่ "undefined" แล้วงงว่าต้องทำอะไรต่อ
 */
export async function requestMedia(constraints) {
  if (!isMediaSupported()) {
    throw new Error("เบราว์เซอร์นี้เปิดกล้องไม่ได้ — ต้องเปิดหน้าเว็บผ่าน https");
  }
  try {
    return await navigator.mediaDevices.getUserMedia(constraints);
  } catch (error) {
    if (error?.name === "NotAllowedError") {
      throw new Error("คุณกดไม่อนุญาตไว้ — กดรูปกล้องบนแถบที่อยู่เว็บเพื่ออนุญาตใหม่");
    }
    if (error?.name === "NotFoundError" || error?.name === "OverconstrainedError") {
      throw new Error("ไม่พบกล้องหรือไมโครโฟนบนเครื่องนี้");
    }
    if (error?.name === "NotReadableError") {
      throw new Error("กล้องถูกโปรแกรมอื่นใช้อยู่ กรุณาปิดโปรแกรมนั้นก่อน");
    }
    throw error;
  }
}

/** ปิดกล้อง/ไมค์ให้เรียบร้อย — ไฟกล้องต้องดับจริงเมื่อวางสาย */
export function stopStream(stream) {
  stream?.getTracks().forEach((track) => track.stop());
}

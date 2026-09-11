import React, { useCallback, useEffect, useRef, useState } from "react";
import { useLocation } from "react-router-dom";
import { ArrowLeft, ChevronDown, Crown, LoaderCircle, MessageCircle, Search, Send, User } from "lucide-react";
import { getEmployee, getChatContacts, getChatMessages, readChatMessages, sendChatMessage } from "@/api";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";

const thaiDate = new Intl.DateTimeFormat("th-TH", { timeZone: "Asia/Bangkok", day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" });
const mergeMessages = (old, incoming) => [...new Map([...old, ...incoming].map((message) => [message.id, message])).values()].sort((a, b) => a.id - b.id);

function Conversation({ me, peer, active, draft, setDraft, onRead }) {
  const [messages, setMessages] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [sendError, setSendError] = useState("");
  const [sending, setSending] = useState(false);
  const [older, setOlder] = useState(false);
  const [loadingOlder, setLoadingOlder] = useState(false);
  const [peerRead, setPeerRead] = useState(0);
  const [atBottom, setAtBottom] = useState(true);
  const [revision, setRevision] = useState(0);
  const list = useRef(null);
  const latest = useRef(0);
  const readThrough = useRef(0);
  const inFlight = useRef(false);
  const attempt = useRef(null);
  const alive = useRef(true);
  const nearBottom = useRef(true);
  const input = useRef(null);
  useEffect(() => { alive.current = true; return () => { alive.current = false; }; }, []);

  useEffect(() => {
    if (!active) return;
    let stopped = false, timer, busy = false;
    const controller = new AbortController();
    async function poll() {
      if (stopped || busy || document.visibilityState !== "visible") return;
      busy = true;
      let catchUp = false;
      try {
        const first = latest.current === 0;
        const data = await getChatMessages(peer.id, first ? {} : { after_id: latest.current, limit: 100 }, controller.signal);
        if (stopped) return;
        if (first) setOlder(data.has_more);
        else catchUp = data.has_more;
        latest.current = Math.max(latest.current, ...data.messages.map((message) => message.id));
        setMessages((previous) => mergeMessages(previous, data.messages));
        setPeerRead(data.peer_read_through_id);
        setError("");
      } catch (err) {
        if (!stopped && err.name !== "AbortError") setError("เชื่อมต่อแชทไม่สำเร็จ กำลังลองเชื่อมต่อใหม่");
      } finally {
        busy = false;
        if (!stopped) { setLoading(false); clearTimeout(timer); timer = setTimeout(poll, catchUp ? 50 : 3000); }
      }
    }
    const wake = () => { if (document.visibilityState === "visible") { clearTimeout(timer); poll(); } };
    poll();
    document.addEventListener("visibilitychange", wake);
    return () => { stopped = true; clearTimeout(timer); controller.abort(); document.removeEventListener("visibilitychange", wake); };
  }, [peer.id, active, revision]);

  useEffect(() => {
    if (active && nearBottom.current && list.current) list.current.scrollTop = list.current.scrollHeight;
  }, [messages, active]);

  useEffect(() => {
    if (!active || !atBottom || document.visibilityState !== "visible") return;
    const incoming = messages.filter((message) => message.sender_id === peer.id && !message.read_at);
    const through = Math.max(0, ...incoming.map((message) => message.id));
    if (!through || through <= readThrough.current) return;
    let stopped = false;
    readChatMessages(peer.id, through).then(() => {
      if (stopped) return;
      readThrough.current = through;
      onRead();
    }).catch(() => {}); // The next poll retries; never claim read until the server accepts it.
    return () => { stopped = true; };
  }, [messages, active, atBottom, peer.id, onRead]);

  async function loadOlder() {
    if (loadingOlder || !messages.length) return;
    setLoadingOlder(true);
    const height = list.current?.scrollHeight ?? 0;
    const top = list.current?.scrollTop ?? 0;
    nearBottom.current = false;
    setAtBottom(false);
    try {
      const data = await getChatMessages(peer.id, { before_id: messages[0].id });
      if (!alive.current) return;
      setMessages((previous) => mergeMessages(previous, data.messages));
      setOlder(data.has_more);
      setError("");
      requestAnimationFrame(() => { if (list.current) list.current.scrollTop = top + list.current.scrollHeight - height; });
    } catch { if (alive.current) setError("โหลดข้อความก่อนหน้าไม่สำเร็จ กรุณาลองอีกครั้ง"); }
    finally { if (alive.current) setLoadingOlder(false); }
  }

  async function submit(event) {
    event.preventDefault();
    const body = draft.trim();
    if (!body || body.length > 2000 || inFlight.current) return;
    inFlight.current = true;
    setSending(true); setSendError("");
    if (attempt.current?.body !== body) attempt.current = { body, client_id: crypto.randomUUID() };
    try {
      const message = await sendChatMessage(peer.id, attempt.current);
      if (!alive.current) return;
      nearBottom.current = true; setAtBottom(true);
      setMessages((previous) => mergeMessages(previous, [message]));
      // Keep the receive cursor at the last polled message so simultaneous replies are not skipped.
      setDraft((current) => current.trim() === body ? "" : current);
      attempt.current = null;
      onRead();
      input.current?.focus();
    } catch { if (alive.current) setSendError("ส่งไม่สำเร็จ ข้อความยังอยู่ กดส่งเพื่อลองอีกครั้ง"); }
    finally { inFlight.current = false; if (alive.current) setSending(false); }
  }

  return <>
    <div ref={list} role="log" aria-label={`ข้อความกับ ${peer.full_name}`} aria-live="polite"
      onScroll={() => { const el = list.current; nearBottom.current = el.scrollHeight - el.scrollTop - el.clientHeight < 48; setAtBottom(nearBottom.current); }}
      className="min-h-0 flex-1 overflow-y-auto overscroll-contain bg-muted/30 p-3">
      {older && <Button variant="ghost" size="sm" className="mb-3 w-full" disabled={loadingOlder} onClick={loadOlder}>{loadingOlder ? "กำลังโหลด…" : "ข้อความก่อนหน้า"}</Button>}
      {loading && <p className="py-8 text-center text-sm text-muted-foreground">กำลังโหลดข้อความ…</p>}
      {!loading && !messages.length && !error && <div className="py-10 text-center text-sm text-muted-foreground"><MessageCircle className="mx-auto mb-2 size-8 opacity-50" />เริ่มคุยกับ {peer.full_name}<p className="mt-1 text-xs">บทสนทนานี้เห็นเฉพาะคุณกับผู้รับ</p></div>}
      <div className="space-y-3">{messages.map((message) => {
        const mine = message.sender_id === me.id;
        return <div key={message.id} className={cn("flex flex-col", mine ? "items-end" : "items-start")}>
          <p className={cn("max-w-[88%] whitespace-pre-wrap break-words rounded-2xl px-3 py-2 text-sm [overflow-wrap:anywhere]", mine ? "rounded-br-sm bg-primary text-primary-foreground" : "rounded-bl-sm border bg-card text-card-foreground")}>{message.body}</p>
          <span className="mt-1 text-[10px] text-muted-foreground">{thaiDate.format(new Date(message.created_at))}{mine && (message.read_at || message.id <= peerRead ? " · อ่านแล้ว" : " · ส่งแล้ว")}</span>
        </div>;
      })}</div>
    </div>
    {!atBottom && <button type="button" className="border-t bg-primary/10 py-1.5 text-xs text-primary" onClick={() => { nearBottom.current = true; setAtBottom(true); list.current.scrollTop = list.current.scrollHeight; }}>ไปข้อความล่าสุด ↓</button>}
    {error && <div role="status" className="border-t px-3 py-2 text-xs text-destructive">{error} <button type="button" className="underline" onClick={() => setRevision((value) => value + 1)}>ลองใหม่</button></div>}
    <form onSubmit={submit} className="space-y-2 border-t bg-card p-3">
      {sendError && <p role="alert" className="text-xs text-destructive">{sendError}</p>}
      <div className="flex items-end gap-2">
        <textarea ref={input} aria-label="พิมพ์ข้อความ" placeholder="พิมพ์ข้อความ…" rows={2} maxLength={2000}
          value={draft} onChange={(event) => setDraft(event.target.value)}
          onKeyDown={(event) => { if (event.key === "Enter" && !event.shiftKey && !event.nativeEvent.isComposing) submit(event); }}
          className="max-h-28 min-h-11 min-w-0 flex-1 resize-none rounded-xl border bg-background px-3 py-2 text-sm outline-none focus-visible:ring-2 focus-visible:ring-ring" />
        <Button type="submit" size="icon" aria-label="ส่งข้อความ" disabled={sending || !draft.trim()} className="mb-0.5 shrink-0 rounded-xl">{sending ? <LoaderCircle className="animate-spin" /> : <Send />}</Button>
      </div>
      <div className="flex justify-between text-[10px] text-muted-foreground"><span>Enter ส่ง · Shift+Enter ขึ้นบรรทัดใหม่</span><span>{draft.length}/2000</span></div>
    </form>
  </>;
}

function ChatPanel({ me }) {
  const [open, setOpen] = useState(false);
  const [contacts, setContacts] = useState([]);
  const [peer, setPeer] = useState(null);
  const [search, setSearch] = useState("");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(true);
  const [drafts, setDrafts] = useState({});
  const [revision, setRevision] = useState(0);
  const trigger = useRef(null);
  const refresh = useCallback(() => setRevision((value) => value + 1), []);
  useEffect(() => {
    let stopped = false, timer, busy = false;
    const controller = new AbortController();
    async function poll() {
      if (stopped || busy || document.visibilityState !== "visible") return;
      busy = true;
      try {
        const data = await getChatContacts(controller.signal);
        if (!stopped) { setContacts(data.contacts); setError(""); }
      } catch (err) { if (!stopped && err.name !== "AbortError") setError("โหลดรายชื่อแชทไม่สำเร็จ"); }
      finally { busy = false; if (!stopped) { setLoading(false); clearTimeout(timer); timer = setTimeout(poll, open ? 5000 : 10000); } }
    }
    const wake = () => { clearTimeout(timer); poll(); };
    poll(); document.addEventListener("visibilitychange", wake);
    return () => { stopped = true; controller.abort(); clearTimeout(timer); document.removeEventListener("visibilitychange", wake); };
  }, [open, revision]);
  const unread = contacts.reduce((total, contact) => total + contact.unread_count, 0);
  const visible = contacts.filter((contact) => `${contact.full_name} ${contact.employee_code}`.toLowerCase().includes(search.toLowerCase()));
  const collapse = () => { setOpen(false); trigger.current?.focus(); };
  const setDraft = (value) => setDrafts((previous) => ({ ...previous, [peer.id]: typeof value === "function" ? value(previous[peer.id] ?? "") : value }));
  return <div className="fixed right-3 bottom-[calc(5rem+env(safe-area-inset-bottom))] z-[45] sm:right-5 lg:bottom-5">
    <section id="work-chat" aria-label="แชทหัวหน้าและพนักงาน" hidden={!open}
      onKeyDown={(event) => { if (event.key === "Escape") { event.stopPropagation(); collapse(); } }}
      className={cn("mb-2 h-[min(34rem,calc(100dvh-10rem))] w-[min(24rem,calc(100vw-1.5rem))] flex-col overflow-hidden rounded-2xl border bg-card shadow-2xl lg:h-[min(36rem,calc(100dvh-7rem))]", open ? "flex" : "hidden")}>
      <header className="flex shrink-0 items-center gap-2 border-b bg-primary px-3 py-3 text-primary-foreground">
        {peer ? <button type="button" aria-label="กลับรายชื่อแชท" className="rounded-md p-1 hover:bg-white/15 focus-visible:outline" onClick={() => setPeer(null)}><ArrowLeft className="size-5" /></button> : <MessageCircle className="size-5" />}
        <div className="min-w-0 flex-1"><h2 className="truncate text-sm font-semibold">{peer ? peer.full_name : "แชทที่ทำงาน"}</h2><p className="text-[11px] opacity-80">{peer ? `${peer.is_manager ? "หัวหน้า" : "พนักงาน"} · แชทส่วนตัว` : me.is_manager ? "คุยกับพนักงานของคุณ" : "คุยกับหัวหน้า"}</p></div>
        <button type="button" aria-label="ยุบแชท" className="rounded-md p-1 hover:bg-white/15 focus-visible:outline" onClick={collapse}><ChevronDown className="size-5" /></button>
      </header>
      {peer ? <Conversation key={peer.id} me={me} peer={peer} active={open} draft={drafts[peer.id] ?? ""} setDraft={setDraft} onRead={refresh} /> : <>
        <label className="relative m-3 block"><Search className="absolute top-2.5 left-3 size-4 text-muted-foreground" /><input aria-label="ค้นหาคนในแชท" placeholder="ค้นหาชื่อหรือรหัส…" value={search} onChange={(event) => setSearch(event.target.value)} className="w-full rounded-lg border bg-background py-2 pr-3 pl-9 text-sm outline-none focus-visible:ring-2 focus-visible:ring-ring" /></label>
        {error && <p role="status" className="px-3 pb-2 text-xs text-destructive">{error} <button type="button" className="underline" onClick={refresh}>ลองใหม่</button></p>}
        <div className="min-h-0 flex-1 overflow-y-auto overscroll-contain px-2 pb-2">
          {loading ? <p className="p-4 text-center text-sm text-muted-foreground">กำลังโหลดรายชื่อ…</p> : !visible.length && !error ? <p className="p-4 text-center text-sm text-muted-foreground">{search ? "ไม่พบรายชื่อที่ค้นหา" : me.is_manager ? "ยังไม่มีพนักงานในระบบ" : "ยังไม่มีหัวหน้าในระบบ"}</p> : visible.map((contact) => <button key={contact.id} type="button" onClick={() => setPeer(contact)} className="flex w-full items-center gap-3 rounded-xl p-3 text-left hover:bg-muted focus-visible:outline focus-visible:outline-ring">
            <span className="flex size-10 shrink-0 items-center justify-center rounded-full bg-primary/10 text-primary">{contact.is_manager ? <Crown className="size-5" /> : <User className="size-5" />}</span>
            <span className="min-w-0 flex-1"><span className="block truncate text-sm font-medium">{contact.full_name}</span><span className="block truncate text-xs text-muted-foreground">{contact.last_message ? `${contact.last_message.sender_id === me.id ? "คุณ: " : ""}${contact.last_message.body}` : contact.employee_code}</span></span>
            {contact.unread_count > 0 && <span className="rounded-full bg-primary px-2 py-0.5 text-xs font-semibold text-primary-foreground" aria-label={`ยังไม่อ่าน ${contact.unread_count} ข้อความ`}>{contact.unread_count > 99 ? "99+" : contact.unread_count}</span>}
          </button>)}
        </div>
        <p className="border-t p-3 text-center text-[11px] text-muted-foreground">ข้อความเห็นเฉพาะคุณกับผู้รับ · อัปเดตอัตโนมัติ</p>
      </>}
    </section>
    <div className="flex justify-end"><Button ref={trigger} type="button" aria-expanded={open} aria-controls="work-chat" aria-label={`แชท${unread ? ` มี ${unread} ข้อความที่ยังไม่อ่าน` : ""}`} onClick={() => setOpen((value) => !value)} className="h-12 gap-2 rounded-full px-4 shadow-lg"><MessageCircle className="size-5" /><span>แชท</span>{unread > 0 && <span className="rounded-full bg-destructive px-1.5 text-xs text-white">{unread > 99 ? "99+" : unread}</span>}</Button></div>
  </div>;
}

export default function ChatWidget() {
  useLocation(); // Re-evaluate the session after login/logout; keep the panel across page changes.
  const me = getEmployee();
  return me ? <ChatPanel key={me.id} me={me} /> : null;
}

<!-- gitnexus:start -->
# GitNexus — Code Intelligence

This project is indexed by GitNexus as **project_job_part-time** (4823 symbols, 11230 relationships, 411 execution flows).

> Index stale? Run `node .gitnexus/run.cjs analyze --index-only` from the project root — it auto-selects an available runner. No `.gitnexus/run.cjs` yet? Bootstrap with `npx`, `bunx`, or `pnpm dlx` — e.g. `bunx gitnexus@latest analyze` (npm 11 npx crash; #1939).

## Always Do

- **MUST run impact analysis before editing.** Use `impact({target: "symbolName", direction: "upstream"})` (MCP) or `node .gitnexus/run.cjs impact "symbolName" --direction upstream --repo .` (CLI fallback); report callers, processes, and risk. Never substitute grep for graph analysis.
- **MUST analyze graph changes before committing.** Use `detect_changes({scope: "all"})` (MCP) or `node .gitnexus/run.cjs detect-changes --scope all --repo .` (CLI fallback). `partial: true` or `truncated: true` is not a clean check — a zero means unseen, not unaffected; re-run it. For regression review: `detect_changes({scope: "compare", base_ref: "master"})` or `node .gitnexus/run.cjs detect-changes --scope compare --base-ref "master" --repo .`.
- **MUST warn the user** if impact analysis returns HIGH or CRITICAL risk before proceeding with edits.
- **MUST treat `risk: UNKNOWN` as unresolved, not as low.** An empty caller set is not evidence the symbol is unused — it can also mean the callers are not resolvable by the index (plain-object property access, dynamic dispatch, cross-language calls). `impact` pairs `UNKNOWN` with a `riskNote` saying so. Confirm with a text search before treating the symbol as safe to change or delete; do not proceed on the strength of a zero.
- When exploring unfamiliar code, use `query({search_query: "concept"})` to find execution flows instead of grepping. It returns process-grouped results ranked by relevance.
- When you need full context on a specific symbol — callers, callees, which execution flows it participates in — use `context({name: "symbolName"})`.
- For security review, `explain({target: "fileOrSymbol"})` lists taint findings (source→sink flows; needs `analyze --pdg`).

## Never Do

- NEVER edit a function, class, or method before MCP/CLI impact analysis.
- NEVER ignore HIGH or CRITICAL risk warnings from impact analysis, and never read `UNKNOWN` as an all-clear — it means the walk could not answer, which is the one verdict that requires confirming by other means.
- NEVER rename symbols with find-and-replace — use `rename` which understands the call graph.
- NEVER commit before MCP/CLI graph change analysis.

## Resources

| Resource | Use for |
| --- | --- |
| `gitnexus://repo/project_job_part-time/context` | Codebase overview, check index freshness |
| `gitnexus://repo/project_job_part-time/clusters` | All functional areas |
| `gitnexus://repo/project_job_part-time/processes` | All execution flows |
| `gitnexus://repo/project_job_part-time/process/{name}` | Step-by-step execution trace |

## CLI

| Task | Read this skill file |
| --- | --- |
| Understand architecture / "How does X work?" | `.claude/skills/gitnexus-exploring/SKILL.md` |
| Blast radius / "What breaks if I change X?" | `.claude/skills/gitnexus-impact-analysis/SKILL.md` |
| Trace bugs / "Why is X failing?" | `.claude/skills/gitnexus-debugging/SKILL.md` |
| Rename / extract / split / refactor | `.claude/skills/gitnexus-refactoring/SKILL.md` |
| Tools, resources, schema reference | `.claude/skills/gitnexus-guide/SKILL.md` |
| Index, status, clean, wiki CLI commands | `.claude/skills/gitnexus-cli/SKILL.md` |

<!-- gitnexus:end -->

---

# Project Rules (user-defined — keep outside the gitnexus block)

## Documentation Policy

- **MUST อัปเดตไฟล์ `CLAUDE.md` นี้ทุกครั้งที่มีการทำอะไรกับโปรเจ็ค** — แก้โค้ด เพิ่มฟีเจอร์ แก้บั๊ก เปลี่ยน config ย้าย/ลบไฟล์ ทุกกรณี
  (MUST update this file every time any work is done on this project.)
- บันทึกลงหัวข้อ **Work Log** ด้านล่าง: วันที่ (YYYY-MM-DD), สิ่งที่เปลี่ยน, ไฟล์/ส่วนที่กระทบ, และเหตุผลถ้าไม่ชัดเจนจากโค้ด
- ถือเป็นส่วนหนึ่งของการปิดงาน — ทำเองโดยไม่ต้องรอให้ผู้ใช้สั่ง และไม่ต้องถามก่อนอัปเดต
- ถ้ามีการเปลี่ยนโครงสร้าง/สถาปัตยกรรม ให้สรุปไว้ที่นี่ด้วย ไม่ใช่แค่บรรทัด log
- **แก้ได้เฉพาะใต้เครื่องหมาย `<!-- gitnexus:end -->` เท่านั้น** ทุกอย่างเหนือเส้นนั้น GitNexus generate ใหม่ทุกครั้งที่ re-index แล้วสิ่งที่เขียนไว้จะหาย

## Work Log

<!-- ใหม่สุดอยู่บนสุด / Newest first -->

### 2026-09-12 (ตี 0:30) — deploy ระบบช่วยเหลือระยะไกลขึ้น production + reboot เปิด WebSocket

**สถานะ: ใช้งานได้แล้วทุกส่วนยกเว้นวิดีโอคอล — เหลือรันสคริปต์เดียวเปิดทาง WebSocket**

| ขั้น | สิ่งที่ทำ | ผลตรวจ |
| --- | --- | --- |
| 1 | `pip install -r requirements.txt` ใน venv ของ production | `qrcode` ใช้งานได้ (สร้าง SVG ผ่าน) · `websockets 17.0.1` ครบ |
| 2 | build React + copy ขึ้น `C:\inetpub\checkin` | ทำไปพร้อม commit ฟีเจอร์ "ข้อมูลบริษัท" ตอน 00:18 — ไฟล์ใน IIS ตรงกับ `dist/` (md5 ตรง) |
| 3 | copy `web.config` ตัวใหม่ | กฎ proxy มีทั้ง `payroll` และ `support` แล้ว (md5 ตรงกับ repo) |
| 4 | restart backend (`MardodiCheckinAPI`) | endpoint 45 → **51 เส้น** · `/support/*` ขึ้นครบ 6 เส้น |
| 5 | `dism /online /enable-feature /featurename:IIS-WebSockets` | สำเร็จ แต่สถานะเป็น **Enable Pending** → ต้อง reboot |
| 6 | **ตัดสินใจไม่ reboot** | เจอ Windows Update ค้าง 6 ตัว รวม Cumulative Update ของ OS (KB5122882) และ .NET (KB5126149) — reboot จะลากอัปเดตพวกนี้ลงด้วย กินเวลา 15-45 นาที restart หลายรอบ โดยไม่มีคนเฝ้า |
| 7 | เตรียมทางเลี่ยงที่ไม่ต้อง reboot | `deploy\cloudflare\enable-support-websocket.ps1` — ให้ Cloudflare Tunnel ส่ง `/support/ws/` ตรงไป uvicorn ข้าม IIS |

**ตรวจก่อน reboot**

- `https://thanakronpart-time.com/support/ice-servers` → 200 JSON (ผ่าน Cloudflare + IIS แล้ว)
- `https://thanakronpart-time.com/it-support` → 200 หน้าเว็บ
- WebSocket ตรงไป backend `:8001` → **ต่อติด** (`ready role=guest`)
- WebSocket ผ่าน IIS `:80` → **ไม่ติด** (`InvalidUpgrade: missing Connection header`)
  = IIS ตัด header ทิ้งเพราะยังไม่มี WebSocketModule → ยืนยันว่า reboot จำเป็นจริง
- ห้องทดสอบที่สร้างระหว่างตรวจถูกลบออกจาก DB แล้ว (เหลือ 0 แถวใน `support_sessions`)

**เรื่องการ reboot — เปลี่ยนการตัดสินใจกลางคัน**

ตอนแรกตั้งใจจะ reboot ให้เลย เพราะตี 0:30 คืนเสาร์คือช่วงที่กระทบน้อยที่สุด และตรวจแล้วว่าทุกบริการ
กลับมาเองได้ (`W3SVC` + `Cloudflared` = **Auto**, `MardodiCheckinAPI` = **BootTrigger**)

แต่พอตรวจต่อเจอว่ามี **Windows Update ค้างอยู่ 6 ตัว** รวม Cumulative Update ของ OS กับ .NET
ที่ยังไม่ได้ลง (`CBS RebootPending` = True, `PendingFileRenameOperations` มีค่า) การ reboot จึงไม่ใช่
"ดับ 2 นาทีแล้วกลับมา" แต่อาจกลายเป็นลงอัปเดต 15-45 นาที restart หลายรอบ และถ้าอัปเดตตัวใดพังแล้ว
rollback จะนานกว่านั้นอีก — โดยไม่มีใครตื่นอยู่เฝ้า จึงเปลี่ยนไปใช้ทางที่ย้อนกลับได้ง่ายกว่าแทน

**ทางเลี่ยง: ให้ Cloudflare Tunnel ส่ง WebSocket ตรงไป backend**

`cloudflared` รองรับ WebSocket ในตัวอยู่แล้ว และแยก ingress ตาม path ได้ จึงเพิ่มกฎให้ `/support/ws/`
วิ่งตรงไป `uvicorn :8001` ข้าม IIS ส่วนเส้นทางอื่นทุกเส้นยังผ่าน IIS เหมือนเดิม
ความปลอดภัยไม่ลดลงเพราะ backend ตรวจโทเค็นห้องกับ JWT เองอยู่แล้ว และได้ผลพลอยได้คือเร็วขึ้นด้วย

ตรวจกฎล่วงหน้าด้วย `cloudflared tunnel ingress rule` แล้ว — routing ถูกต้องทุกเส้น:

| URL | ไปที่ |
|---|---|
| `/support/ws/abc123` | `localhost:8001` (backend ตรง) |
| `/support/ice-servers` | `localhost:80` (IIS) |
| `/it-support`, `/checkins/me` | `localhost:80` (IIS) |

**🔴 สิ่งที่ค้นพบระหว่างทาง — สำคัญมาก**

Windows Service `Cloudflared` **ไม่ได้ใช้ `F:\Game\config.yml`** อย่างที่เอกสารเดิมบอก
แต่ใช้ `C:\ProgramData\Cloudflare\cloudflared\config.yml` และไฟล์นั้นชี้ `credentials-file`
ไปคนละพาธด้วย — ถ้าใครก๊อป config จาก repo ทับตรง ๆ tunnel จะหา credentials ไม่เจอแล้วเว็บล่มทั้งระบบ
ใส่หมายเหตุเตือนไว้ใน `deploy/cloudflare/config.yml` แล้ว และสคริปต์อ่านพาธจริงจาก service เอง
ไม่ได้เดาเอา

**ยังไม่ได้ทำ:** ยังไม่ได้รัน `enable-support-websocket.ps1` (harness กันไม่ให้แก้ config ระบบ
นอกโฟลเดอร์โปรเจ็กต์ — เจ้าของรันเองคำสั่งเดียว) · ยังไม่ได้ `git push` (master นำหน้า origin 4 commit) ·
ยังไม่ได้ตั้ง TURN (STUN อย่างเดียวต่อติดราว 80-90% ของเน็ตทั่วไป ถ้าเจอเคสต่อไม่ติดบ่อยค่อยเช่า coturn) ·
ฟีเจอร์ `Web-WebSockets` ยังค้าง `InstallPending` อยู่ ถ้าวันหลัง reboot ตามรอบปกติก็จะติดตั้งเสร็จเอง
แล้ว WebSocket จะวิ่งผ่าน IIS ได้ด้วย (จะลบกฎ cloudflared ทิ้งหรือเก็บไว้ก็ได้)

### 2026-09-12 — เพิ่มระบบช่วยเหลือระยะไกล (วิดีโอคอล + วาดชี้จุดบนภาพ)

**สรุป:** เมนูใหม่ "ช่วยเหลือระยะไกล" ใน Sidebar — คนที่ล็อกอินเปิดห้องแล้วส่งลิงก์ให้ผู้ใช้ที่มีปัญหา
ผู้ใช้กดลิงก์ + กดอนุญาตกล้อง ก็คุยวิดีโอกันได้ทันทีโดยไม่ต้องมีบัญชี ระหว่างคุยผู้ช่วยวาดวงกลม/ลูกศร
ลงบนภาพจากกล้องของผู้ใช้เพื่อชี้ว่าต้องกดตรงไหน — เอกสารทั้งหมดที่ `checkin-system/REMOTE_SUPPORT.md`

**ไฟล์ใหม่**

| ไฟล์ | หน้าที่ |
| --- | --- |
| `backend/app/support_models.py` | ตาราง `support_sessions` (โทเค็นในลิงก์ + วันหมดอายุ ไม่เก็บภาพ/เสียง) |
| `backend/app/routers/support.py` | REST 7 เส้น + WebSocket signaling (`/support/ws/{code}`) |
| `backend/test_support.py` | เทสต์ 13 ข้อ: สิทธิ์เข้าห้อง ลิงก์หมดอายุ การส่งต่อข้อความ |
| `frontend/src/lib/support-call.js` | WebRTC + WebSocket + ต่อใหม่อัตโนมัติ (ใช้ร่วมกันสองฝั่ง) |
| `frontend/src/lib/annotations.js` | รูปแบบเส้นที่วาด + การวาดลง canvas (ใช้ร่วมกันสองฝั่ง) |
| `frontend/src/components/support/AnnotationLayer.jsx` | ชั้น canvas รับการลากนิ้ว/เมาส์ |
| `frontend/src/components/support/VideoStage.jsx` | เวทีวิดีโอ + เส้น + ป้ายสถานะ + ภาพเล็ก |
| `frontend/src/components/support/CallToolbar.jsx` | แถบเครื่องมือฝั่งผู้ช่วย |
| `frontend/src/pages/SupportPage.jsx` | หน้าผู้ช่วย (ต้องล็อกอิน) |
| `frontend/src/pages/RemoteHelpPage.jsx` | หน้าผู้ใช้ (ไม่ต้องล็อกอิน) |
| `checkin-system/REMOTE_SUPPORT.md` | เอกสารประกอบทั้งหมด |

**ไฟล์ที่แก้**

- `app/security.py` — แยก `employee_from_token()` ออกมาจาก `get_current_employee()` แล้วให้ตัวเดิมเรียกใช้
  (WebSocket ในเบราว์เซอร์ตั้ง header `Authorization` ไม่ได้ ต้องรับโทเค็นทาง query string แล้วตรวจเอง)
- `app/config.py` — เพิ่ม `SUPPORT_*` / `STUN_SERVERS` / `TURN_*` + property `ice_servers_list`
- `app/main.py` — include `support.router`
- `requirements-base.txt` — เพิ่ม `qrcode>=8.0` (ไลบรารี Python ตัวเดียวที่ลงเพิ่มทั้งงานนี้)
- `backend/.env.example` — บล็อกค่า `SUPPORT_*` / STUN / TURN พร้อมคำอธิบาย
- `frontend/src/App.jsx` — route `/it-support` (ล็อกอิน) + `/remote-help/:code` (สาธารณะ) + ซ่อน ChatWidget บนหน้าผู้ใช้
- `frontend/src/components/AppLayout.jsx` — `SUPPORT_NAV` เข้าเมนูทั้ง BOSS_NAV และ STAFF_NAV
- `frontend/src/api.js` — ฟังก์ชันเรียก `/support/*` + `fetchSupportQr()`
- `frontend/vite.config.js` — `/^\/support/` เข้า navigateFallbackDenylist (ห้าม service worker ตอบแทน)
- `deploy/windows-server/web.config` — เพิ่ม `support` ในกฎ ProxyToBackend + หมายเหตุเรื่อง WebSocket ของ IIS
- `README.md` — หัวข้อใหม่ + แถว API + ตาราง `support_sessions`

**เหตุผลของการออกแบบที่ไม่ชัดจากโค้ด**

- **ไม่ใช้ `aiortc`** — ถ้าให้ Python เป็น peer ด้วย วิดีโอจะวิ่งผ่านเซิร์ฟเวอร์โดยไม่ได้อะไรเพิ่ม
  เปลือง CPU/bandwidth และทำให้วิดีโอของพนักงานผ่านตาเซิร์ฟเวอร์โดยไม่จำเป็น
  ใช้ WebSocket ของ Starlette ส่งแค่ SDP/ICE พอ (ตามแนวเดิมของโปรเจ็กต์ที่ไม่ลงไลบรารีเกินจำเป็น)
- **พิกัดเส้นที่วาดเก็บเป็นสัดส่วน 0..1 ของเฟรมวิดีโอ ไม่ใช่พิกเซลบนจอ** — จอผู้ช่วย (คอม) กับผู้ใช้
  (มือถือแนวตั้ง) คนละขนาด ถ้าส่งเป็นพิกเซล วงกลมจะไปโผล่คนละที่บนจออีกฝั่งทันที
- **ปุ่ม "หยุดภาพ" ส่ง JPEG ทั้งใบผ่าน WebSocket** — ผู้ใช้ถือมือถือส่องของ พอวงกลมเสร็จมือขยับไปแล้ว
  การตรึงเฟรมเดียวกันทั้งสองฝั่งคือวิธีเดียวที่ชี้จุดได้ตรงจริง (ย่อไม่เกิน 1280px คุณภาพ 0.72 → ~150KB)
- **ใช้ `addTransceiver` + `replaceTrack` แทน `addTrack`** — สลับกล้องหน้า/หลังหรือแชร์หน้าจอ
  จึงไม่ต้องเจรจา SDP ใหม่ ภาพไม่ดำไปสองสามวินาทีทุกครั้งที่สลับ
- **ส่งต่อเฉพาะ `type` ที่อยู่ใน `RELAYABLE`** — ไม่งั้นห้องนี้กลายเป็นช่องส่งข้อมูลอะไรก็ได้
  ระหว่างคนนอกสองคนที่ถือลิงก์
- **ฝั่งผู้ใช้เห็นชื่อผู้ช่วยก่อนกดอนุญาต** — การเปิดกล้องให้คนแปลกหน้าคือความเสี่ยง
  หน้าจอจึงเขียนกำกับว่า "ถ้าไม่รู้จักชื่อด้านบน อย่ากดอนุญาต"
- **เมนูอยู่ในทั้ง BOSS_NAV และ STAFF_NAV** — "คนที่ช่วย" คือใครก็ได้ที่ล็อกอิน ไม่ใช่สิทธิ์ของหัวหน้า
  ถ้าจะจำกัดเฉพาะหัวหน้า เปลี่ยน `RequireAuth` เป็น `RequireBoss` ใน `App.jsx` แล้วเอา `SUPPORT_NAV`
  ออกจาก `STAFF_NAV` (มีคอมเมนต์กำกับไว้ในโค้ดแล้ว)

**⚠️ impact analysis — `get_current_employee` ขึ้น CRITICAL (33 จุด, direct 14, 22 execution flows)**

การแก้เป็นการ refactor ล้วน: ย้ายโค้ด decode JWT ออกไปเป็น `employee_from_token()` แล้วให้ตัวเดิมเรียกใช้
signature เดิม, 401 ข้อความเดิม, header `WWW-Authenticate` เดิม, query หาพนักงานด้วย `employee_code` เหมือนเดิม
ยืนยันด้วยเทสต์เดิมที่ผ่านครบ (`test_chat` มีข้อที่เจาะเรื่องปลอมตัวผู้ส่งโดยเฉพาะ)
`detect-changes --scope all` ขึ้น critical ด้วยเหตุผลเดียวกัน — `require_manager`, `Settings`, `root` ที่ขึ้นในรายการ
เป็นแค่เลขบรรทัดเลื่อนจากการแทรกโค้ดด้านบน ไม่ได้แก้ตัวฟังก์ชัน

**ผลทดสอบ:** `python -m unittest test_payroll test_chat test_support` ผ่าน **79/79** ·
`npm run build` ผ่าน (2003 modules) · ทดสอบกับ uvicorn ตัวจริงบนพอร์ต 8003: ต่อ WebSocket สองฝั่ง
ส่ง offer/เส้นที่วาด/ภาพนิ่ง 400KB ผ่านครบ ปิดห้องแล้วลิงก์เดิมเข้าไม่ได้จริง · ลบข้อมูลทดสอบออกจาก
`checkin-dev.db` เรียบร้อย (ไม่แตะ Postgres ของ production)

### 2026-09-12 — เพิ่มแท็บ "ข้อมูลบริษัท" บนเว็บ + แก้บั๊ก proxy ของ /payroll

**ไฟล์ใหม่:** `checkin-system/frontend/src/pages/CompanyPage.jsx`

หน้าอธิบายธุรกิจของบริษัท (Motta & Montipa — แบรนด์แฟชั่นไทย ขายผ่านเคาน์เตอร์ในห้าง + ออนไลน์)
เปิดได้ทั้งหัวหน้าและพนักงาน เพราะเป็นข้อมูลองค์กร ไม่ใช่ข้อมูลส่วนบุคคล

**ไฟล์ที่แก้**

- `frontend/src/App.jsx` — route `/company` ใต้ `RequireAuth`
- `frontend/src/components/AppLayout.jsx` — เพิ่ม `COMPANY_NAV` เข้าทั้ง `BOSS_NAV` และ `STAFF_NAV`
- `deploy/windows-server/web.config` — **เพิ่ม `payroll` เข้ากฎ `ProxyToBackend`**

**🔴 บั๊กที่เจอและแก้ — `/payroll` ไม่เคยทำงานผ่านโดเมน**

ตอนเพิ่ม router `/payroll` เมื่อวาน ลืมเติมชื่อในกฎ `ProxyToBackend` ของ `web.config`
ตามที่ `README.md` เตือนไว้ ผลคือ IIS เสิร์ฟ `index.html` ของ React แทนที่จะ proxy ไป backend —
`https://thanakronpart-time.com/payroll/status` คืน **HTTP 200 + text/html** แทนที่จะเป็น 401 JSON

ตรวจไม่เจอตอนแรกเพราะเทสต์ทั้งหมดยิงที่ `127.0.0.1:8001` ตรงๆ ซึ่งข้าม IIS ไปเลย
**การแจ้งเตือน LINE ไม่ได้รับผลกระทบ** เพราะ Scheduled Task เรียก DB ตรง ไม่ผ่าน HTTP
สิ่งที่พังคือฝั่งเว็บ/แอปที่จะเรียก `/payroll/summary`

แก้แล้วและยืนยันผ่านโดเมนจริง: `/payroll/status` → **401 + application/json**

> บทเรียน: เพิ่ม router ใหม่ใน backend ต้องเติมชื่อใน `ProxyToBackend` เสมอ
> และต้องทดสอบผ่านโดเมนจริง ไม่ใช่แค่ `127.0.0.1:8001`

**Deploy:** รัน `deploy\windows-server\deploy-update.ps1` — build React (2,006 modules),
copy ขึ้น `C:\inetpub\checkin`, copy web.config, restart backend, ตรวจ router ครบ 16 เส้นผ่าน

**ผลตรวจ:** `/company` → 200 · bundle ใหม่ `index-DBkwAQWb.js` ขึ้นแล้ว · พบคำว่า "ข้อมูลบริษัท" ใน bundle ·
frontend tests 16/16 ผ่าน

**หมายเหตุ:** ข้อมูลธุรกิจในหน้านี้มาจากแหล่งสาธารณะ **ยังไม่ได้ยืนยันกับฝ่ายบุคคล**
ทุกบล็อกจึงมีป้ายกำกับ "ยืนยันแล้ว — จากระบบ" หรือ "ยังไม่ยืนยันกับฝ่ายบุคคล" กำกับไว้
อย่าเอาป้ายออกจนกว่าจะยืนยันจริง

### 2026-09-11 (บ่าย) — เปิดใช้ระบบเงินเดือนบน production แล้ว

**สถานะ: ใช้งานจริงแล้ว** — ทำครบทั้ง 4 ขั้นบนเครื่อง production

| ขั้น | สิ่งที่ทำ | ผลตรวจ |
| --- | --- | --- |
| 1 | แก้ `backend/.env` | สำรองไว้ที่ `backend/.env.backup-20260911-163624` (git ignore ครอบแล้ว) |
| 2 | restart `MardodiCheckinAPI` | endpoint 40 → **45 เส้น**, `/payroll` ขึ้นครบ 5 เส้น |
| 3 | migration รันเองตอนสตาร์ต | สร้างตาราง `payroll_notices` + คอลัมน์ `employees.base_salary` สำเร็จ |
| 4 | ตั้ง Scheduled Task `ThanakonPayrollNotice` | 2 trigger/วัน (09:00, 18:00) · สั่งรันจริงแล้ว `LastTaskResult=0` |

**ข้อมูลที่ตั้งใน DB จริง**

- `EMP001` (Thanakon Hongthong): `base_salary=18000`, `start_date` **2026-08-26 → 2026-09-14**
  (ของเดิมเป็นวันเริ่มงานที่เก่า ถ้าไม่แก้ รอบแรกจะคิดเต็มเดือน ฿17,250 แทนที่จะเป็น ฿7,410)
- `BOSS001`: ไม่ตั้ง `base_salary` = ไม่เข้าระบบเงินเดือน (ตั้งใจ)

**🔴 อุบัติเหตุที่เจอและแก้ทัน — บันทึกไว้กันซ้ำ**

ผู้ใช้ **ทับค่า `LINE_TARGET_ID` เดิม** ด้วย userId ส่วนตัว แทนที่จะเพิ่มบรรทัด `PAYROLL_LINE_TARGET_ID` ใหม่
ถ้าปล่อยไว้แล้ว restart: แจ้งเตือนเข้า-ออกงานทุกครั้ง + สรุปรายวัน 20:00 จะย้ายจากกลุ่มมาเข้าแชทส่วนตัวคนเดียว
**หัวหน้าจะไม่ได้รับแจ้งเตือนอีกเลย** — จับได้ก่อน restart จึงไม่มีผลกระทบจริง

ค่าที่ถูกต้องตอนนี้: `LINE_TARGET_ID` = Group ID (`C278cec…`) · `PAYROLL_LINE_TARGET_ID` = userId (`U9e5c3d…`)

**แก้โค้ดเพิ่มระหว่างนี้**

- `app/payroll_service.py` → `salary_of()` — `PAYROLL_DEFAULT_SALARY` **ไม่ใช้กับบัญชีหัวหน้า** แล้ว
  (เกณฑ์เดียวกับ `send_daily_summary.py` ที่ไม่นับบัญชี Boss เป็นพนักงาน) ตั้ง `base_salary` รายคนยังใช้ได้กับหัวหน้าตามปกติ
- `app/payroll.py` → เพิ่ม `period_in_focus()` แก้บั๊กตอนสั่งส่งเอง: วันที่ 27-28 เคยเลือกรอบใหม่ที่ยังไม่มีข้อมูล
  แทนรอบที่เงินกำลังจะออก (เส้นทาง Scheduled Task ไม่ได้รับผลกระทบ)
- เทสต์เพิ่มคุมทั้งสองเรื่อง — รวม **66 ข้อ ผ่านหมด**

**ทดสอบจริง:** ส่งการ์ด Flex เข้าแชทส่วนตัวสำเร็จ 2 ครั้ง (`push_flex` คืน True)
อ่านการลงเวลาจากตาราง `checkins` จริง — รอบ 27 ส.ค.–26 ก.ย. 2026 ประมาณการ **฿7,410** (ก่อนหัก ฿7,800 − ประกันสังคม ฿390)

**ยังไม่ได้ทำ:** ยังไม่ได้ commit · ยังไม่ได้ยืนยันวิธีเฉลี่ยเงิน (`PAYROLL_PRORATE_BASIS=calendar_30`) กับ HR ·
ยังไม่ได้ใส่วันหยุดนักขัตฤกษ์ใน `PAYROLL_HOLIDAYS` (ไม่ใส่ = วันหยุดถูกนับเป็นขาดงานและโดนหักเงิน)

### 2026-09-11 — เพิ่มระบบรอบเงินเดือน + แจ้งเตือนรายได้เข้า LINE

**สรุป:** ส่งสรุปรายได้เข้า LINE อัตโนมัติ 3 จังหวะต่อรอบ (ตัดรอบ 26 / เริ่มรอบใหม่ 27 / เงินเดือนออก 28)
คำนวณจากการลงเวลาจริงใน `checkins` — ดูวิธีคิดเงินและข้อจำกัดทั้งหมดที่ `checkin-system/PAYROLL_LINE_NOTIFY.md`

**ไฟล์ใหม่**

| ไฟล์ | หน้าที่ |
| --- | --- |
| `checkin-system/backend/app/payroll.py` | คณิตศาสตร์ล้วน: ขอบรอบ วันทำงาน การเฉลี่ยเงิน ประกันสังคม (ไม่แตะ DB) |
| `checkin-system/backend/app/payroll_service.py` | ดึงการลงเวลาจริง ตัดสินว่าถึงกำหนดส่งหรือยัง แล้วส่ง |
| `checkin-system/backend/app/payroll_models.py` | ตาราง `payroll_notices` (กันส่งซ้ำ) |
| `checkin-system/backend/app/line_flex.py` | ประกอบ JSON ของการ์ด LINE Flex Message |
| `checkin-system/backend/app/routers/payroll.py` | API 5 เส้นใต้ `/payroll` |
| `checkin-system/backend/send_payroll_notice.py` | CLI ที่ Scheduled Task เรียก |
| `checkin-system/backend/test_payroll.py` | เทสต์ 55 ข้อ |
| `checkin-system/deploy/line/install-payroll-task.ps1` | ติดตั้ง Scheduled Task (2 trigger/วัน) |
| `checkin-system/PAYROLL_LINE_NOTIFY.md` | เอกสารประกอบทั้งหมด |

**ไฟล์ที่แก้**

- `app/config.py` — เพิ่มกลุ่มค่า `PAYROLL_*` (18 ตัว) + property `payroll_weekdays_set` / `payroll_holidays_set` / `payroll_target_id` / เวลาแจ้งเตือน
- `app/models.py` — เพิ่มคอลัมน์ `employees.base_salary` (NULL = ไม่เข้าระบบเงินเดือน)
- `app/database.py` — เพิ่ม `("employees", "base_salary", "DOUBLE PRECISION")` ใน `_ADDED_COLUMNS`
- `app/notify_line.py` — **เพิ่ม** `push_flex()` ข้างๆ `push_text()` โดยไม่แตะ `push_text` เลย
- `app/main.py` — include `payroll.router`
- `backend/.env.example` — ตัวอย่างค่า `PAYROLL_*` ครบชุด
- `README.md` — หัวข้อรอบเงินเดือน + แถว API + ตาราง `payroll_notices`

**เหตุผลของการออกแบบที่ไม่ชัดจากโค้ด**

- **ไม่ใส่ scheduler ใน backend** — ใช้ pattern เดิมของโปรเจ็คคือ script + Windows Scheduled Task
  (เหมือน `send_daily_summary.py`) ตั้ง task เดียวมี 2 trigger/วัน แล้วให้สคริปต์ตัดสินเองว่าวันนั้นส่งอะไร
- **ไม่แตะ `push_text()`** — GitNexus impact upstream ขึ้น **HIGH** (4 จุด: `notify_checkin`,
  `send_test`, `send_daily_summary.main`) จึงเพิ่มฟังก์ชันใหม่ข้างๆ แทนการแก้ของเดิม
- **ไม่ลงไลบรารีเพิ่ม** — Flex Message เป็นของ Messaging API อยู่แล้ว `line-bot-sdk` จะลาก
  aiohttp/requests เข้ามาโดยไม่ได้อะไรเพิ่ม เพราะ `notify_line.py` ใช้ `urllib` จาก stdlib
- **`payroll_notices` ไม่มี UNIQUE constraint** — การส่งซ้ำมีเหตุผลที่ถูกต้อง (ครั้งก่อนล้มเหลว / สั่ง force)
  หนึ่งแถว = หนึ่งครั้งที่พยายามส่ง ตัวกันซ้ำจริงคือ `already_sent()` ที่นับเฉพาะแถว `ok=True`
- **ค่าเริ่มต้นปลอดภัยไว้ก่อน** — `PAYROLL_DEFAULT_SALARY=0` ทำให้ไม่มีใครถูกส่งตัวเลขเงินเดือน
  เข้า LINE โดยไม่ได้ตั้งใจ และมี `PAYROLL_LINE_TARGET_ID` แยกห้องออกจากกลุ่มแจ้งเข้างาน
- **`PAYROLL_PRORATE_BASIS` ค่าเริ่มต้น `calendar_30`** — เป็นวิธีที่ HR ไทยใช้บ่อยสุดกับพนักงานเข้าใหม่
  ยังไม่ได้ยืนยันกับ HR ของบริษัทจริง เปลี่ยนเป็น `work_days` ได้ด้วยการแก้ `.env` บรรทัดเดียว

**ผลทดสอบ:** `python -m unittest test_payroll` ผ่าน 64/64 (payroll 55 + chat 9) · ตรวจ OpenAPI ว่า endpoint ขึ้นครบ 5 เส้น ·
dry-run ครบทั้ง 3 ชนิดข้อความบน SQLite ชั่วคราว (ไม่แตะ Postgres ของ production) · PowerShell parse ผ่าน

**ยังไม่ได้ทำ:** ยังไม่ได้ commit · ยังไม่ได้ deploy ขึ้น production · ยังไม่ได้ตั้ง `PAYROLL_LINE_TARGET_ID`
และเงินเดือนรายคนในฐานข้อมูลจริง · ยังไม่ได้ส่งข้อความจริงเข้ากลุ่ม LINE

### 2026-09-11 — เพิ่ม Documentation Policy
- เพิ่มหัวข้อ "Project Rules" + "Work Log" ต่อท้าย `CLAUDE.md` (นอกบล็อก gitnexus)
- ไม่มีการแก้โค้ดในโปรเจ็ค

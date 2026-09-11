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

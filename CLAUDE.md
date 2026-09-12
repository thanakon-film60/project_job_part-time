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

### 2026-09-11 — Flutter: ยืนยันตัวตนรายวันตอนอยู่บ้าน ทั้ง 2 แอป + ทดสอบเครื่องจริง

ต่อจากงาน backend ด้านล่าง — ทำฝั่งแอปตาม `DAILY_HOME_FACE_VERIFICATION_2026-09-11.md` หัวข้อ 9–10 จนครบ

**ไฟล์ใหม่ (เหมือนกันทั้ง 2 แอป)**
- `lib/models/home_verification.dart` — แปลง UTC → เวลาไทยด้วย `+7` ตรง ๆ **ไม่ใช้ `toLocal()`** เพราะเครื่องผู้ใช้อาจตั้ง timezone ผิดแล้วอ่านคนละเวลากับที่หัวหน้าเห็นบนเว็บ
- `lib/services/home_verification_service.dart` — สร้าง UUID v4 เอง (ไม่ดึง package `uuid` มาเพื่อใช้ที่เดียว) · **จำ `request_id` ลง SharedPreferences ก่อนยิง** เพื่อกู้ผลได้แม้แอปถูกฆ่ากลางคัน
- `lib/screens/home_verification_screen.dart` — state machine ตามหัวข้อ 10 ใช้ `FaceScanner` เดิม
- `lib/widgets/home_verification_card.dart` — 4 สถานะ รวม **"ยังตรวจสอบผลไม่ได้"** ที่ต้องไม่ปนกับ "ยังไม่ได้ยืนยัน"
- `test/home_verification_test.dart` — 22 tests ต่อแอป

**แอปหัวหน้า — พอร์ตชุดสแกนใบหน้าเข้าไปทั้งชุด (เดิมไม่มีเลย):** เพิ่ม `camera` + `google_mlkit_face_detection` ใน pubspec, เพิ่ม `android.permission.CAMERA`, คัดลอก `face_scanner.dart`/`face_service.dart`/`face_enroll_screen.dart`

**⚠️ จุดเสี่ยงที่ต้องรู้:** แก้ [api_service.dart](checkin-system/flutter_app/lib/services/api_service.dart) ซึ่ง `ApiException` impact ขึ้น **CRITICAL** (83 จุด, direct 31) และ detect-changes ขึ้น critical/129 flows เพราะอยู่บนเส้นทางทุก API call — จึงแก้แบบ **additive ล้วน**: `code` เป็น named parameter ที่มี default และการอ่าน `detail` แบบ object เป็นสาขาใหม่ที่ไม่แตะเส้นทาง String/List เดิม endpoint เก่าทุกตัวได้พฤติกรรมเดิมเป๊ะ ยืนยันด้วย 245 tests + ทดสอบเครื่องจริง

**ผลทดสอบ:** analyze สะอาด · พนักงาน 103 tests · หัวหน้า 142 tests · build ผ่าน (หัวหน้าโต 74→101 MB เพราะ ML Kit) · **ทดสอบครบวงจรบน MTN NX1 ด้วย backend บนเครื่อง dev ผ่าน `adb reverse`** — บัญชีหัวหน้าต้องสแกนจริง, บันทึกลง `home_verifications` พร้อม GPS จริง, และ **ไม่สร้างรายการใน `checkins`** (ยืนยันจาก DB)

**bump version:** พนักงาน `1.5.0+7` → `1.6.0+8` · หัวหน้า `1.2.0+4` → `1.3.0+5` (แก้ทั้ง `pubspec.yaml` และ `Config.appVersion`)

**ยังค้าง:** เว็บ · **deploy backend + web.config ขึ้น production** · publish APK ใหม่ — จนกว่าจะ deploy การ์ดจะขึ้น "ยังตรวจสอบผลการยืนยันไม่ได้" ซึ่งเป็นพฤติกรรมที่ถูกต้อง

### 2026-09-11 — backend: ยืนยันตัวตนรายวันตอนอยู่บ้าน (home verification)

**ที่มา:** ทำตาม `checkin-system/DAILY_HOME_FACE_VERIFICATION_2026-09-11.md` ซึ่งกำหนดว่าทุกวันที่ไม่ได้ไปทำงานต้องสแกนใบหน้าสด + ตรวจ GPS บ้าน และหัวข้อ 13 กำหนดให้ **backend เสร็จก่อนเปิด UI ใหม่**

**ขอบเขตที่ตกลงกับเจ้าของงาน:** รอบนี้ทำ backend อย่างเดียว · verifier เอาระดับ **กันปลอม/กันใช้ซ้ำ ไม่ทำ face matching**

**ไฟล์ใหม่**
- `backend/app/home_verification.py` — ตรวจหลักฐาน: อ่านหัวไฟล์ JPEG/PNG เอง (จงใจไม่ใช้ Pillow/OpenCV เพราะ**ไม่ได้ประกาศใน requirements** ถ้า import แล้ว production ไม่มี backend จะไม่สตาร์ต), sha256 กันรูปซ้ำ, ลายนิ้วมือคำขอที่ทนต่อ GPS สั่น
- `backend/app/home_verification_models.py` — `home_verification_challenges` + `home_verifications` (แยกจาก `checkins` เพื่อไม่ให้รายการบ้านหลุดเข้าสูตรสาย/ชั่วโมงทำงาน)
- `backend/app/routers/home_verifications.py` — 5 endpoint: `POST /challenges`, `POST ""`, `GET /requests/{id}`, `GET /me`, `GET /employee/{id}` (หัวหน้า)
- `backend/test_home_verifications.py` — **29 tests ผ่าน**

**ไฟล์ที่แก้**
- `backend/app/config.py` — เพิ่ม `home_verification_challenge_ttl_seconds` (120), `_max_photo_bytes` (8 MB), `_min_photo_pixels` (160)
- `backend/app/main.py` — ลงทะเบียน router
- `deploy/windows-server/web.config` — เติม `home-verifications` ในกฎ `ProxyToBackend` (กับดักข้อ 1: ไม่เติม = 404 บน production)

**สิ่งที่บังคับได้จริง:** ไม่มีฟิลด์ `face_detected` ใน endpoint นี้เลย · **ไม่ยกเว้นบัญชีหัวหน้า** (ต่างจาก `POST /checkins` ที่ยังยกเว้น `is_manager` — ของเดิมไม่ถูกแตะ) · challenge ผูกบัญชี อายุ 120 วิ ใช้ครั้งเดียว · ไบต์รูปห้ามซ้ำทั้งระบบ · geofence ตัดสินฝั่ง server และต้องเป็น `category=home` · `request_id` เดิม+payload เดิมคืนรายการเดิม ไม่สร้างซ้ำ, payload ต่างได้ 409 · ตรวจคำขอเดิม**ก่อน**ตรวจ challenge หมดอายุ · `local_date` ตัดด้วยเวลาไทยฝั่ง server · response ไม่มี `late_minutes`/`expected_check_in`/ชั่วโมงทำงาน (มีเทสต์คุม)

**ข้อจำกัดที่ต้องรู้:** verifier **ไม่ได้ยืนยันว่าใบหน้าในรูปเป็นเจ้าของบัญชี** และไม่ได้ตรวจด้วยซ้ำว่ามีใบหน้าในรูปหรือไม่ — จุดต่อขยายอยู่ที่ `verify_evidence()`

**ยังค้าง:** Flutter ทั้ง 2 แอป (ยังไม่เริ่ม — แอปหัวหน้ายังไม่มีชุดกล้อง/สแกนหน้า) · เว็บ · **deploy ขึ้น production พร้อมคัดลอก `web.config` ใหม่ขึ้น IIS**

### 2026-09-11 — build + ทดสอบแอป Flutter ทั้ง 2 ตัวบนเครื่องจริง (MTN NX1)

**ที่มา:** ทำงานต่อจาก `checkin-system/HANDOVER_COMPANY_AND_WORK_2026-09-10.md` ซึ่งระบุว่างานค้างชิ้นใหญ่สุดคือ build + publish APK

**ทำอะไร**
- ยืนยันว่าเครื่องนี้เป็น **เครื่อง dev** (Flutter 3.38.2 ที่ `C:\src\flutter`, Android SDK, build-tools 36.1.0) **ไม่ใช่เครื่อง production** — ไม่มี `C:\inetpub\checkin`, ไม่มี scheduled task `MardodiCheckinAPI`, ไม่มี service cloudflared, ไม่มีอะไร listen พอร์ต 8001
- รัน `flutter analyze` + `flutter test` ทั้ง 2 แอป → สะอาด, **81 tests (พนักงาน) + 120 tests (หัวหน้า) ผ่านหมด**
- `flutter build apk --release` ทั้ง 2 แอป → `1.5.0+7` (80.2 MB) และ `1.2.0+4` (74.0 MB) ลายเซ็น debug keystore `41C0464D…9625E269` ตรงกับ APK ชุดเดิม → ติดตั้งทับได้ไม่ต้องถอน
- `adb install -r` ลง MTN NX1 (Android 16, API 36) ทั้ง 2 แอป → ทดสอบผ่าน: ไม่ crash, GPS + background tracking ทำงาน, ดึง `/reports/geofence` จาก production ได้ `Motta & Montipa (Head office)`, ตรรกะ `category=home` ไม่ตัดสินสายถูกต้อง

**แก้โค้ด**
- [checkin_tab.dart](checkin-system/flutter_app/lib/screens/tabs/checkin_tab.dart) และ [checkin_tab.dart](checkin-system/flutter_boss_app/lib/screens/tabs/checkin_tab.dart) — หน้าเช็คอินขึ้น `ห่างออฟฟิศ 0.07 กม.` ทั้งที่ออฟฟิศจริงห่าง 4.00 กม. เพราะ `_distanceKm` เก็บระยะถึง*สถานที่ใกล้สุดทุกประเภท* (ตอนอยู่บ้าน = บ้าน) แต่ป้ายเขียนตายตัวว่า "ออฟฟิศ" → เปลี่ยนมาใช้ `_workDistanceKm` + `_nearestOfficeName` ที่มีอยู่แล้ว จึงขึ้น `ห่าง Motta & Montipa (Head office) 4.00 กม.` และลบฟิลด์ `_distanceKm` ที่กลายเป็นตัวแปรตายออก
- GitNexus impact (`_watchPositions`, upstream): **LOW risk** ทั้ง 2 candidate กระทบ 2 จุด อยู่ในไฟล์ตัวเอง

**ยังค้าง**
- **publish APK ขึ้น production** — ต้องก๊อป APK 2 ไฟล์ไปรัน `publish-apk.ps1` บนเครื่อง production (ทำจากเครื่องนี้ไม่ได้) ตอนนี้เว็บยังแจก `1.2.0+3` / `1.0.0+1` อยู่
- **ทดสอบป้ายสาย/ตรงเวลาที่ออฟฟิศจริง** — ตอนทดสอบอยู่ห่าง 4.00 กม. อยู่นอกรัศมี 0.5 กม.
- ฟีเจอร์ไมค์ TiRTC ยังรอ credential จาก Tange (`business@tange.ai`)

### 2026-09-11 — เพิ่ม Documentation Policy
- เพิ่มหัวข้อ "Project Rules" + "Work Log" ต่อท้าย `CLAUDE.md` (นอกบล็อก gitnexus)
- ไม่มีการแก้โค้ดในโปรเจ็ค

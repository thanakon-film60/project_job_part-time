// Run from frontend: node tests/work-schedule-parity.mjs ../backend/venv/Scripts/python.exe
// No database or LINE calls: settings changes exist only in the test subprocess.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { resolve } from "node:path";
import { evaluateAttendance } from "../src/lib/work-schedule.js";

const python = resolve(process.argv[2] ?? "../backend/venv/Scripts/python.exe");
const backend = fileURLToPath(new URL("../../backend/", import.meta.url));
const program = `
import json
from dataclasses import asdict
from datetime import datetime
from app.config import settings
from app.work_schedule import evaluate_attendance
results = []
settings.attendance_rules_enabled = True
for start, end in [('08:30', '17:30'), ('09:00', '18:00')]:
    settings.work_start_time = start
    settings.work_end_time = end
    for grace in [0, 15]:
        settings.late_grace_minutes = grace
        settings.early_leave_grace_minutes = grace
        for kind in ['in', 'out']:
            for minute in range(1440):
                dt = datetime(2026, 9, 10, minute // 60, minute % 60, 59)
                results.append([settings.work_schedule_dict, kind, dt.isoformat() + '+07:00', asdict(evaluate_attendance(kind, dt, {'category':'work'}))])
print(json.dumps(results, ensure_ascii=True))
`;
const child = spawnSync(python, ["-c", program], { cwd: backend, encoding: "utf8", maxBuffer: 16 * 1024 * 1024 });
if (child.error) throw child.error;
assert.equal(child.status, 0, child.stderr);
const cases = JSON.parse(child.stdout);
for (const [work_schedule, kind, timestamp, expected] of cases) {
  assert.deepEqual(evaluateAttendance({ kind, timestamp }, { work_schedule, offices: [] }), expected, `${kind} ${timestamp} ${JSON.stringify(work_schedule)}`);
}
console.log(`Frontend/backend parity: ${cases.length} cases passed (every minute, two schedules, two grace periods, in/out).`);

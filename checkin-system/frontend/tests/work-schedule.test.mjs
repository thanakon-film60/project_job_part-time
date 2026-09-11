import test from "node:test";
import assert from "node:assert/strict";
import { evaluateAttendance, summarizeAttendance, validSchedule } from "../src/lib/work-schedule.js";

const geofence = { offices: [{ name: "Motta & Montipa (Head office)", category: "work" }], work_schedule: {
  work_start: "08:30", work_end: "17:30", late_grace_minutes: 0, early_leave_grace_minutes: 0, enabled: true,
} };
const record = (kind, time, extra = {}) => ({ kind, timestamp: `2026-09-10T${time}+07:00`, office_name: geofence.offices[0].name, ...extra });
const rules = (changes) => ({ ...geofence, work_schedule: { ...geofence.work_schedule, ...changes } });

for (const [kind, time, status, minutes, label] of [
  ["in", "08:15:00", "on_time", 0, "ตรงเวลา (ก่อนเวลา 15 นาที)"],
  ["in", "08:30:00", "on_time", 0, "ตรงเวลา"],
  ["in", "08:30:59", "on_time", 0, "ตรงเวลา"],
  ["in", "08:31:00", "late", 1, "สาย 1 นาที"],
  ["in", "10:05:00", "late", 95, "สาย 1 ชม. 35 นาที"],
  ["out", "16:30:00", "early_leave", 60, "ออกก่อนเวลา 1 ชม."],
  ["out", "17:29:59", "early_leave", 1, "ออกก่อนเวลา 1 นาที"],
  ["out", "17:30:00", "complete", 0, "ครบเวลางาน"],
  ["out", "18:45:00", "complete", 75, "ครบเวลางาน (เกินเวลา 1 ชม. 15 นาที)"],
]) test(`${kind} ${time}: ${status}`, () => {
  assert.deepEqual(evaluateAttendance(record(kind, time), geofence), { status, minutes, label });
});

test("grace changes the boundary, minutes remain relative to scheduled time", () => {
  assert.equal(evaluateAttendance(record("in", "08:45:59"), rules({ late_grace_minutes: 15 })).status, "on_time");
  assert.equal(evaluateAttendance(record("in", "08:46:00"), rules({ late_grace_minutes: 15 })).minutes, 16);
  assert.equal(evaluateAttendance(record("out", "17:15:00"), rules({ early_leave_grace_minutes: 15 })).status, "complete");
  assert.equal(evaluateAttendance(record("out", "17:14:00"), rules({ early_leave_grace_minutes: 15 })).minutes, 16);
});

test("API schedule overrides standard hours", () => {
  assert.equal(evaluateAttendance(record("in", "09:00:00"), rules({ work_start: "09:00" })).status, "on_time");
  assert.equal(evaluateAttendance(record("out", "17:30:00"), rules({ work_end: "18:00" })).minutes, 30);
});

test("UTC with/without offset and Thai timestamps produce identical verdicts", () => {
  for (const timestamp of ["2026-09-10T01:31:00", "2026-09-10T01:31:00Z", "2026-09-10T08:31:00+07:00", "2026-09-09T18:31:00-07:00"]) {
    assert.equal(evaluateAttendance({ kind: "in", timestamp }, geofence).minutes, 1);
  }
});

test("home entries, including former offices, are never judged", () => {
  for (const office_name of ["ถึงบ้านแล้ว", "My HOME", "house"]) {
    assert.equal(evaluateAttendance(record("in", "10:00:00", { office_name }), geofence).status, "not_applicable");
  }
  const custom = { ...geofence, offices: [{ name: "Residence A", category: "home" }] };
  assert.equal(evaluateAttendance(record("in", "10:00:00", { office_name: "Residence A" }), custom).status, "not_applicable");
  const explicitWork = { ...geofence, offices: [{ name: "Home Office", category: "work" }] };
  assert.equal(evaluateAttendance(record("in", "10:00:00", { office_name: "Home Office" }), explicitWork).status, "late");
});

test("disabled, unavailable, invalid schedules or records never accuse someone of lateness", () => {
  for (const config of [null, {}, rules({ enabled: false }), rules({ enabled: "false" }), rules({ work_start: "25:00" }), rules({ late_grace_minutes: -1 })]) {
    assert.equal(evaluateAttendance(record("in", "10:00:00"), config).status, "not_applicable");
  }
  for (const input of [null, {}, { kind: "in", timestamp: "invalid" }, record("unknown", "10:00:00")]) {
    assert.equal(evaluateAttendance(input, geofence).status, "not_applicable");
  }
  assert.equal(validSchedule(geofence.work_schedule), true);
});

test("summary uses first work arrival and last work departure, not repeated entries", () => {
  const records = [record("in", "10:00:00"), record("out", "16:00:00"), record("in", "08:20:00"), record("out", "18:00:00"),
    record("in", "07:00:00", { office_name: "ถึงบ้านแล้ว" }), record("out", "23:00:00", { office_name: "ถึงบ้านแล้ว" })];
  const summary = summarizeAttendance(records, geofence);
  assert.equal(summary.days.length, 1);
  assert.equal(summary.lateDays, 0);
  assert.equal(summary.earlyLeaveDays, 0);
  assert.equal(summary.days[0].arrival.status, "on_time");
  assert.equal(summary.days[0].departure.minutes, 30);
});

test("monthly summary groups by Thai date and counts each late/early-leave day once", () => {
  const summary = summarizeAttendance([
    record("in", "08:31:00"), record("in", "09:00:00"), record("out", "16:00:00"),
    { kind: "in", timestamp: "2026-09-10T18:00:00Z" },
    record("in", "10:00:00", { office_name: "ถึงบ้านแล้ว" }),
  ], geofence);
  assert.deepEqual(summary.days.map((day) => day.date), ["2026-09-10", "2026-09-11"]);
  assert.equal(summary.lateDays, 1);
  assert.equal(summary.earlyLeaveDays, 1);
});

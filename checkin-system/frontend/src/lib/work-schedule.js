// The server supplies the rules; never label someone late using guessed defaults.
export function validSchedule(schedule) {
  return Boolean(schedule && typeof schedule.enabled === "boolean"
    && /^([01]\d|2[0-3]):[0-5]\d$/.test(schedule.work_start)
    && /^([01]\d|2[0-3]):[0-5]\d$/.test(schedule.work_end)
    && [schedule.late_grace_minutes, schedule.early_leave_grace_minutes]
      .every((value) => Number.isInteger(value) && value >= 0 && value <= 180));
}

export function thaiTimestamp(timestamp) {
  if (!timestamp || typeof timestamp !== "string") return null;
  const text = timestamp.trim();
  const date = new Date(/[zZ]|[+-]\d{2}:?\d{2}$/.test(text) ? text : `${text}Z`);
  if (!Number.isFinite(date.getTime())) return null;
  return new Date(date.getTime() + 7 * 60 * 60 * 1000);
}

function isHome(record, offices) {
  const name = String(record?.office_name ?? "").trim();
  const office = offices.find((item) => String(item.name ?? "").trim() === name);
  const category = String(office?.category ?? "").trim().toLowerCase();
  if (["home", "house", "บ้าน"].includes(category)) return true;
  if (["work", "office", "workplace", "ที่ทำงาน", "ออฟฟิศ", "บริษัท", "hospital", "clinic", "โรงพยาบาล", "โรงบาล", "รพ"].includes(category)) return false;
  return /บ้าน|home|house/i.test(`${category} ${name}`);
}

function humanMinutes(total) {
  const hours = Math.floor(total / 60), minutes = total % 60;
  if (!hours) return `${minutes} นาที`;
  return minutes ? `${hours} ชม. ${minutes} นาที` : `${hours} ชม.`;
}

const NONE = Object.freeze({ status: "not_applicable", minutes: 0, label: "" });

export function evaluateAttendance(record, geofence) {
  const schedule = geofence?.work_schedule;
  if (!validSchedule(schedule) || !schedule.enabled || isHome(record, geofence?.offices ?? [])) return NONE;
  const date = thaiTimestamp(record?.timestamp);
  if (!date) return NONE;
  const now = date.getUTCHours() * 60 + date.getUTCMinutes();
  const toMinutes = (value) => value.split(":").reduce((hours, minutes) => Number(hours) * 60 + Number(minutes));
  if (record.kind === "in") {
    const start = toMinutes(schedule.work_start);
    if (now > start + schedule.late_grace_minutes) {
      return { status: "late", minutes: now - start, label: `สาย ${humanMinutes(now - start)}` };
    }
    return { status: "on_time", minutes: 0, label: now < start ? `ตรงเวลา (ก่อนเวลา ${humanMinutes(start - now)})` : "ตรงเวลา" };
  }
  if (record.kind === "out") {
    const end = toMinutes(schedule.work_end);
    if (now < end - schedule.early_leave_grace_minutes) {
      return { status: "early_leave", minutes: end - now, label: `ออกก่อนเวลา ${humanMinutes(end - now)}` };
    }
    return { status: "complete", minutes: Math.max(now - end, 0), label: now > end ? `ครบเวลางาน (เกินเวลา ${humanMinutes(now - end)})` : "ครบเวลางาน" };
  }
  return NONE;
}

// Count days, not repeated check-ins. Use first work entry and last work exit.
export function summarizeAttendance(records, geofence) {
  const days = new Map();
  for (const record of records ?? []) {
    const date = thaiTimestamp(record?.timestamp);
    if (!date || isHome(record, geofence?.offices ?? []) || !["in", "out"].includes(record.kind)) continue;
    const key = date.toISOString().slice(0, 10);
    const day = days.get(key) ?? { date: key, firstIn: null, lastOut: null };
    if (record.kind === "in" && (!day.firstIn || date < thaiTimestamp(day.firstIn.timestamp))) day.firstIn = record;
    if (record.kind === "out" && (!day.lastOut || date > thaiTimestamp(day.lastOut.timestamp))) day.lastOut = record;
    days.set(key, day);
  }
  const entries = [...days.values()].map((day) => ({ ...day,
    arrival: evaluateAttendance(day.firstIn, geofence),
    departure: evaluateAttendance(day.lastOut, geofence),
  }));
  return { days: entries,
    lateDays: entries.filter((day) => day.arrival.status === "late").length,
    earlyLeaveDays: entries.filter((day) => day.departure.status === "early_leave").length,
  };
}

import React from "react";

const WEEKDAYS = ["อา", "จ", "อ", "พ", "พฤ", "ศ", "ส"];

function timeOnly(iso) {
  if (!iso) return "—";
  const d = new Date(iso);
  return d.toLocaleTimeString("th-TH", { hour: "2-digit", minute: "2-digit" });
}

export default function Calendar({ year, month, days }) {
  // map date -> summary
  const byDate = {};
  days.forEach((d) => (byDate[d.date] = d));

  const first = new Date(year, month - 1, 1);
  const startWeekday = first.getDay();
  const daysInMonth = new Date(year, month, 0).getDate();

  const cells = [];
  for (let i = 0; i < startWeekday; i++) cells.push(null);
  for (let day = 1; day <= daysInMonth; day++) {
    const dateStr = `${year}-${String(month).padStart(2, "0")}-${String(
      day
    ).padStart(2, "0")}`;
    cells.push({ day, summary: byDate[dateStr] });
  }

  return (
    <div className="calendar">
      <div className="cal-head">
        {WEEKDAYS.map((w) => (
          <div key={w} className="cal-weekday">
            {w}
          </div>
        ))}
      </div>
      <div className="cal-grid">
        {cells.map((c, i) => {
          if (!c) return <div key={i} className="cal-cell empty" />;
          const s = c.summary;
          const present = !!s;
          const inZone = s && s.within_geofence;
          return (
            <div
              key={i}
              className={`cal-cell ${present ? "present" : ""} ${
                present && !inZone ? "outside" : ""
              }`}
            >
              <div className="cal-day">{c.day}</div>
              {present ? (
                <div className="cal-info">
                  <div className="in">เข้า {timeOnly(s.first_in)}</div>
                  <div className="out">ออก {timeOnly(s.last_out)}</div>
                  <div className={`badge ${inZone ? "ok" : "bad"}`}>
                    {inZone ? "อยู่ในออฟฟิศ" : "นอกเขต"}
                  </div>
                </div>
              ) : (
                <div className="cal-info muted">ไม่มีข้อมูล</div>
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
}

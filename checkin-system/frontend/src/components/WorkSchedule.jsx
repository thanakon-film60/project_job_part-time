import React, { useEffect, useState } from "react";
import { getGeofence } from "@/api";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { evaluateAttendance, validSchedule } from "@/lib/work-schedule";

export function useWorkSchedule() {
  const [geofence, setGeofence] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [revision, setRevision] = useState(0);
  useEffect(() => {
    let active = true;
    setLoading(true);
    setError("");
    setGeofence(null);
    getGeofence().then((data) => {
      if (!active) return;
      setGeofence(data);
      if (!validSchedule(data?.work_schedule)) setError("ยังไม่มีเกณฑ์เวลางานจากเซิร์ฟเวอร์ จึงยังแสดงสถานะสาย/ตรงเวลาไม่ได้");
    }).catch(() => {
      if (active) setError("โหลดสถานที่และเวลางานไม่สำเร็จ จึงยังแสดงสถานะสาย/ตรงเวลาไม่ได้");
    }).finally(() => active && setLoading(false));
    return () => { active = false; };
  }, [revision]);
  return { geofence, loading, error, reload: () => setRevision((value) => value + 1) };
}

export function WorkSchedulePanel({ state }) {
  const { geofence, loading, error, reload } = state;
  const schedule = geofence?.work_schedule;
  return <Card><CardContent className="space-y-2 p-4 text-sm" aria-live="polite">
    <h3 className="font-semibold">สถานที่และเวลาทำงาน</h3>
    {loading && <p className="text-muted-foreground">กำลังโหลดข้อมูล…</p>}
    {geofence?.offices?.map((office) => <p key={office.name}>
      {office.name} · รัศมี {Math.round(office.radius_km * 1000)} เมตร
    </p>)}
    {error && <div className="flex flex-wrap items-center gap-2 text-destructive">
      <p>{error}</p><Button size="sm" variant="outline" onClick={reload}>ลองอีกครั้ง</Button>
    </div>}
    {validSchedule(schedule) && <>
      <p>เวลางาน {schedule.work_start}–{schedule.work_end} น. (เวลาไทย)
        {!schedule.enabled && <Badge variant="secondary" className="ml-2">ปิดการตัดสินสาย/ออกก่อนเวลา</Badge>}
      </p>
      {schedule.enabled && <p className="text-muted-foreground text-xs">
        ผ่อนผันเข้างาน {schedule.late_grace_minutes} นาที · ออกงาน {schedule.early_leave_grace_minutes} นาที
        <br />สถานะย้อนหลังคำนวณตามเกณฑ์ปัจจุบัน ยังไม่แยกวันหยุดและวันลา
      </p>}
    </>}
  </CardContent></Card>;
}

export function AttendanceBadge({ record, geofence }) {
  const verdict = evaluateAttendance(record, geofence);
  if (!verdict.label) return null;
  const variant = verdict.status === "late" ? "destructive" : verdict.status === "early_leave" ? "warning" : "success";
  return <Badge variant={variant} className="max-w-full whitespace-normal text-left">{verdict.label}</Badge>;
}

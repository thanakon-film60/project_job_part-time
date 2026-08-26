import React, { useEffect, useMemo, useState } from "react";
import dayjs from "dayjs";
import {
  ArrowLeft,
  BriefcaseBusiness,
  CalendarDays,
  ChevronLeft,
  ChevronRight,
  CircleAlert,
  Clock,
  House,
  LogIn,
  LogOut,
  MapPin,
  Pencil,
  ShieldCheck,
} from "lucide-react";
import { Link, useParams } from "react-router-dom";
import AppLayout from "@/components/AppLayout.jsx";
import EmployeeEditDialog from "@/components/EmployeeEditDialog.jsx";
import EmployeeFaceAvatar from "@/components/EmployeeFaceAvatar.jsx";
import { getEmployeeHistory } from "@/api";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { EmptyState } from "@/components/ui/empty-state";
import { Input } from "@/components/ui/input";
import { Skeleton, StatCardSkeleton } from "@/components/ui/skeleton";
import { StatCard } from "@/components/ui/stat-card";
import { describeCheckin, isHomeLocation, thaiDateTime, thaiFrom } from "@/lib/attendance";
import { cn } from "@/lib/utils";

function HistorySkeleton() {
  return (
    <div className="space-y-3">
      {[0, 1, 2].map((index) => (
        <Skeleton key={index} className="h-20 w-full rounded-lg" />
      ))}
    </div>
  );
}

export default function EmployeeHistoryPage() {
  const { employeeId } = useParams();
  const [month, setMonth] = useState(dayjs().startOf("month"));
  const [result, setResult] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [editOpen, setEditOpen] = useState(false);
  const [reloadKey, setReloadKey] = useState(0);

  useEffect(() => {
    let active = true;
    setLoading(true);
    setError("");
    getEmployeeHistory(employeeId, month.year(), month.month() + 1)
      .then((data) => active && setResult(data))
      .catch((err) => active && setError(err.message || "โหลดประวัติพนักงานไม่สำเร็จ"))
      .finally(() => active && setLoading(false));
    return () => {
      active = false;
    };
  }, [employeeId, month, reloadKey]);

  const checkins = result?.checkins ?? [];
  const groups = useMemo(() => {
    const grouped = new Map();
    checkins.forEach((record) => {
      const date = thaiFrom(record.timestamp)?.format("YYYY-MM-DD") ?? "unknown";
      if (!grouped.has(date)) grouped.set(date, []);
      grouped.get(date).push(record);
    });
    return [...grouped.entries()];
  }, [checkins]);

  const workDays = useMemo(
    () =>
      new Set(
        checkins
          .filter((record) => !isHomeLocation(record.office_name))
          .map((record) => thaiFrom(record.timestamp)?.format("YYYY-MM-DD")),
      ).size,
    [checkins],
  );
  const employee = result?.employee;

  return (
    <AppLayout>
      <div className="space-y-4">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <Button variant="outline" asChild>
            <Link to="/employees"><ArrowLeft /> กลับหน้าพนักงาน</Link>
          </Button>
          <div className="flex items-center gap-2">
            <Button type="button" variant="outline" size="icon" aria-label="เดือนก่อนหน้า" onClick={() => setMonth((value) => value.subtract(1, "month"))}>
              <ChevronLeft />
            </Button>
            <Input
              type="month"
              value={month.format("YYYY-MM")}
              onChange={(event) => event.target.value && setMonth(dayjs(`${event.target.value}-01`))}
              className="w-40"
              aria-label="เลือกเดือน"
            />
            <Button type="button" variant="outline" size="icon" aria-label="เดือนถัดไป" onClick={() => setMonth((value) => value.add(1, "month"))}>
              <ChevronRight />
            </Button>
          </div>
        </div>

        <Card>
          <CardContent className="flex items-start gap-4 p-4 sm:p-5">
            <EmployeeFaceAvatar faceRecordId={result?.face_profiles?.[0]?.id} className="size-16 border" />
            <div className="min-w-0">
              {loading && !employee ? (
                <div className="space-y-2"><Skeleton className="h-5 w-48" /><Skeleton className="h-4 w-32" /></div>
              ) : (
                <>
                  <h2 className="truncate text-xl font-bold">{employee?.full_name || "ประวัติพนักงาน"}</h2>
                  <div className="text-muted-foreground mt-1 flex flex-wrap items-center gap-2 text-sm">
                    {employee && <Badge variant="secondary">{employee.employee_code}</Badge>}
                    <span>{employee?.email}</span>
                  </div>
                  <div className="mt-3 grid gap-x-6 gap-y-1 text-sm sm:grid-cols-2 lg:grid-cols-3">
                    <span><strong>แผนก:</strong> {employee?.department || "ยังไม่ระบุ"}</span>
                    <span><strong>ตำแหน่ง:</strong> {employee?.position || "ยังไม่ระบุ"}</span>
                    <span><strong>วันเริ่มงาน:</strong> {employee?.start_date ? dayjs(employee.start_date).format("D MMM YYYY") : "ยังไม่ระบุ"}</span>
                    <span><strong>วันเกิด:</strong> {employee?.birth_date ? dayjs(employee.birth_date).format("D MMM YYYY") : "ยังไม่ระบุ"}</span>
                    <span><strong>ลงทะเบียน:</strong> {employee?.created_at ? thaiDateTime(employee.created_at) : "ยังไม่ระบุ"}</span>
                    <span><strong>แก้ไขล่าสุด:</strong> {employee?.updated_at ? thaiDateTime(employee.updated_at) : "ยังไม่มีการแก้ไข"}</span>
                    <span><strong>โทร:</strong> {employee?.phone || "ยังไม่ระบุ"}</span>
                    <span><strong>เลขบัตร:</strong> {employee?.national_id_masked || "ยังไม่มีข้อมูล"}</span>
                    <span><strong>ที่อยู่:</strong> {[employee?.address_line, employee?.subdistrict, employee?.district, employee?.province, employee?.postal_code].filter(Boolean).join(" ") || "ยังไม่ระบุ"}</span>
                  </div>
                  {employee && !employee.profile_complete && (
                    <Badge variant="warning" className="mt-3">บัญชีเดิม — ข้อมูลโปรไฟล์ยังไม่ครบ</Badge>
                  )}
                </>
              )}
            </div>
            {employee && (
              <Button type="button" variant="outline" className="ml-auto shrink-0" onClick={() => setEditOpen(true)}>
                <Pencil /> <span className="hidden sm:inline">แก้ไขข้อมูล</span>
              </Button>
            )}
          </CardContent>
        </Card>

        {employee && (
          <EmployeeEditDialog
            open={editOpen}
            onOpenChange={setEditOpen}
            employee={employee}
            onSaved={() => setReloadKey((value) => value + 1)}
          />
        )}

        <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
          {loading ? (
            <><StatCardSkeleton /><StatCardSkeleton /><StatCardSkeleton /><StatCardSkeleton /></>
          ) : (
            <>
              <StatCard icon={<CalendarDays />} label="วันที่มาทำงาน" value={workDays} suffix="วัน" />
              <StatCard icon={<LogIn />} label="บันทึกเข้างาน" value={checkins.filter((item) => item.kind === "in" && !isHomeLocation(item.office_name)).length} suffix="ครั้ง" tone="success" />
              <StatCard icon={<Clock />} label="บันทึกทั้งหมด" value={checkins.length} suffix="รายการ" />
              <StatCard icon={<ShieldCheck />} label="รูปยืนยันตัวตน" value={result?.face_profiles?.length ?? 0} suffix="รูป" tone="success" />
            </>
          )}
        </div>

        {error && (
          <Alert variant="destructive">
            <CircleAlert />
            <AlertDescription className="text-foreground">{error}</AlertDescription>
          </Alert>
        )}

        <Card>
          <CardHeader>
            <CardTitle>ประวัติการลงเวลา — {month.format("MMMM YYYY")}</CardTitle>
          </CardHeader>
          <CardContent>
            {loading ? (
              <HistorySkeleton />
            ) : groups.length === 0 ? (
              <EmptyState icon={<Clock />} title="ไม่พบประวัติในเดือนนี้" description="ลองเลือกเดือนอื่นเพื่อตรวจสอบข้อมูลย้อนหลัง" />
            ) : (
              <div className="space-y-5">
                {groups.map(([date, records]) => (
                  <section key={date} className="space-y-2">
                    <h3 className="text-sm font-semibold">{dayjs(date).format("D MMMM YYYY")}</h3>
                    <ul className="divide-border overflow-hidden rounded-lg border divide-y">
                      {records.map((record) => {
                        const entry = describeCheckin(record);
                        const isHome = entry.kind === "home";
                        const isIn = entry.kind === "in";
                        return (
                          <li key={record.id} className="flex items-center gap-3 p-3">
                            <span className={cn(
                              "flex size-9 shrink-0 items-center justify-center rounded-lg",
                              isHome ? "bg-purple-500/10 text-purple-700" : isIn ? "bg-success/10 text-success" : "bg-warning/15 text-warning",
                            )}>
                              {isHome ? <House /> : isIn ? <LogIn /> : <LogOut />}
                            </span>
                            <div className="min-w-0 flex-1">
                              <div className="flex flex-wrap items-center gap-2">
                                <span className="font-medium">{entry.label}</span>
                                <Badge variant={entry.badge}>{record.office_name || "ไม่ระบุสถานที่"}</Badge>
                              </div>
                              <div className="text-muted-foreground mt-1 flex flex-wrap gap-x-3 text-xs">
                                <span>{thaiDateTime(record.timestamp)}</span>
                                {record.distance_km != null && (
                                  <span className="inline-flex items-center gap-1"><MapPin className="size-3" /> {record.distance_km < 1 ? `${Math.round(record.distance_km * 1000)} ม.` : `${record.distance_km.toFixed(2)} กม.`}</span>
                                )}
                              </div>
                            </div>
                          </li>
                        );
                      })}
                    </ul>
                  </section>
                ))}
              </div>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2"><BriefcaseBusiness className="size-5" /> Timeline แฟ้มพนักงาน</CardTitle>
          </CardHeader>
          <CardContent>
            {!result?.events?.length ? (
              <EmptyState title="ยังไม่มีเหตุการณ์ในแฟ้มพนักงาน" />
            ) : (
              <ol className="relative ml-2 border-l pl-5">
                {result.events.map((event) => (
                  <li key={event.id} className="relative pb-5 last:pb-0">
                    <span className="bg-primary absolute top-1.5 -left-[25px] size-2.5 rounded-full ring-4 ring-background" />
                    <p className="font-medium">{event.title}</p>
                    <p className="text-muted-foreground text-xs">{thaiDateTime(event.created_at)}</p>
                    {event.detail?.department && (
                      <p className="text-muted-foreground mt-1 text-sm">{event.detail.department} · {event.detail.position}</p>
                    )}
                    {event.detail?.note && <p className="text-muted-foreground mt-1 text-sm">{event.detail.note}</p>}
                    {event.detail?.changed_fields?.length > 0 && (
                      <p className="text-muted-foreground mt-1 text-sm">แก้ไข: {event.detail.changed_fields.join(", ")}</p>
                    )}
                  </li>
                ))}
              </ol>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2"><ShieldCheck className="size-5" /> ประวัติยืนยันใบหน้า</CardTitle>
          </CardHeader>
          <CardContent>
            {!result?.face_profiles?.length ? (
              <EmptyState title="ยังไม่มีรูปยืนยันตัวตน" />
            ) : (
              <ul className="divide-border divide-y">
                {result.face_profiles.map((face, index) => (
                  <li key={face.id} className="flex items-center gap-3 py-3 first:pt-0 last:pb-0">
                    <EmployeeFaceAvatar faceRecordId={face.id} className="size-12 border" />
                    <div className="min-w-0 flex-1">
                      <p className="font-medium">รูปยืนยันตัวตน #{result.face_profiles.length - index}</p>
                      <p className="text-muted-foreground text-xs">บันทึกเมื่อ {thaiDateTime(face.created_at)}</p>
                    </div>
                    <Badge variant="success">{face.source === "mobile" ? "แอปมือถือ" : "เว็บไซต์"}</Badge>
                  </li>
                ))}
              </ul>
            )}
          </CardContent>
        </Card>
      </div>
    </AppLayout>
  );
}

import React, { useEffect, useMemo, useState } from "react";
import dayjs from "dayjs";
import utc from "dayjs/plugin/utc";
import {
  CalendarDays,
  CircleAlert,
  Clock,
  House,
  History,
  Info,
  LogIn,
  LogOut,
  MapPin,
  ShieldAlert,
  User,
  UserX,
  Users,
} from "lucide-react";
import { Link } from "react-router-dom";
import { getEmployee, getTeamCalendar, getMyCheckins, getMyFaces } from "../api";
import AppLayout from "../components/AppLayout.jsx";
import AppDownloadCard from "../components/AppDownloadCard.jsx";
import MonthCalendar, { MonthCalendarSkeleton } from "../components/MonthCalendar.jsx";
import UnverifiedDutyAlert from "../components/UnverifiedDutyAlert.jsx";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { EmptyState } from "@/components/ui/empty-state";
import { Skeleton, StatCardSkeleton, ListRowSkeleton } from "@/components/ui/skeleton";
import { StatCard } from "@/components/ui/stat-card";
import {
  UNVERIFIED_DUTY_WARNING,
  UNVERIFIED_REASON_NO_FACE,
  UNVERIFIED_TITLE,
  describeCheckin,
  describeUnverified,
  hasCheckinOn,
  thaiDateTime,
  thaiTime,
} from "@/lib/attendance";
import { cn } from "@/lib/utils";

dayjs.extend(utc);

// การแปลงเวลาไทยและการอ่านว่า "รายการนี้อยู่บ้านหรือที่ทำงาน" อยู่ใน
// src/lib/attendance.js — ใช้ร่วมกันทั้งเว็บ และตรรกะตรงกับ backend + แอป Flutter

function locationVariant(location) {
  if (location === "อยู่ที่บ้าน") return "purple";
  if (location === "นอกเขต") return "warning";
  return "success";
}

function EmployeeDashboard({ me }) {
  const [checkins, setCheckins] = useState([]);
  const [faces, setFaces] = useState(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let active = true;
    Promise.all([
      getMyCheckins().catch(() => []),
      // โหลดล้มเหลว = ไม่รู้ว่าลงทะเบียนใบหน้าไว้ไหม ปล่อยเป็น null แล้วไม่เตือน
      // ดีกว่ากล่าวหาว่าไม่ได้ลงทะเบียนทั้งที่จริงๆ แค่เน็ตหลุด
      getMyFaces().catch(() => null),
    ])
      .then(([checkinData, faceData]) => {
        if (!active) return;
        setCheckins(Array.isArray(checkinData) ? checkinData : []);
        setFaces(Array.isArray(faceData) ? faceData : null);
      })
      .finally(() => active && setLoading(false));
    return () => {
      active = false;
    };
  }, []);

  // เตือนหลังโหลดเสร็จเท่านั้น ไม่งั้นระหว่างรอข้อมูลจะขึ้นแดงทุกครั้งที่เปิดหน้า
  const verification = describeUnverified({
    faceEnrolled: faces === null ? true : faces.length > 0,
    checkedInToday: loading ? true : hasCheckinOn(checkins),
  });

  return (
    <AppLayout>
      <div className="space-y-4">
        {verification.unverified && (
          <UnverifiedDutyAlert
            title={verification.title}
            reasons={verification.reasons}
            warning={verification.warning}
          >
            <p className="mt-1">
              เปิดแอปในมือถือแล้วสแกนใบหน้าเพื่อลงเวลา
              {faces !== null && faces.length === 0 && (
                <>
                  {" — "}
                  <Link to="/face-records" className="font-semibold underline">
                    ลงทะเบียนใบหน้าที่นี่
                  </Link>
                </>
              )}
            </p>
          </UnverifiedDutyAlert>
        )}

        {/* การ์ดต้อนรับพนักงาน */}
        <Card className="border-primary/20 bg-gradient-to-r from-primary/10 via-primary/5 to-transparent">
          <CardContent className="flex flex-col justify-between gap-3 p-4 sm:flex-row sm:items-center sm:p-5">
            <div className="flex items-center gap-3">
              <Avatar className="size-12 border-2 border-primary/20 shadow-xs">
                <AvatarFallback className="bg-primary text-primary-foreground text-base font-semibold">
                  {me?.full_name?.charAt(0) || "E"}
                </AvatarFallback>
              </Avatar>
              <div className="min-w-0">
                <h3 className="text-foreground truncate text-base font-bold sm:text-lg">
                  สวัสดี, {me?.full_name}
                </h3>
                <div className="text-muted-foreground mt-0.5 flex flex-wrap items-center gap-2 text-xs">
                  <Badge variant="outline">รหัส {me?.employee_code}</Badge>
                  <span>{me?.email}</span>
                </div>
              </div>
            </div>

            <Button asChild variant="outline" size="sm" className="w-fit">
              <Link to="/face-records" className="flex items-center gap-1.5">
                <User className="size-4" />
                <span>ประวัติใบหน้า</span>
              </Link>
            </Button>
          </CardContent>
        </Card>

        {/* การ์ดดาวน์โหลดแอปสำหรับเช็คอิน */}
        <AppDownloadCard />

        {/* สรุปประวัติการลงเวลาล่าสุดของพนักงาน */}
        <Card>
          <CardContent className="space-y-4 p-4 sm:p-5">
            <div className="flex items-center justify-between">
              <h3 className="flex items-center gap-2 text-base font-semibold">
                <Clock className="text-primary size-4.5" />
                ประวัติการลงเวลาของฉัน
              </h3>
              <Badge variant="secondary">ทั้งหมด {checkins.length} รายการ</Badge>
            </div>

            <p className="text-muted-foreground text-xs">
              อยู่บ้านคืออยู่บ้าน — ไม่ได้ไปทำงาน จึงไม่มีเข้างาน/ออกงานและไม่นับเป็นเวลาทำงาน
              แต่ยังต้องเข้าสู่ระบบทุกวัน เพื่อให้ระบบรู้ว่าอยู่ที่ไหนและกำลังทำอะไร
            </p>

            {loading ? (
              <div className="divide-border -mx-1 divide-y px-1">
                {[0, 1, 2, 3].map((i) => (
                  <ListRowSkeleton key={i} />
                ))}
              </div>
            ) : checkins.length === 0 ? (
              <EmptyState
                icon={<Clock className="size-6" />}
                title="ยังไม่มีประวัติการลงเวลา"
                description="เมื่อเช็คอินผ่านแอปมือถือ ข้อมูลจะแสดงที่นี่"
              />
            ) : (
              <ul className="divide-border -mx-1 divide-y px-1">
                {checkins.slice(0, 10).map((record) => {
                  // อยู่บ้าน = ไม่ได้ไปทำงาน จึงไม่ขึ้นว่า "เข้างาน" และไม่มีออกงานคู่กัน
                  const entry = describeCheckin(record);
                  const isHome = entry.kind === "home";
                  const isIn = entry.kind === "in";
                  return (
                    <li
                      key={record.id}
                      className="flex items-center justify-between gap-3 py-3 first:pt-0 last:pb-0"
                    >
                      <div className="flex min-w-0 items-center gap-3">
                        <span
                          className={cn(
                            "flex size-9 shrink-0 items-center justify-center rounded-lg",
                            isHome
                              ? "bg-purple-500/10 text-purple-700 dark:text-purple-300"
                              : isIn
                                ? "bg-success/10 text-success"
                                : "bg-orange-500/10 text-orange-600 dark:text-orange-400",
                          )}
                        >
                          {isHome ? (
                            <House className="size-4.5" />
                          ) : isIn ? (
                            <LogIn className="size-4.5" />
                          ) : (
                            <LogOut className="size-4.5" />
                          )}
                        </span>
                        <div className="min-w-0">
                          <div className="flex items-center gap-2">
                            <span className="text-sm font-medium">{entry.label}</span>
                            <Badge variant={entry.badge} className="text-[10px]">
                              {record.office_name || (record.within_geofence ? "ในเขต" : "นอกเขต")}
                            </Badge>
                          </div>
                          <div className="text-muted-foreground mt-0.5 flex flex-wrap items-center gap-x-2 text-xs">
                            <span>{thaiDateTime(record.timestamp)}</span>
                            {record.distance_km != null && (
                              <span>
                                ห่าง{" "}
                                {record.distance_km < 1
                                  ? `${Math.round(record.distance_km * 1000)} ม.`
                                  : `${record.distance_km.toFixed(2)} กม.`}
                              </span>
                            )}
                          </div>
                        </div>
                      </div>
                    </li>
                  );
                })}
              </ul>
            )}
          </CardContent>
        </Card>
      </div>
    </AppLayout>
  );
}

export default function DashboardPage() {
  const me = getEmployee();
  const [value, setValue] = useState(dayjs());
  const [days, setDays] = useState([]);
  const [selectedDay, setSelectedDay] = useState(null);
  const [loading, setLoading] = useState(false);
  const [err, setErr] = useState("");

  useEffect(() => {
    if (!me?.is_manager) return;
    setLoading(true);
    setErr("");
    getTeamCalendar(value.year(), value.month() + 1)
      .then((response) => setDays(response.days))
      .catch((error) => setErr(String(error.message || error)))
      .finally(() => setLoading(false));
  }, [value.year(), value.month(), me?.is_manager]);

  const byDate = useMemo(() => {
    const result = {};
    days.forEach((day) => {
      result[day.date] = day;
    });
    return result;
  }, [days]);

  const activeEmployees = useMemo(() => {
    const ids = new Set();
    days.forEach((day) => day.people.forEach((person) => ids.add(person.employee_id)));
    return ids.size;
  }, [days]);

  // ปฏิทินคืนวันที่ "ไม่มีคนลงเวลาแต่มีคนขาด" มาด้วย จึงนับเฉพาะวันที่มีคนลงเวลาจริง
  const daysWithCheckins = useMemo(
    () => days.filter((day) => day.people.length > 0).length,
    [days],
  );

  // คนที่ยังไม่ยืนยันตัวตน "ของวันนี้" — เฉพาะตอนดูเดือนปัจจุบัน
  // เดือนอื่นให้ไปดูรายวันในปฏิทินเอา ไม่ต้องเอาของวันนี้มาแปะค้างไว้
  const todayMissing = useMemo(() => {
    const today = dayjs();
    if (!today.isSame(value, "month")) return [];
    return byDate[today.format("YYYY-MM-DD")]?.missing ?? [];
  }, [byDate, value]);

  function openDay(current) {
    const day = byDate[current.format("YYYY-MM-DD")];
    // เปิดได้ทั้งวันที่มีคนลงเวลา และวันที่มีแต่คนขาด — วันที่ขาดยิ่งต้องกดดู
    if (day?.people?.length || day?.missing?.length) setSelectedDay(day);
  }

  /** เนื้อหาในช่องวัน — จอเล็กโชว์แค่จำนวนคน (ชื่อจะล้นจนอ่านไม่ออก)
   *  จอ sm ขึ้นไปค่อยไล่ชื่อพร้อมแท็กสถานที่ */
  function renderCell(date) {
    const day = byDate[date.format("YYYY-MM-DD")];
    if (!day?.people?.length && !day?.missing?.length) return null;

    const visible = day.people.slice(0, 3);
    const missingCount = day.missing?.length ?? 0;
    return (
      <div className="min-w-0 space-y-1">
        {missingCount > 0 && (
          <Badge
            variant="outline"
            className="border-destructive/50 text-destructive max-w-full gap-1 truncate text-[10px] font-semibold"
          >
            <UserX className="size-3 shrink-0" />
            ไม่ยืนยันตัวตน {missingCount}
          </Badge>
        )}

        {day.people.length > 0 && (
          <Badge variant="info" className="sm:hidden">
            {day.people.length} คน
          </Badge>
        )}

        <div className="hidden space-y-1 sm:block">
          {visible.map((person) => (
            <div key={person.employee_id} className="min-w-0">
              <div className="flex min-w-0 items-center gap-1 text-[11px] font-medium">
                <User className="size-3 shrink-0" />
                <span className="truncate">{person.full_name}</span>
              </div>
              {person.locations.slice(0, 1).map((location) => (
                <Badge
                  key={location}
                  variant={locationVariant(location)}
                  className="mt-0.5 max-w-full truncate text-[10px]"
                >
                  {location}
                </Badge>
              ))}
            </div>
          ))}
          {day.people.length > visible.length && (
            <div className="text-muted-foreground text-[10px]">
              +{day.people.length - visible.length} คน
            </div>
          )}
        </div>
      </div>
    );
  }

  // หน้าแรกของพนักงานทั่วไป — แสดงข้อมูลส่วนตัว ประวัติเข้างาน และการ์ดดาวน์โหลดแอป
  if (!me?.is_manager) {
    return <EmployeeDashboard me={me} />;
  }

  return (
    <AppLayout>
      <div className="space-y-4">
        <div className="hidden lg:block">
          <h2 className="text-2xl font-bold">ปฏิทินเข้างาน</h2>
          <p className="text-muted-foreground text-sm">
            ชื่อที่แสดงคือพนักงานที่ลงเวลาในวันนั้น กดวันที่เพื่อดูเวลาเข้า–ออก
          </p>
        </div>
        <p className="text-muted-foreground text-sm lg:hidden">
          กดวันที่เพื่อดูรายชื่อและเวลาเข้า–ออก
        </p>

        <div className="grid grid-cols-2 gap-3 sm:gap-4 lg:grid-cols-3">
          {loading && days.length === 0 ? (
            <>
              <StatCardSkeleton />
              <StatCardSkeleton />
              <StatCardSkeleton />
            </>
          ) : (
            <>
              <StatCard
                icon={<Users />}
                label={`พนักงานที่ลงเวลา (${value.format("MMMM YYYY")})`}
                value={activeEmployees}
                suffix="คน"
              />
              <StatCard
                icon={<CalendarDays />}
                label="วันที่มีการลงเวลา"
                value={daysWithCheckins}
                suffix="วัน"
                tone="success"
              />
              <StatCard
                icon={<ShieldAlert />}
                label="วันนี้ยังไม่ยืนยันตัวตน"
                value={todayMissing.length}
                suffix="คน"
                tone={todayMissing.length > 0 ? "destructive" : "success"}
              />
            </>
          )}
        </div>

        {err && (
          <Alert variant="destructive">
            <CircleAlert />
            <AlertDescription className="text-foreground">{err}</AlertDescription>
          </Alert>
        )}

        {todayMissing.length > 0 && (
          <UnverifiedDutyAlert
            title={`${UNVERIFIED_TITLE} ${todayMissing.length} คน — ${dayjs().format("D MMMM YYYY")}`}
            warning={UNVERIFIED_DUTY_WARNING}
          >
            <ul className="mt-0.5 space-y-1">
              {todayMissing.map((person) => (
                <li key={person.employee_id} className="flex flex-wrap items-center gap-1.5">
                  <span className="font-semibold">{person.full_name}</span>
                  <span className="opacity-80">({person.employee_code})</span>
                  {!person.face_enrolled && (
                    <Badge
                      variant="outline"
                      className="border-destructive/50 text-destructive text-[10px]"
                    >
                      {UNVERIFIED_REASON_NO_FACE}
                    </Badge>
                  )}
                </li>
              ))}
            </ul>
          </UnverifiedDutyAlert>
        )}

        <Card>
          <CardContent>
            {loading && days.length === 0 ? (
              <MonthCalendarSkeleton />
            ) : (
              <MonthCalendar
                value={value}
                onChange={setValue}
                onSelectDate={openDay}
                renderCell={renderCell}
              />
            )}
          </CardContent>
        </Card>
      </div>

      <Dialog open={Boolean(selectedDay)} onOpenChange={(open) => !open && setSelectedDay(null)}>
        <DialogContent className="sm:max-w-2xl">
          <DialogHeader>
            <DialogTitle>
              {selectedDay
                ? `ผู้ที่ลงเวลา — ${dayjs(selectedDay.date).format("D MMMM YYYY")}`
                : ""}
            </DialogTitle>
            <DialogDescription className="sr-only">
              รายชื่อพนักงานที่ลงเวลาในวันที่เลือก พร้อมเวลาเข้า–ออกและสถานที่
            </DialogDescription>
          </DialogHeader>

          <div className="-mx-1 max-h-[65vh] space-y-4 overflow-y-auto px-1">
            {selectedDay?.missing?.length > 0 && (
              <UnverifiedDutyAlert
                title={`${UNVERIFIED_TITLE} ${selectedDay.missing.length} คน`}
                warning={UNVERIFIED_DUTY_WARNING}
              >
                <ul className="mt-0.5 space-y-1">
                  {selectedDay.missing.map((person) => (
                    <li
                      key={person.employee_id}
                      className="flex flex-wrap items-center gap-1.5"
                    >
                      <span className="font-semibold">{person.full_name}</span>
                      <span className="opacity-80">({person.employee_code})</span>
                      {!person.face_enrolled && (
                        <Badge
                          variant="outline"
                          className="border-destructive/50 text-destructive text-[10px]"
                        >
                          {UNVERIFIED_REASON_NO_FACE}
                        </Badge>
                      )}
                      <Link
                        to={`/employees/${person.employee_id}/history`}
                        className="underline opacity-80 hover:opacity-100"
                      >
                        ดูประวัติ
                      </Link>
                    </li>
                  ))}
                </ul>
              </UnverifiedDutyAlert>
            )}

            {!selectedDay?.people?.length ? (
              <EmptyState title="ไม่มีผู้ลงเวลาในวันนี้" />
            ) : (
              <ul className="divide-border divide-y">
                {selectedDay.people.map((person) => (
                  <li key={person.employee_id} className="flex gap-3 py-3 first:pt-0 last:pb-0">
                    <Avatar className="size-10 shrink-0">
                      <AvatarFallback>
                        <User className="size-5" />
                      </AvatarFallback>
                    </Avatar>
                    <div className="min-w-0 flex-1 space-y-1.5">
                      <div className="flex flex-wrap items-center gap-2">
                        <span className="font-medium">{person.full_name}</span>
                        <Badge variant="secondary">{person.employee_code}</Badge>
                        {/* ลงเวลาแล้วแต่ยังไม่เคยลงทะเบียนใบหน้าไว้เทียบ — ยืนยันตัวตนได้ไม่เต็มร้อย */}
                        {person.face_enrolled === false && (
                          <Badge
                            variant="outline"
                            className="border-destructive/50 text-destructive gap-1"
                          >
                            <ShieldAlert className="size-3" />
                            {UNVERIFIED_REASON_NO_FACE}
                          </Badge>
                        )}
                      </div>
                      <div className="text-muted-foreground flex flex-wrap gap-x-4 gap-y-1 text-sm">
                        {person.home_only ? (
                          <span className="inline-flex items-center gap-1 text-purple-700 dark:text-purple-300">
                            <House className="size-3.5" /> อยู่บ้าน — ไม่ได้ไปทำงาน
                          </span>
                        ) : (
                          <>
                            <span className="text-success inline-flex items-center gap-1">
                              <LogIn className="size-3.5" /> เข้า {thaiTime(person.first_in)}
                            </span>
                            <span className="inline-flex items-center gap-1 text-orange-600 dark:text-orange-400">
                              <LogOut className="size-3.5" /> ออก {thaiTime(person.last_out)}
                            </span>
                          </>
                        )}
                        <span className="inline-flex items-center gap-1">
                          <Clock className="size-3.5" /> ลงเวลาทั้งหมด {person.count} ครั้ง
                        </span>
                      </div>
                      <div className="flex flex-wrap items-center gap-1.5">
                        <MapPin className="text-muted-foreground size-3.5 shrink-0" />
                        {person.locations.map((location) => (
                          <Badge key={location} variant={locationVariant(location)}>
                            {location}
                          </Badge>
                        ))}
                      </div>
                      <Button asChild variant="outline" size="sm" className="mt-1">
                        <Link to={`/employees/${person.employee_id}/history`}>
                          <History /> ดูประวัติพนักงาน
                        </Link>
                      </Button>
                    </div>
                  </li>
                ))}
              </ul>
            )}
          </div>
        </DialogContent>
      </Dialog>
    </AppLayout>
  );
}

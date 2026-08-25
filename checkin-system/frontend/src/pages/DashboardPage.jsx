import React, { useEffect, useMemo, useState } from "react";
import dayjs from "dayjs";
import utc from "dayjs/plugin/utc";
import {
  CalendarDays,
  CircleAlert,
  Clock,
  Info,
  LogIn,
  LogOut,
  MapPin,
  User,
  Users,
} from "lucide-react";
import { Link } from "react-router-dom";
import { getEmployee, getTeamCalendar, getMyCheckins } from "../api";
import AppLayout from "../components/AppLayout.jsx";
import AppDownloadCard from "../components/AppDownloadCard.jsx";
import MonthCalendar from "../components/MonthCalendar.jsx";
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
import { Skeleton } from "@/components/ui/skeleton";
import { StatCard } from "@/components/ui/stat-card";
import { cn } from "@/lib/utils";

dayjs.extend(utc);

// เวลาไทย = UTC+7 (นาที) — ฝั่ง API ส่ง ISO ที่ติด offset มาแล้ว ตรงนี้บังคับอีกชั้น
// เพื่อให้เห็นเวลาไทยเหมือนกันหมด ต่อให้เปิดจากเครื่อง/มือถือที่ตั้ง timezone อื่นไว้
const THAI_OFFSET_MINUTES = 7 * 60;

function thaiTime(iso) {
  if (!iso) return "–";
  return dayjs(iso).utcOffset(THAI_OFFSET_MINUTES).format("HH:mm");
}

function locationVariant(location) {
  if (location === "อยู่ที่บ้าน") return "purple";
  if (location === "นอกเขต") return "warning";
  return "success";
}

function EmployeeDashboard({ me }) {
  const [checkins, setCheckins] = useState([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let active = true;
    getMyCheckins()
      .then((data) => active && setCheckins(Array.isArray(data) ? data : []))
      .catch(() => active && setCheckins([]))
      .finally(() => active && setLoading(false));
    return () => {
      active = false;
    };
  }, []);

  return (
    <AppLayout>
      <div className="space-y-4">
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

            {loading ? (
              <div className="space-y-2">
                <Skeleton className="h-14 w-full rounded-lg" />
                <Skeleton className="h-14 w-full rounded-lg" />
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
                  const isIn = record.kind === "in";
                  return (
                    <li
                      key={record.id}
                      className="flex items-center justify-between gap-3 py-3 first:pt-0 last:pb-0"
                    >
                      <div className="flex min-w-0 items-center gap-3">
                        <span
                          className={cn(
                            "flex size-9 shrink-0 items-center justify-center rounded-lg",
                            isIn
                              ? "bg-success/10 text-success"
                              : "bg-orange-500/10 text-orange-600 dark:text-orange-400",
                          )}
                        >
                          {isIn ? <LogIn className="size-4.5" /> : <LogOut className="size-4.5" />}
                        </span>
                        <div className="min-w-0">
                          <div className="flex items-center gap-2">
                            <span className="text-sm font-medium">
                              {isIn ? "เข้างาน" : "ออกงาน"}
                            </span>
                            <Badge
                              variant={isIn ? "success" : "warning"}
                              className="text-[10px]"
                            >
                              {record.office_name || (record.within_geofence ? "ในเขต" : "นอกเขต")}
                            </Badge>
                          </div>
                          <div className="text-muted-foreground mt-0.5 flex flex-wrap items-center gap-x-2 text-xs">
                            <span>
                              {dayjs(record.timestamp)
                                .utcOffset(THAI_OFFSET_MINUTES)
                                .format("D MMM YYYY HH:mm น.")}
                            </span>
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

  function openDay(current) {
    const day = byDate[current.format("YYYY-MM-DD")];
    if (day?.people?.length) setSelectedDay(day);
  }

  /** เนื้อหาในช่องวัน — จอเล็กโชว์แค่จำนวนคน (ชื่อจะล้นจนอ่านไม่ออก)
   *  จอ sm ขึ้นไปค่อยไล่ชื่อพร้อมแท็กสถานที่ */
  function renderCell(date) {
    const day = byDate[date.format("YYYY-MM-DD")];
    if (!day?.people?.length) return null;

    const visible = day.people.slice(0, 3);
    return (
      <div className="min-w-0 space-y-1">
        <Badge variant="info" className="sm:hidden">
          {day.people.length} คน
        </Badge>

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
          <StatCard
            icon={<Users />}
            label={`พนักงานที่ลงเวลา (${value.format("MMMM YYYY")})`}
            value={activeEmployees}
            suffix="คน"
          />
          <StatCard
            icon={<CalendarDays />}
            label="วันที่มีการลงเวลา"
            value={days.length}
            suffix="วัน"
            tone="success"
          />
        </div>

        {err && (
          <Alert variant="destructive">
            <CircleAlert />
            <AlertDescription className="text-foreground">{err}</AlertDescription>
          </Alert>
        )}

        <Card>
          <CardContent>
            {loading ? (
              <div className="space-y-3">
                <Skeleton className="h-8 w-48" />
                <Skeleton className="h-[320px] w-full sm:h-[520px]" />
              </div>
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

          <div className="-mx-1 max-h-[65vh] overflow-y-auto px-1">
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
                      </div>
                      <div className="text-muted-foreground flex flex-wrap gap-x-4 gap-y-1 text-sm">
                        <span className="text-success inline-flex items-center gap-1">
                          <LogIn className="size-3.5" /> เข้า {thaiTime(person.first_in)}
                        </span>
                        <span className="inline-flex items-center gap-1 text-orange-600 dark:text-orange-400">
                          <LogOut className="size-3.5" /> ออก {thaiTime(person.last_out)}
                        </span>
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

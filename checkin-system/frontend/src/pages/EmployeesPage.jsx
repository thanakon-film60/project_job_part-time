import React, { useEffect, useMemo, useRef, useState } from "react";
import { ChevronRight, CircleAlert, IdCard, Mail, Plus, Search, ShieldCheck, Users } from "lucide-react";
import { Link } from "react-router-dom";
import AppLayout from "@/components/AppLayout.jsx";
import EmployeeFaceAvatar from "@/components/EmployeeFaceAvatar.jsx";
import { getEmployee, getEmployeeFaces, getEmployees } from "@/api";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { EmptyState } from "@/components/ui/empty-state";
import { Input } from "@/components/ui/input";
import { Skeleton, StatCardSkeleton } from "@/components/ui/skeleton";
import { StatCard } from "@/components/ui/stat-card";

function EmployeeListSkeleton() {
  return (
    <Card className="gap-0 py-0">
      {[0, 1, 2].map((index) => (
        <div key={index} className="flex items-center gap-3 border-b p-4 last:border-b-0">
          <Skeleton className="size-12 rounded-full" />
          <div className="flex-1 space-y-2"><Skeleton className="h-4 w-40" /><Skeleton className="h-3 w-56" /></div>
          <Skeleton className="size-8 rounded-md" />
        </div>
      ))}
    </Card>
  );
}

function EmployeeListItem({ employee }) {
  const [faces, setFaces] = useState([]);
  const [faceLoading, setFaceLoading] = useState(true);

  useEffect(() => {
    let active = true;
    getEmployeeFaces(employee.id)
      .then((records) => active && setFaces(records))
      .catch(() => active && setFaces([]))
      .finally(() => active && setFaceLoading(false));
    return () => { active = false; };
  }, [employee.id]);

  return (
    <Link
      to={`/employees/${employee.id}/history`}
      className="group flex items-center gap-3 border-b p-3 transition-colors last:border-b-0 hover:bg-muted/60 focus-visible:bg-muted/60 focus-visible:outline-none sm:gap-4 sm:p-4"
      aria-label={`ดูรายละเอียด ${employee.full_name}`}
    >
      {faceLoading ? <Skeleton className="size-12 shrink-0 rounded-full sm:size-14" /> : (
        <EmployeeFaceAvatar faceRecordId={faces[0]?.id} className="size-12 border sm:size-14" />
      )}
      <div className="min-w-0 flex-1">
        <div className="flex flex-wrap items-center gap-2">
          <h3 className="truncate font-semibold">{employee.full_name}</h3>
          <Badge variant={faces.length ? "success" : "warning"}>{faces.length ? `${faces.length} รูป` : "ยังไม่มีรูป"}</Badge>
          {!employee.profile_complete && <Badge variant="warning">ข้อมูลยังไม่ครบ</Badge>}
        </div>
        <div className="text-muted-foreground mt-1 flex flex-wrap gap-x-4 gap-y-1 text-xs sm:text-sm">
          <span className="inline-flex items-center gap-1"><IdCard className="size-3.5" /> {employee.employee_code}</span>
          <span className="inline-flex min-w-0 items-center gap-1"><Mail className="size-3.5 shrink-0" /><span className="truncate">{employee.email}</span></span>
          {(employee.department || employee.position) && <span>{[employee.department, employee.position].filter(Boolean).join(" · ")}</span>}
        </div>
      </div>
      <div className="flex shrink-0 items-center gap-1 text-sm font-medium text-primary">
        <span className="hidden sm:inline">ดูรายละเอียด</span>
        <ChevronRight className="size-5 transition-transform group-hover:translate-x-0.5" />
      </div>
    </Link>
  );
}

export default function EmployeesPage() {
  const me = getEmployee();
  const [employees, setEmployees] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [query, setQuery] = useState("");
  const listRef = useRef(null);

  useEffect(() => {
    getEmployees().then(setEmployees).catch((err) => setError(err.message || "โหลดข้อมูลพนักงานไม่สำเร็จ")).finally(() => setLoading(false));
  }, []);

  const staff = useMemo(() => employees.filter((employee) => !employee.is_manager), [employees]);
  const visibleStaff = useMemo(() => {
    const keyword = query.trim().toLocaleLowerCase("th");
    if (!keyword) return staff;
    return staff.filter((employee) => [employee.full_name, employee.employee_code, employee.email, employee.department, employee.position]
      .some((value) => String(value || "").toLocaleLowerCase("th").includes(keyword)));
  }, [query, staff]);

  function showAllEmployees() {
    setQuery("");
    window.requestAnimationFrame(() => {
      listRef.current?.scrollIntoView({ behavior: "smooth", block: "start" });
      listRef.current?.focus({ preventScroll: true });
    });
  }

  if (!me?.is_manager) {
    return <AppLayout><Alert variant="destructive"><CircleAlert /><AlertDescription className="text-foreground">หน้านี้สำหรับ Boss เท่านั้น</AlertDescription></Alert></AppLayout>;
  }

  return (
    <AppLayout>
      <div className="space-y-4">
        <div className="hidden items-start justify-between gap-3 lg:flex">
          <div><h2 className="text-2xl font-bold">ข้อมูลพนักงาน</h2><p className="text-muted-foreground text-sm">กดรายชื่อเพื่อดูรายละเอียด ประวัติ และแก้ไขข้อมูล</p></div>
          <Button asChild><Link to="/employees/register"><Plus /> ลงทะเบียนพนักงาน</Link></Button>
        </div>
        <Button asChild className="w-full lg:hidden"><Link to="/employees/register"><Plus /> ลงทะเบียนพนักงาน</Link></Button>

        <div className="grid grid-cols-2 gap-3 sm:gap-4 lg:grid-cols-3">
          {loading ? <><StatCardSkeleton /><StatCardSkeleton /></> : <>
            <StatCard icon={<Users />} label="พนักงานทั้งหมด" value={staff.length} suffix="คน" onClick={showAllEmployees} aria-label="ดูรายชื่อพนักงานทั้งหมด" />
            <StatCard icon={<ShieldCheck />} label="บัญชี Boss" value={employees.filter((employee) => employee.is_manager).length} suffix="บัญชี" tone="success" />
          </>}
        </div>

        {error && <Alert variant="destructive"><CircleAlert /><AlertDescription className="text-foreground">{error}</AlertDescription></Alert>}

        <section ref={listRef} tabIndex={-1} className="scroll-mt-20 space-y-3 outline-none" aria-labelledby="employee-list-title">
          <div className="flex flex-col justify-between gap-3 sm:flex-row sm:items-center">
            <div><h2 id="employee-list-title" className="text-lg font-semibold">รายชื่อพนักงานทั้งหมด</h2><p className="text-muted-foreground text-sm">แสดง {visibleStaff.length} จาก {staff.length} คน</p></div>
            <div className="relative w-full sm:w-80"><Search className="text-muted-foreground absolute top-1/2 left-3 size-4 -translate-y-1/2" /><Input value={query} onChange={(event) => setQuery(event.target.value)} className="pl-9" placeholder="ค้นหาชื่อ รหัส อีเมล แผนก..." /></div>
          </div>

          {loading ? <EmployeeListSkeleton /> : visibleStaff.length === 0 ? (
            <Card><CardContent><EmptyState title={staff.length ? "ไม่พบพนักงานที่ค้นหา" : "ยังไม่มีพนักงานในระบบ"} /></CardContent></Card>
          ) : (
            <Card className="gap-0 overflow-hidden py-0">
              {visibleStaff.map((employee) => <EmployeeListItem key={employee.id} employee={employee} />)}
            </Card>
          )}
        </section>
      </div>
    </AppLayout>
  );
}

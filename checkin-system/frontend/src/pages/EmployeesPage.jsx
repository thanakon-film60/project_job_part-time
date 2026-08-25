import React, { useEffect, useMemo, useState } from "react";
import {
  CircleAlert,
  CircleCheck,
  IdCard,
  Mail,
  ShieldCheck,
  TriangleAlert,
  User,
  Users,
} from "lucide-react";
import AppLayout from "../components/AppLayout.jsx";
import {
  fetchFacePhoto,
  getEmployee,
  getEmployeeFaces,
  getEmployees,
} from "../api";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent } from "@/components/ui/card";
import { EmptyState } from "@/components/ui/empty-state";
import { ImagePreview } from "@/components/ui/image-preview";
import { Skeleton } from "@/components/ui/skeleton";
import { StatCard } from "@/components/ui/stat-card";
import { cn } from "@/lib/utils";

function FacePhoto({ record, employeeName, featured = false }) {
  const [url, setUrl] = useState("");
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    let active = true;
    let objectUrl = "";
    fetchFacePhoto(record.id)
      .then((value) => {
        objectUrl = value;
        if (active) setUrl(value);
        else URL.revokeObjectURL(value);
      })
      .catch(() => active && setFailed(true));

    return () => {
      active = false;
      if (objectUrl) URL.revokeObjectURL(objectUrl);
    };
  }, [record.id]);

  const frame = featured ? "aspect-[4/5] w-full" : "size-20 sm:size-24";

  if (failed) {
    return (
      <div
        className={cn(
          "bg-muted text-muted-foreground flex flex-col items-center justify-center gap-1 rounded-lg text-xs",
          frame,
        )}
      >
        <TriangleAlert className="size-5" />
        <span>โหลดรูปไม่ได้</span>
      </div>
    );
  }

  if (!url) return <Skeleton className={cn("rounded-lg", frame)} />;

  return (
    <ImagePreview
      src={url}
      alt={`รูปยืนยันตัวตนของ ${employeeName}`}
      wrapperClassName={frame}
      className={featured ? "h-full" : "size-full"}
    />
  );
}

function EmployeeCard({ employee }) {
  const [faces, setFaces] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

  useEffect(() => {
    let active = true;
    getEmployeeFaces(employee.id)
      .then((records) => active && setFaces(records))
      .catch((err) => active && setError(err.message || "โหลดรูปใบหน้าไม่สำเร็จ"))
      .finally(() => active && setLoading(false));
    return () => {
      active = false;
    };
  }, [employee.id]);

  const latestFace = faces[0];

  return (
    <Card>
      <CardContent className="grid gap-4 sm:grid-cols-[minmax(0,180px)_1fr] sm:gap-5">
        <div className="relative mx-auto w-40 sm:mx-0 sm:w-full">
          {loading ? (
            <Skeleton className="aspect-[4/5] w-full rounded-lg" />
          ) : latestFace ? (
            <FacePhoto record={latestFace} employeeName={employee.full_name} featured />
          ) : (
            <div className="bg-muted text-muted-foreground flex aspect-[4/5] w-full flex-col items-center justify-center gap-1 rounded-lg text-xs">
              <User className="size-7" />
              <span>ไม่มีรูปยืนยันตัวตน</span>
            </div>
          )}
          <Badge
            variant={latestFace ? "success" : "warning"}
            className="absolute top-2 left-2 shadow-sm backdrop-blur"
          >
            {latestFace ? "พร้อมยืนยันตัวตน" : "ยังไม่มีรูปใบหน้า"}
          </Badge>
        </div>

        <div className="min-w-0 space-y-3">
          <div className="space-y-2">
            <h3 className="text-lg font-semibold">{employee.full_name}</h3>
            <div className="flex flex-wrap gap-2">
              <Badge variant="info">พนักงาน</Badge>
              <Badge variant={latestFace ? "success" : "warning"}>
                {latestFace ? `รูปยืนยัน ${faces.length} รูป` : "ยังไม่ได้ลงทะเบียนใบหน้า"}
              </Badge>
            </div>
          </div>

          <div className="space-y-1.5 text-sm">
            <p className="flex items-center gap-2">
              <IdCard className="text-muted-foreground size-4 shrink-0" />
              รหัสพนักงาน: <strong>{employee.employee_code}</strong>
            </p>
            <p className="flex min-w-0 items-center gap-2">
              <Mail className="text-muted-foreground size-4 shrink-0" />
              <span className="truncate">อีเมล: {employee.email}</span>
            </p>
            {employee.created_at && (
              <p className="text-muted-foreground text-xs">
                ลงทะเบียนเมื่อ {new Date(employee.created_at).toLocaleString("th-TH")}
              </p>
            )}
          </div>

          {error && (
            <Alert variant="destructive">
              <CircleAlert />
              <AlertDescription className="text-foreground">{error}</AlertDescription>
            </Alert>
          )}

          {faces.length > 1 && (
            <div className="space-y-2">
              <p className="text-muted-foreground text-xs">รูปใบหน้าเพิ่มเติม</p>
              <div className="flex flex-wrap gap-2">
                {faces.slice(1).map((face) => (
                  <FacePhoto key={face.id} record={face} employeeName={employee.full_name} />
                ))}
              </div>
            </div>
          )}

          {latestFace && (
            <p className="text-muted-foreground flex items-center gap-1.5 text-xs">
              <CircleCheck className="text-success size-3.5 shrink-0" />
              รูปล่าสุดบันทึกเมื่อ {new Date(latestFace.created_at).toLocaleString("th-TH")}
            </p>
          )}
        </div>
      </CardContent>
    </Card>
  );
}

export default function EmployeesPage() {
  const me = getEmployee();
  const [employees, setEmployees] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

  useEffect(() => {
    getEmployees()
      .then(setEmployees)
      .catch((err) => setError(err.message || "โหลดข้อมูลพนักงานไม่สำเร็จ"))
      .finally(() => setLoading(false));
  }, []);

  const staff = useMemo(
    () => employees.filter((employee) => !employee.is_manager),
    [employees],
  );

  if (!me?.is_manager) {
    return (
      <AppLayout>
        <Alert variant="destructive">
          <CircleAlert />
          <AlertDescription className="text-foreground">
            หน้านี้สำหรับ Boss เท่านั้น
          </AlertDescription>
        </Alert>
      </AppLayout>
    );
  }

  return (
    <AppLayout>
      <div className="space-y-4">
        <div className="hidden lg:block">
          <h2 className="text-2xl font-bold">ข้อมูลพนักงาน</h2>
          <p className="text-muted-foreground text-sm">
            รายชื่อและรูปใบหน้าที่ลงทะเบียนไว้สำหรับยืนยันตัวตน
          </p>
        </div>

        <div className="grid grid-cols-2 gap-3 sm:gap-4 lg:grid-cols-3">
          <StatCard icon={<Users />} label="พนักงานทั้งหมด" value={staff.length} suffix="คน" />
          <StatCard
            icon={<ShieldCheck />}
            label="บัญชี Boss"
            value={employees.filter((employee) => employee.is_manager).length}
            suffix="บัญชี"
            tone="success"
          />
        </div>

        {error && (
          <Alert variant="destructive">
            <CircleAlert />
            <AlertDescription className="text-foreground">{error}</AlertDescription>
          </Alert>
        )}

        {loading ? (
          <div className="space-y-4">
            {[0, 1].map((i) => (
              <Card key={i}>
                <CardContent className="grid gap-4 sm:grid-cols-[minmax(0,180px)_1fr]">
                  <Skeleton className="mx-auto aspect-[4/5] w-40 rounded-lg sm:mx-0 sm:w-full" />
                  <div className="space-y-3">
                    <Skeleton className="h-6 w-1/2" />
                    <Skeleton className="h-4 w-2/3" />
                    <Skeleton className="h-4 w-1/3" />
                  </div>
                </CardContent>
              </Card>
            ))}
          </div>
        ) : staff.length === 0 ? (
          <Card>
            <CardContent>
              <EmptyState title="ยังไม่มีพนักงานในระบบ" />
            </CardContent>
          </Card>
        ) : (
          <div className="space-y-4">
            {staff.map((employee) => (
              <EmployeeCard key={employee.id} employee={employee} />
            ))}
          </div>
        )}
      </div>
    </AppLayout>
  );
}

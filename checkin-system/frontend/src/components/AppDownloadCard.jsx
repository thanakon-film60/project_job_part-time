import React, { useEffect, useState } from "react";
import dayjs from "dayjs";
import utc from "dayjs/plugin/utc";
import { toast } from "sonner";
import { Download, Link2, Smartphone, TriangleAlert } from "lucide-react";
import {
  appDownloadUrl,
  bossAppDownloadUrl,
  getAppInfo,
  getBossAppInfo,
} from "../api";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";

dayjs.extend(utc);

const THAI_OFFSET_MINUTES = 7 * 60;

function prettySize(bytes) {
  if (!bytes) return "";
  const mb = bytes / (1024 * 1024);
  return `${mb.toFixed(1)} MB`;
}

/** การ์ดดาวน์โหลดแอป Flutter — โชว์บนหน้าแรกของพนักงาน
 *
 *  ข้อมูลไฟล์มาจาก GET /app/info (backend อ่านจาก storage/app)
 *  ถ้ายังไม่เคย build APK จะขึ้นข้อความบอกว่ายังไม่มีไฟล์ แทนที่จะโชว์ปุ่มเสีย ๆ
 */
export default function AppDownloadCard({ variant = "employee" }) {
  const isBossApp = variant === "boss";
  const [info, setInfo] = useState(null);
  const [loading, setLoading] = useState(true);
  const url = isBossApp ? bossAppDownloadUrl() : appDownloadUrl();

  useEffect(() => {
    let alive = true;
    const loadInfo = isBossApp ? getBossAppInfo : getAppInfo;
    loadInfo()
      .then((data) => alive && setInfo(data))
      .catch(() => alive && setInfo({ available: false }))
      .finally(() => alive && setLoading(false));
    return () => {
      alive = false;
    };
  }, [isBossApp]);

  async function copyLink() {
    try {
      await navigator.clipboard.writeText(url);
      toast.success("คัดลอกลิงก์แล้ว", {
        description: "เปิดลิงก์นี้ในมือถือเพื่อโหลดแอป",
      });
    } catch {
      toast.info(url);
    }
  }

  return (
    <Card>
      <CardContent className="space-y-4">
        <div className="flex items-start gap-3 sm:gap-4">
          <img
            src="/logo-checkin.png"
            alt=""
            aria-hidden="true"
            className="size-12 shrink-0 rounded-xl object-contain sm:size-14"
          />
          <div className="min-w-0">
            <h3 className="flex items-center gap-2 text-base font-semibold sm:text-lg">
              <Smartphone className="size-4.5 shrink-0" />
              <span className="min-w-0">
                {isBossApp ? "แอปหัวหน้า THANAKON-BOX" : "แอปเช็คอิน THANAKON-ROOM"}
              </span>
            </h3>
            <p className="text-muted-foreground mt-0.5 text-sm">
              {isBossApp
                ? "สำหรับหัวหน้าดูภาพรวมทีม ข้อมูลพนักงาน และแผนที่ติดตามจากมือถือ"
                : "ใช้เช็คอินด้วย GPS + สแกนใบหน้า จากมือถือได้โดยตรง"}
            </p>
          </div>
        </div>

        {loading ? (
          <div className="space-y-4">
            <div className="flex flex-wrap gap-2">
              <Skeleton className="h-5 w-16 rounded-md" />
              <Skeleton className="h-5 w-24 rounded-md" />
              <Skeleton className="h-5 w-20 rounded-md" />
              <Skeleton className="h-5 w-32 rounded-md" />
            </div>
            <div className="flex flex-col gap-2 sm:flex-row">
              <Skeleton className="h-11 w-full rounded-md sm:w-48" />
              <Skeleton className="h-11 w-full rounded-md sm:w-36" />
            </div>
            <div className="space-y-1.5 pt-1">
              <Skeleton className="h-3.5 w-full" />
              <Skeleton className="h-3.5 w-4/5" />
            </div>
          </div>
        ) : !info?.available ? (
          <Alert variant="warning">
            <TriangleAlert />
            <AlertTitle>ยังไม่มีไฟล์ติดตั้งบนเซิร์ฟเวอร์</AlertTitle>
            <AlertDescription>
              {isBossApp
                ? "ยังไม่ได้วาง APK ของแอปบอสไว้ที่ backend/storage/boss-app"
                : "ผู้ดูแลระบบต้อง build แอปก่อน (deploy\\windows-server\\build-flutter-apk.ps1) แล้วปุ่มดาวน์โหลดจะขึ้นเอง"}
            </AlertDescription>
          </Alert>
        ) : (
          <>
            <div className="flex flex-wrap gap-2">
              <Badge variant="success">Android</Badge>
              {info.version && <Badge variant="secondary">เวอร์ชัน {info.version}</Badge>}
              {info.size_bytes ? (
                <Badge variant="secondary">{prettySize(info.size_bytes)}</Badge>
              ) : null}
              {/* บอกรุ่นขั้นต่ำไว้ด้วย — เครื่องเก่ากว่านี้โหลดไปก็ติดตั้งไม่ได้ */}
              {info.min_android && (
                <Badge variant="secondary">ต้องใช้ Android {info.min_android} ขึ้นไป</Badge>
              )}
              {info.built_at && (
                <Badge variant="secondary">
                  อัปเดต{" "}
                  {dayjs(info.built_at)
                    .utcOffset(THAI_OFFSET_MINUTES)
                    .format("D MMM YYYY HH:mm")}
                </Badge>
              )}
            </div>

            <div className="flex flex-col gap-2 sm:flex-row">
              {/* ต้องเป็น <a> จริง ไม่ใช่ fetch — Android ถึงจะเปิดตัวติดตั้งให้ */}
              <Button asChild size="lg" className="w-full sm:w-auto">
                <a href={url} download>
                  <Download />
                  {isBossApp ? "ดาวน์โหลดแอปบอส (.apk)" : "ดาวน์โหลดแอป (.apk)"}
                </a>
              </Button>
              <Button variant="outline" size="lg" className="w-full sm:w-auto" onClick={copyLink}>
                <Link2 />
                คัดลอกลิงก์
              </Button>
            </div>

            <p className="text-muted-foreground text-xs leading-relaxed sm:text-sm">
              วิธีติดตั้งบน Android: เปิดลิงก์นี้จากมือถือ → กดดาวน์โหลด → เปิดไฟล์ที่โหลดมา
              → ถ้าขึ้นเตือน ให้กด “ตั้งค่า” แล้วอนุญาต “ติดตั้งแอปที่ไม่รู้จัก” ให้เบราว์เซอร์
              → กดติดตั้ง แล้วเข้าสู่ระบบด้วยบัญชีเดียวกับเว็บ
              {isBossApp && " (ระบบอนุญาตเฉพาะบัญชีหัวหน้า)"}
              <br />
              iPhone ยังไม่มีไฟล์ติดตั้ง ให้ใช้เว็บนี้แทน (กดแชร์ → “เพิ่มไปยังหน้าจอโฮม”)
            </p>
          </>
        )}
      </CardContent>
    </Card>
  );
}

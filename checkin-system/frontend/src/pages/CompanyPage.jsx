import React, { useEffect, useState } from "react";
import {
  AlertTriangle,
  Building2,
  CheckCircle2,
  Clock,
  ExternalLink,
  Globe,
  HelpCircle,
  MapPin,
  Shirt,
  ShoppingBag,
  Store,
} from "lucide-react";
import AppLayout from "../components/AppLayout.jsx";
import { getGeofence } from "../api";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Separator } from "@/components/ui/separator";
import { Skeleton } from "@/components/ui/skeleton";

/**
 * หน้าอธิบายธุรกิจของบริษัทที่พนักงานสังกัดอยู่
 *
 * ข้อมูลสองชั้นที่ต้องแยกให้ออก และเป็นเหตุผลที่หน้านี้มีป้ายกำกับทุกบล็อก:
 *   1. "ยืนยันแล้ว"  = อ่านจากระบบเราเอง (สำนักงาน/เวลางาน มาจาก /reports/geofence สดๆ)
 *   2. "ยังไม่ยืนยัน" = ค้นจากแหล่งสาธารณะเมื่อ 10 ก.ย. 2026 ยังไม่ได้ยืนยันกับฝ่ายบุคคล
 *
 * อย่าลบป้ายออกจนกว่าจะยืนยันกับ HR จริง — หน้านี้เปิดดูได้ทั้งหัวหน้าและพนักงาน
 * การแสดงข้อมูลที่ยังไม่ยืนยันโดยไม่บอกว่ายังไม่ยืนยัน อันตรายกว่าการไม่แสดงเลย
 */

const COMPANY_NAME = "Motta & Montipa";

const BRANDS = [
  {
    name: "Montipa",
    icon: Shirt,
    tagline: "ใส่สวยไม่ต้องรีด",
    products: "กางเกงผ้า/ยีนส์ผู้หญิงเป็นตัวชูโรง แยกทรงเป็นรหัส S สลิม · W ขากระบอก · N ขา 5 ส่วน · H ขาสั้น · J ยีนส์ และเสื้อ",
    reach: "ประมาณ 23 สาขาทั่วประเทศ",
    channels: ["เคาน์เตอร์ในห้าง", "เว็บแบรนด์", "Shopee", "TikTok", "LINE"],
    site: "https://www.montipa-design.com/",
  },
  {
    name: "Motta",
    icon: ShoppingBag,
    tagline: "เครื่องประดับและกระเป๋าแฟชั่น",
    products: "เครื่องประดับ กระเป๋า เสื้อผ้า และสินค้าแฟชั่นอื่นๆ",
    reach: "ประมาณ 30+ สาขา",
    channels: ["เคาน์เตอร์ในห้าง", "ออนไลน์"],
    site: null,
  },
];

const DEPARTMENT_STORES = ["Central", "The Mall", "Robinson Lifestyle"];

const LEGAL_ROWS = [
  ["ชื่อนิติบุคคล", "บริษัท มนทิพาดีไซน์ จำกัด (MONTIPA DESIGN CO., LTD.)"],
  ["เลขทะเบียน", "0105565157489"],
  ["วันจดทะเบียน", "26 กันยายน 2565"],
  ["ประเภทธุรกิจ (TSIC 46103)", "ขายส่งสิ่งทอ เสื้อผ้า รองเท้า เครื่องหนัง และของใช้ในครัวเรือน"],
  ["ที่ตั้ง", "59/37 ม.3 ต.คลองเกลือ อ.ปากเกร็ด จ.นนทบุรี 11120"],
];

const HR_QUESTIONS = [
  "นิติบุคคลที่จ้างจริงคือ มนทิพาดีไซน์ หรือ แอ็ท เฟเวอริท",
  "ที่อยู่สำนักงานแบบตัวอักษรเต็ม (ระบบมีแต่พิกัด ยังไม่มีที่อยู่)",
  "จำนวนสาขา/เคาน์เตอร์ปัจจุบัน และมีพนักงานกี่คนที่ต้องลงเวลา",
  "เวลาทำงานของพนักงานหน้าร้าน (PC) ต่างจากออฟฟิศไหม",
  "วันหยุดบริษัทใช้ปฏิทินแบบไหน หยุดตามวันหยุดราชการครบหรือไม่",
];

const SYSTEM_GAPS = [
  {
    assumption: "ระบบตั้งไว้ที่สำนักงานเดียว",
    reality: "ธุรกิจมีเคาน์เตอร์กระจายหลายสิบสาขา",
    fix: "เติมรายการใน OFFICES ของ backend ได้เลย โค้ดรองรับหลายสถานที่อยู่แล้ว ไม่ต้อง build แอปใหม่",
  },
  {
    assumption: "เวลาทำงานเป็นค่าเดียวทั้งระบบ",
    reality: "ออฟฟิศกับหน้าร้านในห้างคนละรอบเวลา",
    fix: "ต้องเพิ่มตารางเวลารายกลุ่ม/รายคน — ยังไม่มีในระบบ",
  },
  {
    assumption: "ตัดสินสาย/ออกก่อนโดยดูเฉพาะเวลาในวัน",
    reality: "ห้างปิดดึก กะเย็นอาจคาบเกี่ยวข้ามวัน",
    fix: "ถ้ามีกะข้ามคืนต้องออกแบบตรรกะใหม่",
  },
];

/** ป้ายบอกว่าข้อมูลบล็อกนี้เชื่อได้แค่ไหน */
function SourceBadge({ verified }) {
  return verified ? (
    <Badge variant="secondary" className="gap-1">
      <CheckCircle2 className="size-3" />
      ยืนยันแล้ว — จากระบบ
    </Badge>
  ) : (
    <Badge variant="outline" className="gap-1 border-amber-500/50 text-amber-700 dark:text-amber-500">
      <AlertTriangle className="size-3" />
      ยังไม่ยืนยันกับฝ่ายบุคคล
    </Badge>
  );
}

function InfoRow({ label, value }) {
  return (
    <div className="flex flex-col gap-0.5 py-2 sm:flex-row sm:items-baseline sm:gap-4">
      <div className="text-muted-foreground w-full shrink-0 text-xs sm:w-56 sm:text-sm">{label}</div>
      <div className="text-sm font-medium break-words">{value}</div>
    </div>
  );
}

export default function CompanyPage() {
  const [geofence, setGeofence] = useState(null);
  const [loadError, setLoadError] = useState("");

  useEffect(() => {
    let alive = true;
    getGeofence()
      .then((data) => alive && setGeofence(data))
      // โหลดไม่ได้ให้บอกตรงๆ ดีกว่าโชว์ค่าที่เดาเอง (กฎเดียวกับ WorkSchedule.jsx)
      .catch(() => alive && setLoadError("โหลดข้อมูลสำนักงานจากระบบไม่สำเร็จ"));
    return () => {
      alive = false;
    };
  }, []);

  const offices = geofence?.offices ?? [];
  const schedule = geofence?.work_schedule;

  return (
    <AppLayout>
      <div className="space-y-4">
        <div className="hidden lg:block">
          <h2 className="text-2xl font-bold">ข้อมูลบริษัท</h2>
          <p className="text-muted-foreground text-sm">
            บริษัทที่เราสังกัดทำธุรกิจอะไร ขายอะไร และเกี่ยวข้องกับระบบลงเวลานี้อย่างไร
          </p>
        </div>

        {/* ---------- ภาพรวมธุรกิจ ---------- */}
        <Card>
          <CardHeader>
            <div className="flex flex-wrap items-start justify-between gap-2">
              <div className="flex items-center gap-3">
                <div className="bg-primary/10 text-primary flex size-11 shrink-0 items-center justify-center rounded-xl">
                  <Building2 className="size-6" />
                </div>
                <div>
                  <CardTitle className="text-xl">{COMPANY_NAME}</CardTitle>
                  <CardDescription>แบรนด์แฟชั่นไทย — เจ้าของสินค้าเอง ผลิตเอง ขายเอง</CardDescription>
                </div>
              </div>
              <SourceBadge verified={false} />
            </div>
          </CardHeader>
          <CardContent className="space-y-4">
            <p className="text-sm leading-relaxed">
              ธุรกิจหลักคือ <strong>ค้าปลีกสินค้าแฟชั่น</strong> โดยเป็นเจ้าของแบรนด์เอง
              กระจายสินค้าเข้า <strong>เคาน์เตอร์/ช็อปในห้างสรรพสินค้าทั่วประเทศ</strong> เป็นช่องทางหลัก
              และขายออนไลน์ผ่านเว็บแบรนด์ของตัวเองควบคู่ไปด้วย
              กำลังหลักหน้าร้านคือ <strong>PC (พนักงานขายประจำเคาน์เตอร์)</strong> โดยมี Area Manager คุมหลายสาขา
              และมีทีมการตลาด/ขายออนไลน์แยกต่างหาก
            </p>

            <div className="bg-muted/50 rounded-lg border p-3">
              <div className="text-muted-foreground mb-2 text-xs font-medium">ช่องทางขาย</div>
              <div className="flex flex-wrap items-center gap-2 text-sm">
                <Store className="text-muted-foreground size-4" />
                <span>เคาน์เตอร์ในห้าง</span>
                <span className="text-muted-foreground">·</span>
                {DEPARTMENT_STORES.map((store) => (
                  <Badge key={store} variant="secondary">
                    {store}
                  </Badge>
                ))}
                <span className="text-muted-foreground">·</span>
                <Globe className="text-muted-foreground size-4" />
                <span>ออนไลน์ (เว็บแบรนด์ / Shopee / TikTok / LINE)</span>
              </div>
            </div>
          </CardContent>
        </Card>

        {/* ---------- แบรนด์ในเครือ ---------- */}
        <div className="grid gap-4 md:grid-cols-2">
          {BRANDS.map((brand) => {
            const Icon = brand.icon;
            return (
              <Card key={brand.name}>
                <CardHeader>
                  <div className="flex items-center gap-3">
                    <div className="bg-muted flex size-10 shrink-0 items-center justify-center rounded-lg">
                      <Icon className="size-5" />
                    </div>
                    <div className="min-w-0">
                      <CardTitle>{brand.name}</CardTitle>
                      <CardDescription className="truncate">{brand.tagline}</CardDescription>
                    </div>
                  </div>
                </CardHeader>
                <CardContent className="space-y-3">
                  <p className="text-sm leading-relaxed">{brand.products}</p>
                  <Separator />
                  <div className="text-muted-foreground flex items-center gap-2 text-sm">
                    <Store className="size-4 shrink-0" />
                    {brand.reach}
                  </div>
                  <div className="flex flex-wrap gap-1.5">
                    {brand.channels.map((channel) => (
                      <Badge key={channel} variant="outline">
                        {channel}
                      </Badge>
                    ))}
                  </div>
                  {brand.site && (
                    <a
                      href={brand.site}
                      target="_blank"
                      rel="noreferrer noopener"
                      className="text-primary inline-flex items-center gap-1 text-sm hover:underline"
                    >
                      เปิดเว็บแบรนด์
                      <ExternalLink className="size-3.5" />
                    </a>
                  )}
                </CardContent>
              </Card>
            );
          })}
        </div>

        {/* ---------- สำนักงานที่ระบบใช้จริง (ข้อมูลสด) ---------- */}
        <Card>
          <CardHeader>
            <div className="flex flex-wrap items-start justify-between gap-2">
              <div>
                <CardTitle className="flex items-center gap-2">
                  <MapPin className="size-5" />
                  สถานที่ทำงานที่ระบบใช้จริง
                </CardTitle>
                <CardDescription>ดึงสดจาก backend ทุกครั้งที่เปิดหน้านี้</CardDescription>
              </div>
              <SourceBadge verified />
            </div>
          </CardHeader>
          <CardContent className="space-y-3">
            {loadError ? (
              <div className="text-destructive flex items-center gap-2 text-sm">
                <AlertTriangle className="size-4" />
                {loadError}
              </div>
            ) : !geofence ? (
              <div className="space-y-2">
                <Skeleton className="h-5 w-64" />
                <Skeleton className="h-5 w-40" />
              </div>
            ) : (
              <>
                {offices.map((office) => (
                  <div key={office.name} className="rounded-lg border p-3">
                    <div className="font-medium">{office.name}</div>
                    <div className="text-muted-foreground mt-1 text-sm">
                      พิกัด {office.lat}, {office.lng} · รัศมีเช็คอิน {office.radius_km} กม.
                    </div>
                  </div>
                ))}
                {schedule && (
                  <div className="text-muted-foreground flex flex-wrap items-center gap-2 text-sm">
                    <Clock className="size-4 shrink-0" />
                    เวลาทำงานมาตรฐาน {schedule.work_start} – {schedule.work_end} น.
                    {schedule.late_grace_minutes > 0
                      ? ` (ผ่อนผัน ${schedule.late_grace_minutes} นาที)`
                      : " (ไม่มีผ่อนผัน)"}
                  </div>
                )}
              </>
            )}
          </CardContent>
        </Card>

        {/* ---------- ข้อมูลนิติบุคคล ---------- */}
        <Card>
          <CardHeader>
            <div className="flex flex-wrap items-start justify-between gap-2">
              <div>
                <CardTitle>ข้อมูลนิติบุคคล</CardTitle>
                <CardDescription>ค้นจากฐานข้อมูลสาธารณะ เมื่อ 10 ก.ย. 2026</CardDescription>
              </div>
              <SourceBadge verified={false} />
            </div>
          </CardHeader>
          <CardContent>
            <div className="divide-y">
              {LEGAL_ROWS.map(([label, value]) => (
                <InfoRow key={label} label={label} value={value} />
              ))}
            </div>
            <div className="bg-amber-500/10 mt-3 rounded-lg border border-amber-500/30 p-3 text-sm">
              <strong>ยังสรุปไม่ได้ว่าใครเป็นนายจ้าง</strong> — ประกาศรับสมัครงานของทั้งสองแบรนด์
              ออกในนาม <em>บริษัท แอ็ท เฟเวอริท จำกัด</em> ซึ่งเป็นคนละนิติบุคคลกับข้างบน
              ต้องถามฝ่ายบุคคลให้ชัดในวันเริ่มงาน
            </div>
          </CardContent>
        </Card>

        {/* ---------- สิ่งที่ต้องถาม HR ---------- */}
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <HelpCircle className="size-5" />
              ยังต้องยืนยันกับฝ่ายบุคคล
            </CardTitle>
            <CardDescription>ข้อมูลที่ค้นเองไม่ได้ ต้องถามเท่านั้น</CardDescription>
          </CardHeader>
          <CardContent>
            <ul className="space-y-2">
              {HR_QUESTIONS.map((question) => (
                <li key={question} className="flex items-start gap-2 text-sm">
                  <span className="bg-muted-foreground/40 mt-2 size-1.5 shrink-0 rounded-full" />
                  {question}
                </li>
              ))}
            </ul>
          </CardContent>
        </Card>

        {/* ---------- ผลกระทบต่อระบบลงเวลา ---------- */}
        <Card>
          <CardHeader>
            <CardTitle>ธุรกิจแบบนี้กระทบระบบลงเวลาอย่างไร</CardTitle>
            <CardDescription>
              ระบบนี้ออกแบบมาสำหรับออฟฟิศเดียว กะเดียว — ถ้าจะใช้กับหน้าร้านในห้างต้องแก้ 3 จุด
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-3">
            {SYSTEM_GAPS.map((gap) => (
              <div key={gap.assumption} className="rounded-lg border p-3">
                <div className="text-sm font-medium">{gap.assumption}</div>
                <div className="text-muted-foreground mt-1 text-sm">
                  แต่จริงๆ แล้ว: {gap.reality}
                </div>
                <div className="mt-2 text-sm">
                  <span className="text-muted-foreground">ทางแก้: </span>
                  {gap.fix}
                </div>
              </div>
            ))}
          </CardContent>
        </Card>

        <p className="text-muted-foreground pb-2 text-xs">
          ข้อมูลธุรกิจในหน้านี้รวบรวมจากแหล่งสาธารณะเมื่อ 10 ก.ย. 2026 และยังไม่ได้ยืนยันกับบริษัท
          ใช้เป็นข้อมูลตั้งต้นเท่านั้น — เมื่อยืนยันกับฝ่ายบุคคลแล้ว แก้ที่
          <code className="bg-muted mx-1 rounded px-1 py-0.5">src/pages/CompanyPage.jsx</code>
          แล้วเปลี่ยนป้ายเป็น &quot;ยืนยันแล้ว&quot;
        </p>
      </div>
    </AppLayout>
  );
}

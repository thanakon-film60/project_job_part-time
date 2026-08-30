import React from "react";
import { ShieldAlert } from "lucide-react";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { cn } from "@/lib/utils";

/**
 * กล่องเตือนสีแดง "ยังไม่ได้ยืนยันตัวตน"
 *
 * ใช้ทั้งหน้าพนักงาน (เตือนตัวเอง) และหน้าหัวหน้า (สรุปว่าใครยังไม่ยืนยัน)
 * จึงรับ reasons/warning มาจากภายนอก แทนที่จะไปคิดเงื่อนไขเองในนี้
 * ตัวตัดสินว่า "ยังไม่ยืนยัน" อยู่ที่ describeUnverified() ใน lib/attendance.js
 *
 * ใช้ text-destructive ทั้งก้อน ไม่ใช่ text-muted-foreground ตามค่าเริ่มต้นของ
 * AlertDescription เพราะข้อความนี้ต้อง "อ่านแล้วสะดุด" ไม่ใช่ข้อความประกอบ
 */
export default function UnverifiedDutyAlert({
  title,
  reasons = [],
  warning,
  className,
  children,
}) {
  return (
    <Alert variant="destructive" className={cn("border-destructive/50", className)}>
      <ShieldAlert />
      <AlertTitle className="text-destructive font-bold">{title}</AlertTitle>
      <AlertDescription className="text-destructive/90">
        {reasons.length > 0 && (
          <ul className="list-inside list-disc space-y-0.5">
            {reasons.map((reason) => (
              <li key={reason}>{reason}</li>
            ))}
          </ul>
        )}
        {warning && <p className="mt-1 font-semibold">⚠ {warning}</p>}
        {children}
      </AlertDescription>
    </Alert>
  );
}

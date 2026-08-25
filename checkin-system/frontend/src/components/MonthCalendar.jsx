import React, { useMemo } from "react";
import dayjs from "dayjs";
import { ChevronLeft, ChevronRight } from "lucide-react";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";

const WEEKDAYS = ["อา", "จ", "อ", "พ", "พฤ", "ศ", "ส"];

/** ปฏิทินรายเดือน — เขียนเองแทน <Calendar> ของ antd
 *
 *  เหตุผลที่ไม่ใช้ react-day-picker (ตัวที่ shadcn ห่อมาให้): ช่องวันของเรา
 *  ต้องยัดรายชื่อพนักงานหลายคน + แท็กสถานที่ ซึ่ง day-picker ออกแบบมาสำหรับ
 *  "เลือกวัน" ไม่ใช่ "ตารางงานรายวัน" — เขียน grid เองคุมง่ายกว่าและ responsive ได้ตรงกว่า
 *
 *  props:
 *   - value: dayjs ของเดือนที่กำลังดู
 *   - onChange(next): เปลี่ยนเดือน
 *   - onSelectDate(dayjs): กดที่ช่องวัน
 *   - renderCell(dayjs): เนื้อหาในช่อง (คืน null ได้ถ้าวันนั้นไม่มีข้อมูล)
 */
export default function MonthCalendar({ value, onChange, onSelectDate, renderCell }) {
  const cells = useMemo(() => {
    const first = value.startOf("month");
    const lead = first.day(); // อาทิตย์ = 0 ตรงกับหัวตาราง
    const daysInMonth = value.daysInMonth();
    const list = [];
    for (let i = 0; i < lead; i += 1) list.push(null);
    for (let d = 1; d <= daysInMonth; d += 1) list.push(first.date(d));
    // เติมท้ายให้ครบแถว ตารางจะได้ไม่มีช่องขาดครึ่ง
    while (list.length % 7 !== 0) list.push(null);
    return list;
  }, [value]);

  const today = dayjs();

  return (
    <div className="w-full">
      <div className="mb-3 flex flex-wrap items-center justify-between gap-2">
        <div className="flex items-center gap-1">
          <Button
            variant="outline"
            size="icon-sm"
            aria-label="เดือนก่อนหน้า"
            onClick={() => onChange(value.subtract(1, "month"))}
          >
            <ChevronLeft />
          </Button>
          <div className="min-w-[9.5rem] text-center text-sm font-semibold sm:text-base">
            {value.format("MMMM YYYY")}
          </div>
          <Button
            variant="outline"
            size="icon-sm"
            aria-label="เดือนถัดไป"
            onClick={() => onChange(value.add(1, "month"))}
          >
            <ChevronRight />
          </Button>
        </div>
        <Button variant="ghost" size="sm" onClick={() => onChange(dayjs())}>
          วันนี้
        </Button>
      </div>

      <div className="grid grid-cols-7 gap-px text-center">
        {WEEKDAYS.map((w) => (
          <div key={w} className="text-muted-foreground pb-1.5 text-[11px] font-medium sm:text-xs">
            {w}
          </div>
        ))}
      </div>

      {/* gap-px + พื้นหลัง border ทำให้ได้เส้นตารางบางเท่ากันทุกช่องโดยไม่ต้องคุม border ซ้อน */}
      <div className="bg-border grid grid-cols-7 gap-px overflow-hidden rounded-lg border">
        {cells.map((date, index) => {
          if (!date) return <div key={`empty-${index}`} className="bg-muted/40 min-h-16" />;

          const isToday = date.isSame(today, "date");
          const content = renderCell?.(date);
          const hasData = Boolean(content);

          return (
            <button
              key={date.format("YYYY-MM-DD")}
              type="button"
              onClick={() => onSelectDate?.(date)}
              className={cn(
                "bg-card hover:bg-accent/60 focus-visible:ring-ring/50 relative flex min-h-16 flex-col items-stretch gap-1 p-1 text-left transition-colors outline-none focus-visible:ring-[3px] focus-visible:ring-inset sm:min-h-28 sm:p-1.5",
                hasData && "bg-primary/[0.04]",
              )}
            >
              <span
                className={cn(
                  "text-[11px] font-medium tabular-nums sm:text-xs",
                  isToday &&
                    "bg-primary text-primary-foreground inline-flex size-5 items-center justify-center self-start rounded-full sm:size-6",
                  !isToday && "text-muted-foreground",
                )}
              >
                {date.date()}
              </span>
              {content}
            </button>
          );
        })}
      </div>
    </div>
  );
}

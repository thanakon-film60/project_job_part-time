import * as React from "react";
import { Card } from "@/components/ui/card";
import { cn } from "@/lib/utils";

/** แทน Statistic ของ antd — ตัวเลขสรุปหนึ่งค่า พร้อมไอคอนและหน่วย
 *  จอเล็กบีบตัวเลขลงเองด้วย text-2xl → sm:text-3xl จะได้ไม่ล้นการ์ด
 */
function StatCard({ icon, label, value, suffix, tone = "default", className, onClick, ...props }) {
  const interactive = typeof onClick === "function";
  return (
    <Card
      className={cn(
        "gap-0 py-4",
        interactive && "cursor-pointer transition hover:-translate-y-0.5 hover:border-primary/40 hover:shadow-md focus-visible:ring-2 focus-visible:ring-ring focus-visible:outline-none",
        className,
      )}
      onClick={onClick}
      role={interactive ? "button" : undefined}
      tabIndex={interactive ? 0 : undefined}
      onKeyDown={interactive ? (event) => {
        if (event.key === "Enter" || event.key === " ") {
          event.preventDefault();
          onClick(event);
        }
      } : undefined}
      {...props}
    >
      <div className="flex items-start gap-3 px-4">
        {icon && (
          <span
            className={cn(
              "flex size-9 shrink-0 items-center justify-center rounded-lg [&_svg]:size-4.5",
              tone === "success" && "bg-success/12 text-success",
              tone === "warning" && "bg-warning/15 text-warning",
              tone === "destructive" && "bg-destructive/10 text-destructive",
              tone === "default" && "bg-primary/10 text-primary",
            )}
          >
            {icon}
          </span>
        )}
        <div className="min-w-0 flex-1">
          <div className="text-muted-foreground truncate text-xs sm:text-sm">{label}</div>
          <div className="mt-0.5 flex items-baseline gap-1">
            <span className="text-2xl leading-tight font-semibold tabular-nums sm:text-3xl">
              {value}
            </span>
            {suffix && <span className="text-muted-foreground text-xs sm:text-sm">{suffix}</span>}
          </div>
        </div>
      </div>
    </Card>
  );
}

export { StatCard };

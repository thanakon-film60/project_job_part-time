import * as React from "react";
import { Card, CardContent } from "@/components/ui/card";
import { cn } from "@/lib/utils";

function Skeleton({ className, ...props }) {
  return (
    <div
      data-slot="skeleton"
      className={cn("bg-muted/80 animate-pulse rounded-md", className)}
      {...props}
    />
  );
}

/** โครงร่างการ์ดตัวเลขสรุปสถิติ (StatCard) */
function StatCardSkeleton({ className }) {
  return (
    <Card className={cn("gap-0 py-4", className)}>
      <div className="flex items-start gap-3 px-4">
        <Skeleton className="size-9 shrink-0 rounded-lg" />
        <div className="min-w-0 flex-1 space-y-1.5">
          <Skeleton className="h-3.5 w-24" />
          <Skeleton className="h-7 w-16" />
        </div>
      </div>
    </Card>
  );
}

/** โครงร่างแถวรายการทั่วไป (เช่น ประวัติการลงเวลา หรือรายชื่อพนักงาน) */
function ListRowSkeleton({ className }) {
  return (
    <div className={cn("flex items-center justify-between gap-3 py-3", className)}>
      <div className="flex min-w-0 items-center gap-3">
        <Skeleton className="size-9 shrink-0 rounded-lg" />
        <div className="min-w-0 space-y-1.5">
          <div className="flex items-center gap-2">
            <Skeleton className="h-4 w-20" />
            <Skeleton className="h-4 w-14 rounded-full" />
          </div>
          <Skeleton className="h-3 w-36" />
        </div>
      </div>
      <Skeleton className="h-3.5 w-12" />
    </div>
  );
}

/** โครงร่างการ์ดทั่วไป */
function CardSkeleton({ className, rows = 3 }) {
  return (
    <Card className={className}>
      <CardContent className="space-y-3 p-4 sm:p-5">
        <Skeleton className="h-5 w-1/3" />
        <div className="space-y-2 pt-1">
          {Array.from({ length: rows }).map((_, i) => (
            <Skeleton key={i} className="h-4 w-full" />
          ))}
        </div>
      </CardContent>
    </Card>
  );
}

export { Skeleton, StatCardSkeleton, ListRowSkeleton, CardSkeleton };

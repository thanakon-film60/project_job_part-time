import * as React from "react";
import * as ToggleGroupPrimitive from "@radix-ui/react-toggle-group";
import { cn } from "@/lib/utils";

/** ใช้แทน Segmented ของ antd — ปุ่มเลือกช่วงเวลาแบบกลุ่มเดียวกัน */
const ToggleGroup = React.forwardRef(function ToggleGroup({ className, children, ...props }, ref) {
  return (
    <ToggleGroupPrimitive.Root
      ref={ref}
      data-slot="toggle-group"
      className={cn(
        "bg-muted text-muted-foreground inline-flex w-fit items-center gap-1 rounded-lg p-1",
        className,
      )}
      {...props}
    >
      {children}
    </ToggleGroupPrimitive.Root>
  );
});

const ToggleGroupItem = React.forwardRef(function ToggleGroupItem(
  { className, children, ...props },
  ref,
) {
  return (
    <ToggleGroupPrimitive.Item
      ref={ref}
      data-slot="toggle-group-item"
      className={cn(
        "focus-visible:ring-ring/50 data-[state=on]:bg-background data-[state=on]:text-foreground inline-flex h-7 items-center justify-center rounded-md px-2.5 text-xs font-medium whitespace-nowrap transition-all outline-none hover:text-foreground focus-visible:ring-[3px] disabled:pointer-events-none disabled:opacity-50 data-[state=on]:shadow-xs sm:text-sm",
        className,
      )}
      {...props}
    >
      {children}
    </ToggleGroupPrimitive.Item>
  );
});

export { ToggleGroup, ToggleGroupItem };

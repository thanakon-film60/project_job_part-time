import { Inbox } from "lucide-react";
import { cn } from "@/lib/utils";

/** แทน Empty ของ antd */
function EmptyState({ icon, title, description, action, className }) {
  return (
    <div
      className={cn(
        "text-muted-foreground flex flex-col items-center justify-center gap-2 px-4 py-10 text-center",
        className,
      )}
    >
      <span className="bg-muted flex size-12 items-center justify-center rounded-full [&_svg]:size-6">
        {icon || <Inbox />}
      </span>
      <p className="text-foreground text-sm font-medium">{title}</p>
      {description && <p className="max-w-sm text-xs sm:text-sm">{description}</p>}
      {action}
    </div>
  );
}

export { EmptyState };

import * as React from "react";
import { Dialog, DialogContent, DialogDescription, DialogTitle } from "@/components/ui/dialog";
import { cn } from "@/lib/utils";

/** แทน <Image preview> ของ antd — กดรูปแล้วเปิดดูเต็มจอ
 *  ใช้ Dialog ของ shadcn เป็นฐาน จึงปิดด้วย Esc / กดพื้นหลังได้ตามมาตรฐาน
 */
function ImagePreview({ src, alt, className, wrapperClassName }) {
  const [open, setOpen] = React.useState(false);

  return (
    <>
      <button
        type="button"
        onClick={() => setOpen(true)}
        className={cn(
          "group focus-visible:ring-ring/50 relative block w-full cursor-zoom-in overflow-hidden rounded-lg outline-none focus-visible:ring-[3px]",
          wrapperClassName,
        )}
      >
        <img
          src={src}
          alt={alt}
          loading="lazy"
          className={cn(
            "h-full w-full object-cover transition-transform duration-200 group-hover:scale-[1.03]",
            className,
          )}
        />
      </button>

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="max-w-[min(92vw,900px)] bg-transparent p-0 shadow-none sm:max-w-[min(92vw,900px)]">
          <DialogTitle className="sr-only">{alt || "ดูรูปขนาดเต็ม"}</DialogTitle>
          <DialogDescription className="sr-only">กด Esc หรือแตะพื้นหลังเพื่อปิด</DialogDescription>
          <img
            src={src}
            alt={alt}
            className="max-h-[85vh] w-full rounded-xl bg-black object-contain"
          />
        </DialogContent>
      </Dialog>
    </>
  );
}

export { ImagePreview };

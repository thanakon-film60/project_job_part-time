import { clsx } from "clsx";
import { twMerge } from "tailwind-merge";

/** รวม className แบบ shadcn/ui — clsx จัดเงื่อนไข, twMerge กันคลาส tailwind ตีกัน */
export function cn(...inputs) {
  return twMerge(clsx(inputs));
}

import { Toaster as Sonner } from "sonner";

/** แทน message.* ของ antd — ใช้ toast() จาก "sonner" ได้ทุกที่ ไม่ต้อง context */
function Toaster(props) {
  return (
    <Sonner
      position="top-center"
      richColors
      closeButton
      toastOptions={{ style: { fontFamily: "inherit" } }}
      {...props}
    />
  );
}

export { Toaster };

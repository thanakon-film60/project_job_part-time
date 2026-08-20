import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import { VitePWA } from "vite-plugin-pwa";

// ===================================================================
// PWA = ทำให้เว็บติดตั้งบนมือถือได้เหมือนแอป (มีไอคอน เปิดเต็มจอ)
//
// ใช้แทนแอป Flutter เพราะ:
//   - ใช้กล้อง + GPS ได้เต็มที่ (เว็บเป็น HTTPS จริงผ่าน Cloudflare)
//   - อัปเดตทันทีที่ deploy ไม่ต้องให้พนักงานลง APK ใหม่
//   - ไม่ต้องติดตั้ง Flutter/Android SDK บนเซิร์ฟเวอร์
//
// ⚠️ ห้าม cache คำขอที่ยิงไป API — ข้อมูลเช็คอินต้องสดเสมอ
//    (ตั้ง navigateFallbackDenylist + ไม่ใส่ runtimeCaching ของ API)
// ===================================================================
export default defineConfig({
  plugins: [
    react(),
    VitePWA({
      registerType: "autoUpdate",
      includeAssets: [
        "favicon-32.png",
        "apple-touch-icon.png",
        "icon-192.png",
        "icon-512.png",
        "icon-maskable-512.png",
      ],
      manifest: {
        name: "THANAKON-BOX เช็คอินเข้างาน",
        short_name: "THANAKON-BOX",
        description: "ระบบเช็คอินเข้างานด้วย GPS และสแกนใบหน้า",
        lang: "th",
        theme_color: "#1565c0",
        background_color: "#ffffff",
        display: "standalone",
        orientation: "portrait",
        start_url: "/",
        scope: "/",
        icons: [
          { src: "/icon-192.png", sizes: "192x192", type: "image/png" },
          { src: "/icon-512.png", sizes: "512x512", type: "image/png" },
          {
            src: "/icon-maskable-512.png",
            sizes: "512x512",
            type: "image/png",
            purpose: "maskable",
          },
        ],
      },
      workbox: {
        // path ของ API — ห้ามให้ service worker ไปตอบแทนเด็ดขาด
        navigateFallbackDenylist: [
          /^\/auth/,
          /^\/checkins/,
          /^\/faces/,
          /^\/line/,
          /^\/locations/,
          /^\/reports/,
          /^\/health/,
          /^\/docs/,
          /^\/openapi\.json/,
          /^\/api/,
        ],
        // cache เฉพาะไฟล์หน้าเว็บ (js/css/html/รูปไอคอน) ไม่แตะข้อมูล
        globPatterns: ["**/*.{js,css,html,png,svg,woff2}"],
      },
      devOptions: {
        // ปิดไว้ตอน dev จะได้ไม่มี service worker มากวนเวลาแก้โค้ด
        enabled: false,
      },
    }),
  ],
  server: { port: 5173 },
});

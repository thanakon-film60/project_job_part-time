import path from "node:path";
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";
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
    // Tailwind v4 — ฐานของ shadcn/ui (ไม่มี tailwind.config.js แล้ว ตั้งธีมใน src/index.css)
    tailwindcss(),
    VitePWA({
      registerType: "autoUpdate",
      // ⚠️ ห้ามใส่ includeAssets ซ้ำกับ globPatterns ข้างล่าง!
      //    ไฟล์ใน public/ ถูก copy ลง dist อยู่แล้ว globPatterns จึงเก็บให้ครบเอง
      //    ถ้าใส่ทั้งสองที่ ไฟล์เดียวกันจะเข้า precache 2 รอบ → cache.put โยน
      //    "Entry already exists" → service worker ติดตั้งไม่ผ่าน → ตัวเก่าค้าง
      //    เสิร์ฟ index.html เดิมที่ชี้ไป /assets/*.js ซึ่งถูกลบไปแล้วตอน deploy
      //    ผลคือผู้ใช้เดิมเจอจอขาวถาวร (เคยเกิดจริงมาแล้ว 25 ส.ค. 2026)
      //
      // ด้วยเหตุผลเดียวกัน ปิด includeManifestIcons ด้วย — ไอคอนใน manifest ข้างล่าง
      // ก็อยู่ใน dist และถูก globPatterns เก็บไปแล้ว ไม่ต้องให้ปลั๊กอินใส่ซ้ำอีกรอบ
      includeManifestIcons: false,
      manifest: {
        name: "THANAKON-ROOM เช็คอินเข้างาน",
        short_name: "THANAKON-ROOM",
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
          // /app = ดาวน์โหลดไฟล์ติดตั้งแอป Flutter (ของ backend ไม่ใช่หน้าเว็บ)
          /^\/app/,
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
        // ลบ cache ของ build เก่าทิ้งตอน activate ไม่งั้นไฟล์เก่าค้างกินที่ไปเรื่อย ๆ
        cleanupOutdatedCaches: true,
        // เวอร์ชันใหม่เข้าคุมแท็บที่เปิดค้างอยู่ทันที ไม่ต้องรอปิดแท็บทั้งหมดก่อน
        skipWaiting: true,
        clientsClaim: true,
      },
      devOptions: {
        // ปิดไว้ตอน dev จะได้ไม่มี service worker มากวนเวลาแก้โค้ด
        enabled: false,
      },
    }),
  ],
  resolve: {
    alias: { "@": path.resolve(import.meta.dirname, "./src") },
  },
  server: { port: 5173 },
});

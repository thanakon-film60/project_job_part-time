import React from "react";
import AppDownloadCard from "../components/AppDownloadCard.jsx";
import AppLayout from "../components/AppLayout.jsx";

export default function BossAppDownloadPage() {
  return (
    <AppLayout>
      <div className="space-y-4">
        <div className="hidden lg:block">
          <h2 className="text-2xl font-bold">ติดตั้งแอปบอส</h2>
          <p className="text-muted-foreground text-sm">
            ดาวน์โหลดแอป THANAKON-BOX สำหรับหัวหน้าไปติดตั้งบนโทรศัพท์ Android
          </p>
        </div>
        <AppDownloadCard variant="boss" />
      </div>
    </AppLayout>
  );
}

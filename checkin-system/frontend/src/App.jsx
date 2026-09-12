import React from "react";
import ChatWidget from "./components/ChatWidget.jsx";
import { Routes, Route, Navigate, useLocation } from "react-router-dom";
import { getEmployee, getToken } from "./api";
import LoginPage from "./pages/LoginPage.jsx";
import DashboardPage from "./pages/DashboardPage.jsx";
import FaceRecordsPage from "./pages/FaceRecordsPage.jsx";
import EmployeesPage from "./pages/EmployeesPage.jsx";
import EmployeeRegistrationPage from "./pages/EmployeeRegistrationPage.jsx";
import EmployeeHistoryPage from "./pages/EmployeeHistoryPage.jsx";
import LiveMapPage from "./pages/LiveMapPage.jsx";
import BossAppDownloadPage from "./pages/BossAppDownloadPage.jsx";
import CompanyPage from "./pages/CompanyPage.jsx";
import SupportPage from "./pages/SupportPage.jsx";
import RemoteHelpPage from "./pages/RemoteHelpPage.jsx";

function RequireAuth({ children }) {
  return getToken() ? children : <Navigate to="/login" replace />;
}

function RequireBoss({ children }) {
  if (!getToken()) return <Navigate to="/login" replace />;
  return getEmployee()?.is_manager ? children : <Navigate to="/" replace />;
}

export default function App() {
  // หน้าให้ผู้ใช้ภายนอกเข้ามาขอความช่วยเหลือเป็นวิดีโอเต็มจอ ไม่ควรมีกล่องแชทลอยทับ
  const isGuestCall = useLocation().pathname.startsWith("/remote-help");

  return (
    <>
    <Routes>
      <Route path="/login" element={<LoginPage />} />
      {/* ฝั่งผู้ใช้ที่ขอความช่วยเหลือ — ตั้งใจไม่ต้องล็อกอิน แค่ถือลิงก์ก็เข้าได้
          (backend คุมด้วยโทเค็นสุ่มในลิงก์ + วันหมดอายุ ดู app/routers/support.py) */}
      <Route path="/remote-help/:code" element={<RemoteHelpPage />} />
      <Route
        path="/"
        element={
          <RequireAuth>
            <DashboardPage />
          </RequireAuth>
        }
      />
      {/* ใช้ /face-records ไม่ใช่ /faces เพราะ /faces เป็น path ของ API
          (เว็บกับ API อยู่โดเมนเดียวกัน จึงห้ามชนกัน) */}
      <Route
        path="/employees/register"
        element={
          <RequireBoss>
            <EmployeeRegistrationPage />
          </RequireBoss>
        }
      />
      <Route
        path="/employees/:employeeId/history"
        element={
          <RequireBoss>
            <EmployeeHistoryPage />
          </RequireBoss>
        }
      />
      <Route
        path="/employees"
        element={
          <RequireBoss>
            <EmployeesPage />
          </RequireBoss>
        }
      />
      {/* แผนที่ติดตามพนักงาน — เฉพาะหัวหน้า (API /locations/live ก็กันไว้อีกชั้น) */}
      <Route
        path="/live-map"
        element={
          <RequireBoss>
            <LiveMapPage />
          </RequireBoss>
        }
      />
      <Route
        path="/install-boss-app"
        element={
          <RequireBoss>
            <BossAppDownloadPage />
          </RequireBoss>
        }
      />
      {/* ห้องช่วยเหลือระยะไกล — พนักงานที่ล็อกอินแล้วเปิดห้องได้ทุกคน
          ถ้าอยากให้เฉพาะหัวหน้า เปลี่ยน RequireAuth เป็น RequireBoss บรรทัดล่าง
          แล้วเอา SUPPORT_NAV ออกจาก STAFF_NAV ใน AppLayout.jsx ด้วย */}
      <Route
        path="/it-support"
        element={
          <RequireAuth>
            <SupportPage />
          </RequireAuth>
        }
      />
      {/* ข้อมูลบริษัท — เปิดได้ทั้งหัวหน้าและพนักงาน เป็นข้อมูลองค์กรไม่ใช่ข้อมูลส่วนบุคคล */}
      <Route
        path="/company"
        element={
          <RequireAuth>
            <CompanyPage />
          </RequireAuth>
        }
      />
      <Route
        path="/face-records"
        element={
          <RequireAuth>
            <FaceRecordsPage />
          </RequireAuth>
        }
      />
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
    {!isGuestCall && <ChatWidget />}
    </>
  );
}

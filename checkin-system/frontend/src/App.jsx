import React from "react";
import { Routes, Route, Navigate } from "react-router-dom";
import { getEmployee, getToken } from "./api";
import LoginPage from "./pages/LoginPage.jsx";
import DashboardPage from "./pages/DashboardPage.jsx";
import FaceRecordsPage from "./pages/FaceRecordsPage.jsx";
import EmployeesPage from "./pages/EmployeesPage.jsx";
import EmployeeRegistrationPage from "./pages/EmployeeRegistrationPage.jsx";
import EmployeeHistoryPage from "./pages/EmployeeHistoryPage.jsx";
import LiveMapPage from "./pages/LiveMapPage.jsx";
import BossAppDownloadPage from "./pages/BossAppDownloadPage.jsx";

function RequireAuth({ children }) {
  return getToken() ? children : <Navigate to="/login" replace />;
}

function RequireBoss({ children }) {
  if (!getToken()) return <Navigate to="/login" replace />;
  return getEmployee()?.is_manager ? children : <Navigate to="/" replace />;
}

export default function App() {
  return (
    <Routes>
      <Route path="/login" element={<LoginPage />} />
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
  );
}

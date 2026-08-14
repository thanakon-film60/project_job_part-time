import React from "react";
import { Routes, Route, Navigate } from "react-router-dom";
import { getToken } from "./api";
import LoginPage from "./pages/LoginPage.jsx";
import DashboardPage from "./pages/DashboardPage.jsx";
import FaceRecordsPage from "./pages/FaceRecordsPage.jsx";

function RequireAuth({ children }) {
  return getToken() ? children : <Navigate to="/login" replace />;
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

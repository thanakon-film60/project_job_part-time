import React from "react";
import ReactDOM from "react-dom/client";
import { BrowserRouter } from "react-router-dom";
import dayjs from "dayjs";
import "dayjs/locale/th";
import App from "./App.jsx";
import { ErrorBoundary } from "./components/ErrorBoundary.jsx";
import { Toaster } from "@/components/ui/sonner";
import "./index.css";

// ตั้ง locale ครั้งเดียวตรงนี้ ทุกหน้าที่ format วันที่จะได้ภาษาไทยเหมือนกันหมด
dayjs.locale("th");

ReactDOM.createRoot(document.getElementById("root")).render(
  <React.StrictMode>
    <ErrorBoundary>
      <BrowserRouter>
        <App />
        <Toaster />
      </BrowserRouter>
    </ErrorBoundary>
  </React.StrictMode>,
);

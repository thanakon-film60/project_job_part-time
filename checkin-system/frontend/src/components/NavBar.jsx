import React from "react";
import { Link, useLocation, useNavigate } from "react-router-dom";
import { getEmployee, clearSession } from "../api";

export default function NavBar() {
  const emp = getEmployee();
  const loc = useLocation();
  const nav = useNavigate();

  function logout() {
    clearSession();
    nav("/login", { replace: true });
  }

  return (
    <header className="top">
      <div className="brand">
        <span className="brand-inline">
          <img className="header-logo" src="/logo-checkin.svg" alt="" aria-hidden="true" />
          <strong>THANAKON-ROOM</strong>
        </span>
        <nav className="tabs">
          <Link className={loc.pathname === "/" ? "active" : ""} to="/">
            ปฏิทินเข้างาน
          </Link>
          <Link
            className={loc.pathname === "/face-records" ? "active" : ""}
            to="/face-records"
          >
            ประวัติใบหน้า
          </Link>
        </nav>
      </div>
      <div className="who">
        {emp?.full_name}
        {emp?.is_manager ? " (ผู้จัดการ)" : ""}
        <button className="linkbtn" onClick={logout}>
          ออกจากระบบ
        </button>
      </div>
    </header>
  );
}

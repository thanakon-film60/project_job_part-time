import React, { useEffect, useMemo, useState } from "react";
import { Link, useLocation, useNavigate } from "react-router-dom";
import {
  CalendarDays,
  Crown,
  Download,
  LogOut,
  MapPin,
  Menu,
  Smile,
  User,
  Users,
} from "lucide-react";
import { getEmployee, clearSession } from "../api";
import EmployeeFaceAvatar from "@/components/EmployeeFaceAvatar.jsx";
import { Button } from "@/components/ui/button";
import { Sheet, SheetContent, SheetDescription, SheetTitle } from "@/components/ui/sheet";
import { cn } from "@/lib/utils";

const logoSrc = "/logo-checkin.svg";

const BOSS_NAV = [
  { to: "/", label: "ปฏิทินเข้างาน", icon: CalendarDays },
  { to: "/employees", label: "ข้อมูลพนักงาน", icon: Users },
  { to: "/live-map", label: "แผนที่ติดตามพนักงาน", icon: MapPin },
  { to: "/install-boss-app", label: "ติดตั้งแอปบอส", icon: Download },
];

const STAFF_NAV = [
  { to: "/", label: "ปฏิทินเข้างาน", icon: CalendarDays },
  { to: "/face-records", label: "ประวัติใบหน้า", icon: Smile },
];

/** path ปัจจุบันตรงกับเมนูไหน — ใช้ทั้งไฮไลต์เมนูและตั้งชื่อหัวข้อหน้า */
function matchNav(pathname, items) {
  const hit = items.find((item) => item.to !== "/" && pathname.startsWith(item.to));
  return hit || items[0];
}

function SidebarBrand({ isBoss }) {
  return (
    <div className="flex items-center gap-3 border-b border-sidebar-border px-4 py-4">
      <img src={logoSrc} alt="" aria-hidden="true" className="size-10 shrink-0 object-contain" />
      <div className="min-w-0">
        <div className="truncate text-sm font-bold tracking-wide text-sidebar-foreground">
          THANAKON-ROOM
        </div>
        <div className="text-[11px] tracking-[0.14em] text-sidebar-foreground/60 uppercase">
          {isBoss ? "Boss control" : "Employee"}
        </div>
      </div>
    </div>
  );
}

function SidebarNav({ items, activeTo, onNavigate }) {
  return (
    <nav className="flex-1 space-y-1 overflow-y-auto p-3">
      {items.map(({ to, label, icon: Icon }) => {
        const active = to === activeTo;
        return (
          <Link
            key={to}
            to={to}
            onClick={onNavigate}
            aria-current={active ? "page" : undefined}
            className={cn(
              "flex items-center gap-3 rounded-lg px-3 py-2.5 text-sm font-medium transition-colors",
              active
                ? "bg-sidebar-primary text-sidebar-primary-foreground shadow-sm"
                : "text-sidebar-foreground/80 hover:bg-sidebar-accent hover:text-sidebar-accent-foreground",
            )}
          >
            <Icon className="size-4.5 shrink-0" />
            <span className="truncate">{label}</span>
          </Link>
        );
      })}
    </nav>
  );
}

export default function AppLayout({ children }) {
  const emp = getEmployee();
  const loc = useLocation();
  const nav = useNavigate();
  const isBoss = Boolean(emp?.is_manager);
  const items = isBoss ? BOSS_NAV : STAFF_NAV;
  const [navOpen, setNavOpen] = useState(false);

  const current = useMemo(() => matchNav(loc.pathname, items), [loc.pathname, items]);

  // เปลี่ยนหน้าแล้วปิดเมนูเอง ไม่ต้องกดกากบาททุกครั้ง
  useEffect(() => setNavOpen(false), [loc.pathname]);

  function logout() {
    clearSession();
    nav("/login", { replace: true });
  }

  const sidebarInner = (
    <>
      <SidebarBrand isBoss={isBoss} />
      <SidebarNav items={items} activeTo={current.to} onNavigate={() => setNavOpen(false)} />
      <div className="border-t border-sidebar-border p-3">
        <Button
          variant="ghost"
          className="w-full justify-start text-sidebar-foreground/80 hover:bg-sidebar-accent hover:text-sidebar-accent-foreground"
          onClick={logout}
        >
          <LogOut />
          ออกจากระบบ
        </Button>
      </div>
    </>
  );

  return (
    <div className="bg-background flex min-h-svh">
      {/* จอกว้าง (lg ขึ้นไป) เมนูค้างไว้ข้างซ้าย — จอแคบกว่านั้นซ่อนไว้ใน Sheet */}
      <aside className="bg-sidebar hidden w-64 shrink-0 flex-col border-r border-sidebar-border lg:sticky lg:top-0 lg:flex lg:h-svh">
        {sidebarInner}
      </aside>

      <Sheet open={navOpen} onOpenChange={setNavOpen}>
        <SheetContent
          side="left"
          className="bg-sidebar gap-0 border-sidebar-border p-0 text-sidebar-foreground"
        >
          <SheetTitle className="sr-only">เมนูหลัก</SheetTitle>
          <SheetDescription className="sr-only">เลือกหน้าที่ต้องการเปิด</SheetDescription>
          {sidebarInner}
        </SheetContent>
      </Sheet>

      <div className="flex min-w-0 flex-1 flex-col">
        <header className="bg-sidebar text-sidebar-foreground sticky top-0 z-30 flex h-14 items-center gap-2 px-3 shadow-sm sm:h-16 sm:gap-3 sm:px-5">
          <Button
            variant="ghost"
            size="icon"
            aria-label="เปิดเมนู"
            className="text-sidebar-foreground hover:bg-sidebar-accent hover:text-sidebar-accent-foreground lg:hidden"
            onClick={() => setNavOpen(true)}
          >
            <Menu />
          </Button>

          <img
            src={logoSrc}
            alt=""
            aria-hidden="true"
            className="size-8 shrink-0 object-contain lg:hidden"
          />

          <h1 className="min-w-0 flex-1 truncate text-sm font-semibold sm:text-base">
            <span className="lg:hidden">THANAKON-ROOM</span>
            <span className="hidden lg:inline">{current.label}</span>
          </h1>

          <div className="flex items-center gap-2">
            <EmployeeFaceAvatar
              currentUser
              className="size-9 border border-sidebar-border"
              fallback={isBoss ? <Crown className="size-4" /> : <User className="size-4" />}
            />
            <span className="hidden max-w-[180px] truncate text-sm sm:inline">
              {emp?.full_name}
              {isBoss ? " (Boss)" : ""}
            </span>
            <Button
              variant="ghost"
              size="sm"
              onClick={logout}
              className="text-sidebar-foreground hover:bg-sidebar-accent hover:text-sidebar-accent-foreground hidden sm:inline-flex"
            >
              <LogOut />
              <span className="hidden md:inline">ออกจากระบบ</span>
            </Button>
          </div>
        </header>

        {/* หัวข้อหน้าแยกออกมาสำหรับจอเล็ก (บน header มีแค่ชื่อแบรนด์) */}
        <main className="safe-bottom mx-auto w-full max-w-[1180px] flex-1 px-3 py-4 pb-20 sm:px-5 sm:py-6 lg:pb-6">
          <h2 className="mb-3 text-lg font-semibold lg:hidden">{current.label}</h2>
          {children}
        </main>

        {/* แถบนำทางด้านล่างสำหรับมือถือ (Mobile Bottom Navigation) */}
        <nav className="border-border bg-card/95 fixed inset-x-0 bottom-0 z-40 flex h-16 items-center justify-around border-t px-2 shadow-lg backdrop-blur lg:hidden safe-bottom">
          {items.map(({ to, label, icon: Icon }) => {
            const active = to === current.to;
            return (
              <Link
                key={to}
                to={to}
                aria-current={active ? "page" : undefined}
                className={cn(
                  "flex flex-1 flex-col items-center justify-center gap-1 py-1 text-xs font-medium transition-colors",
                  active
                    ? "text-primary font-semibold"
                    : "text-muted-foreground hover:text-foreground",
                )}
              >
                <Icon className={cn("size-5 transition-transform", active && "scale-110")} />
                <span className="max-w-[80px] truncate">{label}</span>
              </Link>
            );
          })}
        </nav>
      </div>
    </div>
  );
}

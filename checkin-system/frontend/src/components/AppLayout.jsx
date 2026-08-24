import React, { useEffect, useState } from "react";
import { Layout, Menu, Typography, Space, Button, Grid, Avatar, Drawer } from "antd";
import {
  CalendarOutlined,
  TeamOutlined,
  SmileOutlined,
  LogoutOutlined,
  CrownOutlined,
  UserOutlined,
  EnvironmentOutlined,
  MenuOutlined,
} from "@ant-design/icons";
import { Link, useLocation, useNavigate } from "react-router-dom";
import { getEmployee, clearSession } from "../api";

const { Header, Sider, Content } = Layout;
const { Text } = Typography;
const { useBreakpoint } = Grid;
const logoSrc = "/logo-checkin.svg";

export default function AppLayout({ children }) {
  const emp = getEmployee();
  const loc = useLocation();
  const nav = useNavigate();
  const screens = useBreakpoint();
  const isBoss = Boolean(emp?.is_manager);

  // จอกว้างพอ (>= lg) ค่อยโชว์ sidebar ถาวร ที่แคบกว่านั้นใช้เมนูแบบดึงออกมา
  // (มือถือ/แท็บเล็ตแนวตั้ง) — เดิม sider ยุบเหลือ 0 โดยไม่มีปุ่มเปิด ทำให้
  // หัวหน้าเปิดจากมือถือแล้วกดเข้าเมนูอื่นไม่ได้เลย
  const isWide = Boolean(screens.lg);
  const [navOpen, setNavOpen] = useState(false);

  // เปลี่ยนหน้าแล้วปิดเมนูเอง ไม่ต้องกดกากบาททุกครั้ง
  useEffect(() => setNavOpen(false), [loc.pathname]);
  useEffect(() => {
    if (isWide) setNavOpen(false);
  }, [isWide]);

  const bossItems = [
    {
      key: "/",
      icon: <CalendarOutlined />,
      label: <Link to="/">ปฏิทินเข้างาน</Link>,
    },
    {
      key: "/employees",
      icon: <TeamOutlined />,
      label: <Link to="/employees">ข้อมูลพนักงาน</Link>,
    },
    {
      key: "/live-map",
      icon: <EnvironmentOutlined />,
      label: <Link to="/live-map">แผนที่ติดตามพนักงาน</Link>,
    },
  ];

  const employeeItems = [
    {
      key: "/",
      icon: <CalendarOutlined />,
      label: <Link to="/">ปฏิทินเข้างาน</Link>,
    },
    {
      key: "/face-records",
      icon: <SmileOutlined />,
      label: <Link to="/face-records">ประวัติใบหน้า</Link>,
    },
  ];

  const selectedKey = loc.pathname.startsWith("/employees")
    ? "/employees"
    : loc.pathname.startsWith("/live-map")
      ? "/live-map"
      : loc.pathname.startsWith("/face-records")
        ? "/face-records"
        : "/";

  const pageTitle = selectedKey === "/employees"
    ? "ข้อมูลพนักงาน"
    : selectedKey === "/live-map"
      ? "แผนที่ติดตามพนักงาน"
      : selectedKey === "/face-records"
        ? "ประวัติใบหน้า"
        : "ปฏิทินเข้างาน";

  function logout() {
    clearSession();
    nav("/login", { replace: true });
  }

  const account = (
    <Space size="small">
      <Avatar size="small" icon={isBoss ? <CrownOutlined /> : <UserOutlined />} />
      {!screens.xs && (
        <Text style={{ color: "#dbe4f0" }}>
          {emp?.full_name}
          {isBoss ? " (Boss)" : ""}
        </Text>
      )}
      <Button size="small" icon={<LogoutOutlined />} onClick={logout} ghost>
        {screens.xs ? "" : "ออกจากระบบ"}
      </Button>
    </Space>
  );

  if (!isBoss) {
    return (
      <Layout style={{ minHeight: "100vh" }}>
        <Header className="app-header">
          <div className="header-brand-wrap">
            <img className="header-logo" src={logoSrc} alt="" aria-hidden="true" />
            <Text strong className="header-brand">THANAKON-ROOM</Text>
          </div>
          <Menu
            theme="dark"
            mode="horizontal"
            selectedKeys={[selectedKey]}
            items={employeeItems}
            style={{ flex: 1, minWidth: 0 }}
          />
          {account}
        </Header>
        <Content className="app-content">{children}</Content>
      </Layout>
    );
  }

  const sidebarBrand = (
    <div className="sidebar-brand">
      <img className="sidebar-brand-logo" src={logoSrc} alt="" aria-hidden="true" />
      <div>
        <div className="sidebar-brand-name">THANAKON-ROOM</div>
        <div className="sidebar-brand-role">BOSS CONTROL</div>
      </div>
    </div>
  );

  const bossMenu = (
    <Menu
      theme="dark"
      mode="inline"
      selectedKeys={[selectedKey]}
      items={bossItems}
      className="boss-menu"
    />
  );

  return (
    <Layout style={{ minHeight: "100vh" }}>
      {isWide && (
        <Sider width={250} className="boss-sidebar">
          {sidebarBrand}
          {bossMenu}
        </Sider>
      )}

      {/* จอแคบ: เมนูเดียวกันแต่ดึงออกมาจากขอบซ้าย */}
      <Drawer
        placement="left"
        open={!isWide && navOpen}
        onClose={() => setNavOpen(false)}
        closable={false}
        width={260}
        className="boss-nav-drawer"
        styles={{ body: { padding: 0, background: "#001529" } }}
      >
        {sidebarBrand}
        {bossMenu}
      </Drawer>

      <Layout>
        <Header className="app-header boss-header">
          {!isWide && (
            <Button
              type="text"
              className="nav-toggle"
              aria-label="เปิดเมนู"
              icon={<MenuOutlined />}
              onClick={() => setNavOpen(true)}
            />
          )}
          {!isWide && (
            <div className="header-brand-wrap mobile-brand-wrap">
              <img className="header-logo" src={logoSrc} alt="" aria-hidden="true" />
              <Text strong className="header-brand mobile-brand">
                THANAKON-ROOM
              </Text>
            </div>
          )}
          <Text strong className="header-page-title">{pageTitle}</Text>
          <div style={{ marginLeft: "auto" }}>{account}</div>
        </Header>
        <Content className="boss-content">{children}</Content>
      </Layout>
    </Layout>
  );
}

import React from "react";
import { Layout, Menu, Typography, Space, Button, Grid, Avatar } from "antd";
import {
  CalendarOutlined,
  TeamOutlined,
  SmileOutlined,
  LogoutOutlined,
  CrownOutlined,
  UserOutlined,
} from "@ant-design/icons";
import { Link, useLocation, useNavigate } from "react-router-dom";
import { getEmployee, clearSession } from "../api";

const { Header, Sider, Content } = Layout;
const { Text } = Typography;
const { useBreakpoint } = Grid;

export default function AppLayout({ children }) {
  const emp = getEmployee();
  const loc = useLocation();
  const nav = useNavigate();
  const screens = useBreakpoint();
  const isBoss = Boolean(emp?.is_manager);

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
    : loc.pathname.startsWith("/face-records")
      ? "/face-records"
      : "/";

  const pageTitle = selectedKey === "/employees"
    ? "ข้อมูลพนักงาน"
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
          <Text strong className="header-brand">THANAKON-ROOM</Text>
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

  return (
    <Layout style={{ minHeight: "100vh" }}>
      <Sider
        width={250}
        breakpoint="lg"
        collapsedWidth="0"
        className="boss-sidebar"
      >
        <div className="sidebar-brand">
          <CrownOutlined className="sidebar-brand-icon" />
          <div>
            <div className="sidebar-brand-name">THANAKON-ROOM</div>
            <div className="sidebar-brand-role">BOSS CONTROL</div>
          </div>
        </div>
        <Menu
          theme="dark"
          mode="inline"
          selectedKeys={[selectedKey]}
          items={bossItems}
          className="boss-menu"
        />
      </Sider>

      <Layout>
        <Header className="app-header boss-header">
          {!screens.lg && (
            <Text strong className="header-brand mobile-brand">
              THANAKON-ROOM
            </Text>
          )}
          <Text strong className="header-page-title">{pageTitle}</Text>
          <div style={{ marginLeft: "auto" }}>{account}</div>
        </Header>
        <Content className="boss-content">{children}</Content>
      </Layout>
    </Layout>
  );
}

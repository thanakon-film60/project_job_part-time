import React from "react";
import { Layout, Menu, Typography, Space, Button, Grid } from "antd";
import {
  CalendarOutlined,
  SmileOutlined,
  LogoutOutlined,
} from "@ant-design/icons";
import { Link, useLocation, useNavigate } from "react-router-dom";
import { getEmployee, clearSession } from "../api";

const { Header, Content } = Layout;
const { Text } = Typography;
const { useBreakpoint } = Grid;

export default function AppLayout({ children }) {
  const emp = getEmployee();
  const loc = useLocation();
  const nav = useNavigate();
  const screens = useBreakpoint();

  const items = [
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

  function logout() {
    clearSession();
    nav("/login", { replace: true });
  }

  return (
    <Layout style={{ minHeight: "100vh" }}>
      <Header
        style={{
          display: "flex",
          alignItems: "center",
          gap: 16,
          paddingInline: screens.xs ? 12 : 24,
        }}
      >
        <Text strong style={{ color: "#fff", fontSize: 18, whiteSpace: "nowrap" }}>
          THANAKON-BOX
        </Text>
        <Menu
          theme="dark"
          mode="horizontal"
          selectedKeys={[loc.pathname]}
          items={items}
          style={{ flex: 1, minWidth: 0 }}
        />
        <Space size="small">
          {!screens.xs && (
            <Text style={{ color: "#cfd6ff" }}>
              {emp?.full_name}
              {emp?.is_manager ? " (ผู้จัดการ)" : ""}
            </Text>
          )}
          <Button
            size="small"
            icon={<LogoutOutlined />}
            onClick={logout}
            ghost
          >
            {screens.xs ? "" : "ออกจากระบบ"}
          </Button>
        </Space>
      </Header>
      <Content
        style={{
          padding: screens.xs ? 12 : 24,
          maxWidth: 1100,
          width: "100%",
          margin: "0 auto",
        }}
      >
        {children}
      </Content>
    </Layout>
  );
}

import React, { useState } from "react";
import { useNavigate, useLocation } from "react-router-dom";
import { Card, Form, Input, Button, Typography, Row, Col, Alert } from "antd";
import { UserOutlined, LockOutlined } from "@ant-design/icons";
import { login } from "../api";

const { Title, Paragraph } = Typography;

export default function LoginPage() {
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);
  const nav = useNavigate();
  const loc = useLocation();
  const from = loc.state?.from || "/";

  async function onFinish(values) {
    setError("");
    setLoading(true);
    try {
      await login(values.username.trim(), values.password);
      nav(from, { replace: true });
    } catch {
      setError("รหัสพนักงาน/อีเมล หรือรหัสผ่านไม่ถูกต้อง");
    } finally {
      setLoading(false);
    }
  }

  return (
    <Row
      justify="center"
      align="middle"
      style={{ minHeight: "100vh", background: "#f0f2f5", padding: 16 }}
    >
      <Col xs={24} sm={18} md={12} lg={9} xl={7}>
        <Card>
          <Title level={3} style={{ marginBottom: 0 }}>
            MARDODI เช็คอิน
          </Title>
          <Paragraph type="secondary">
            เข้าสู่ระบบเพื่อดูปฏิทินและจัดการประวัติใบหน้า
          </Paragraph>
          {error && (
            <Alert
              type="error"
              message={error}
              style={{ marginBottom: 16 }}
              showIcon
            />
          )}
          <Form layout="vertical" onFinish={onFinish} requiredMark={false}>
            <Form.Item
              name="username"
              label="รหัสพนักงาน / อีเมล"
              rules={[{ required: true, message: "กรอกรหัสพนักงานหรืออีเมล" }]}
            >
              <Input prefix={<UserOutlined />} placeholder="เช่น EMP001" size="large" />
            </Form.Item>
            <Form.Item
              name="password"
              label="รหัสผ่าน"
              rules={[{ required: true, message: "กรอกรหัสผ่าน" }]}
            >
              <Input.Password
                prefix={<LockOutlined />}
                placeholder="รหัสผ่าน"
                size="large"
              />
            </Form.Item>
            <Button
              type="primary"
              htmlType="submit"
              block
              size="large"
              loading={loading}
            >
              เข้าสู่ระบบ
            </Button>
          </Form>
        </Card>
      </Col>
    </Row>
  );
}

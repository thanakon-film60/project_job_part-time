import React, { useEffect, useMemo, useState } from "react";
import {
  Alert,
  Badge,
  Card,
  Col,
  Empty,
  Image,
  Row,
  Skeleton,
  Space,
  Statistic,
  Tag,
  Typography,
} from "antd";
import {
  CheckCircleOutlined,
  IdcardOutlined,
  MailOutlined,
  SafetyCertificateOutlined,
  TeamOutlined,
  UserOutlined,
  WarningOutlined,
} from "@ant-design/icons";
import AppLayout from "../components/AppLayout.jsx";
import {
  fetchFacePhoto,
  getEmployee,
  getEmployeeFaces,
  getEmployees,
} from "../api";

const { Title, Text } = Typography;

function FacePhoto({ record, employeeName, featured = false }) {
  const [url, setUrl] = useState("");
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    let active = true;
    let objectUrl = "";
    fetchFacePhoto(record.id)
      .then((value) => {
        objectUrl = value;
        if (active) setUrl(value);
        else URL.revokeObjectURL(value);
      })
      .catch(() => active && setFailed(true));

    return () => {
      active = false;
      if (objectUrl) URL.revokeObjectURL(objectUrl);
    };
  }, [record.id]);

  if (failed) {
    return (
      <div className={`employee-face-placeholder ${featured ? "featured" : ""}`}>
        <WarningOutlined />
        <span>โหลดรูปไม่ได้</span>
      </div>
    );
  }

  if (!url) {
    return <Skeleton.Image active className={featured ? "face-skeleton featured" : "face-skeleton"} />;
  }

  return (
    <Image
      src={url}
      alt={`รูปยืนยันตัวตนของ ${employeeName}`}
      preview
      className={featured ? "employee-face featured" : "employee-face"}
    />
  );
}

function EmployeeCard({ employee }) {
  const [faces, setFaces] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

  useEffect(() => {
    let active = true;
    getEmployeeFaces(employee.id)
      .then((records) => active && setFaces(records))
      .catch((err) => active && setError(err.message || "โหลดรูปใบหน้าไม่สำเร็จ"))
      .finally(() => active && setLoading(false));
    return () => {
      active = false;
    };
  }, [employee.id]);

  const latestFace = faces[0];

  return (
    <Card className="employee-card" bordered={false}>
      <Row gutter={[20, 20]}>
        <Col xs={24} sm={8} md={7} xl={6}>
          <Badge.Ribbon
            text={latestFace ? "พร้อมยืนยันตัวตน" : "ยังไม่มีรูปใบหน้า"}
            color={latestFace ? "green" : "orange"}
          >
            <div className="employee-main-face">
              {loading ? (
                <Skeleton.Image active className="face-skeleton featured" />
              ) : latestFace ? (
                <FacePhoto record={latestFace} employeeName={employee.full_name} featured />
              ) : (
                <div className="employee-face-placeholder featured">
                  <UserOutlined />
                  <span>ไม่มีรูปยืนยันตัวตน</span>
                </div>
              )}
            </div>
          </Badge.Ribbon>
        </Col>

        <Col xs={24} sm={16} md={17} xl={18}>
          <Space direction="vertical" size={10} style={{ width: "100%" }}>
            <div>
              <Title level={4} style={{ margin: 0 }}>{employee.full_name}</Title>
              <Tag color="blue" style={{ marginTop: 7 }}>พนักงาน</Tag>
              <Tag color={latestFace ? "success" : "warning"}>
                {latestFace ? `รูปยืนยัน ${faces.length} รูป` : "ยังไม่ได้ลงทะเบียนใบหน้า"}
              </Tag>
            </div>

            <div className="employee-details">
              <Text><IdcardOutlined /> รหัสพนักงาน: <strong>{employee.employee_code}</strong></Text>
              <Text><MailOutlined /> อีเมล: {employee.email}</Text>
              {employee.created_at && (
                <Text type="secondary">
                  ลงทะเบียนเมื่อ {new Date(employee.created_at).toLocaleString("th-TH")}
                </Text>
              )}
            </div>

            {error && <Alert type="error" showIcon message={error} />}

            {faces.length > 1 && (
              <div>
                <Text type="secondary">รูปใบหน้าเพิ่มเติม</Text>
                <div className="employee-face-list">
                  {faces.slice(1).map((face) => (
                    <FacePhoto key={face.id} record={face} employeeName={employee.full_name} />
                  ))}
                </div>
              </div>
            )}

            {latestFace && (
              <Text type="secondary" className="face-updated-at">
                <CheckCircleOutlined /> รูปล่าสุดบันทึกเมื่อ {new Date(latestFace.created_at).toLocaleString("th-TH")}
              </Text>
            )}
          </Space>
        </Col>
      </Row>
    </Card>
  );
}

export default function EmployeesPage() {
  const me = getEmployee();
  const [employees, setEmployees] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

  useEffect(() => {
    getEmployees()
      .then(setEmployees)
      .catch((err) => setError(err.message || "โหลดข้อมูลพนักงานไม่สำเร็จ"))
      .finally(() => setLoading(false));
  }, []);

  const staff = useMemo(
    () => employees.filter((employee) => !employee.is_manager),
    [employees],
  );

  if (!me?.is_manager) {
    return (
      <AppLayout>
        <Alert type="error" showIcon message="หน้านี้สำหรับ Boss เท่านั้น" />
      </AppLayout>
    );
  }

  return (
    <AppLayout>
      <div className="page-heading">
        <div>
          <Title level={2} style={{ marginBottom: 4 }}>ข้อมูลพนักงาน</Title>
          <Text type="secondary">รายชื่อและรูปใบหน้าที่ลงทะเบียนไว้สำหรับยืนยันตัวตน</Text>
        </div>
      </div>

      <Row gutter={[16, 16]} className="employee-stats">
        <Col xs={12} sm={12} lg={8}>
          <Card bordered={false}>
            <Statistic title="พนักงานทั้งหมด" value={staff.length} suffix="คน" prefix={<TeamOutlined />} />
          </Card>
        </Col>
        <Col xs={12} sm={12} lg={8}>
          <Card bordered={false}>
            <Statistic
              title="บัญชี Boss"
              value={employees.filter((employee) => employee.is_manager).length}
              suffix="บัญชี"
              prefix={<SafetyCertificateOutlined />}
            />
          </Card>
        </Col>
      </Row>

      {error && <Alert type="error" showIcon message={error} style={{ marginBottom: 16 }} />}

      {loading ? (
        <Card bordered={false}><Skeleton active avatar paragraph={{ rows: 5 }} /></Card>
      ) : staff.length === 0 ? (
        <Card bordered={false}><Empty description="ยังไม่มีพนักงานในระบบ" /></Card>
      ) : (
        <Space direction="vertical" size={16} style={{ width: "100%" }}>
          {staff.map((employee) => <EmployeeCard key={employee.id} employee={employee} />)}
        </Space>
      )}
    </AppLayout>
  );
}

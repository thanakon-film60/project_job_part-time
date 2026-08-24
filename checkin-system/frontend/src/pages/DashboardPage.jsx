import React, { useEffect, useMemo, useState } from "react";
import {
  Alert,
  Avatar,
  Card,
  Calendar,
  Col,
  Empty,
  List,
  Modal,
  Row,
  Space,
  Statistic,
  Tag,
  Typography,
} from "antd";
import {
  CalendarOutlined,
  ClockCircleOutlined,
  EnvironmentOutlined,
  LoginOutlined,
  LogoutOutlined,
  TeamOutlined,
  UserOutlined,
} from "@ant-design/icons";
import dayjs from "dayjs";
import utc from "dayjs/plugin/utc";
import "dayjs/locale/th";
import { getEmployee, getTeamCalendar } from "../api";
import AppLayout from "../components/AppLayout.jsx";
import AppDownloadCard from "../components/AppDownloadCard.jsx";

dayjs.locale("th");
dayjs.extend(utc);

// เวลาไทย = UTC+7 (นาที) — ฝั่ง API ส่ง ISO ที่ติด offset มาแล้ว ตรงนี้บังคับอีกชั้น
// เพื่อให้เห็นเวลาไทยเหมือนกันหมด ต่อให้เปิดจากเครื่อง/มือถือที่ตั้ง timezone อื่นไว้
const THAI_OFFSET_MINUTES = 7 * 60;

function thaiTime(iso) {
  if (!iso) return "–";
  return dayjs(iso).utcOffset(THAI_OFFSET_MINUTES).format("HH:mm");
}

const { Text, Title } = Typography;

function locationColor(location) {
  if (location === "อยู่ที่บ้าน") return "purple";
  if (location === "นอกเขต") return "orange";
  return "green";
}

export default function DashboardPage() {
  const me = getEmployee();
  const [value, setValue] = useState(dayjs());
  const [days, setDays] = useState([]);
  const [selectedDay, setSelectedDay] = useState(null);
  const [loading, setLoading] = useState(false);
  const [err, setErr] = useState("");

  useEffect(() => {
    if (!me?.is_manager) return;
    setLoading(true);
    setErr("");
    getTeamCalendar(value.year(), value.month() + 1)
      .then((response) => setDays(response.days))
      .catch((error) => setErr(String(error.message || error)))
      .finally(() => setLoading(false));
  }, [value.year(), value.month(), me?.is_manager]);

  const byDate = useMemo(() => {
    const result = {};
    days.forEach((day) => {
      result[day.date] = day;
    });
    return result;
  }, [days]);

  const activeEmployees = useMemo(() => {
    const ids = new Set();
    days.forEach((day) => day.people.forEach((person) => ids.add(person.employee_id)));
    return ids.size;
  }, [days]);

  function openDay(current) {
    setValue(current);
    const day = byDate[current.format("YYYY-MM-DD")];
    if (day?.people?.length) setSelectedDay(day);
  }

  function cellRender(current, info) {
    if (info.type !== "date") return info.originNode;
    const day = byDate[current.format("YYYY-MM-DD")];
    if (!day) return null;

    const visible = day.people.slice(0, 3);
    return (
      <div className="team-cal-cell">
        {visible.map((person) => (
          <div className="calendar-person" key={person.employee_id}>
            <div className="calendar-person-name">
              <UserOutlined /> {person.full_name}
            </div>
            {person.locations.slice(0, 1).map((location) => (
              <Tag key={location} color={locationColor(location)}>{location}</Tag>
            ))}
          </div>
        ))}
        {day.people.length > visible.length && (
          <Text type="secondary" className="more-people">
            +{day.people.length - visible.length} คน
          </Text>
        )}
      </div>
    );
  }

  // หน้าแรกของพนักงานทั่วไป — สิ่งแรกที่ต้องเห็นคือปุ่มโหลดแอปสำหรับเช็คอิน
  if (!me?.is_manager) {
    return (
      <AppLayout>
        <AppDownloadCard />
        <Alert
          type="info"
          showIcon
          style={{ marginTop: 16 }}
          message="หน้าปฏิทินรวมสำหรับ Boss เท่านั้น"
          description="พนักงานทั่วไปใช้แอป Flutter เพื่อเช็กอิน และดูประวัติใบหน้าของตนเอง"
        />
      </AppLayout>
    );
  }

  return (
    <AppLayout>
      <div className="page-heading calendar-heading">
        <div>
          <Title level={2} style={{ marginBottom: 4 }}>ปฏิทินเข้างาน</Title>
          <Text type="secondary">ชื่อที่แสดงคือพนักงานที่ลงเวลาในวันนั้น กดวันที่เพื่อดูเวลาเข้า–ออก</Text>
        </div>
      </div>

      <Row gutter={[16, 16]} className="calendar-stats">
        <Col xs={12} sm={12} lg={8}>
          <Card bordered={false}>
            <Statistic
              title={`พนักงานที่ลงเวลา (${value.format("MMMM YYYY")})`}
              value={activeEmployees}
              suffix="คน"
              prefix={<TeamOutlined />}
            />
          </Card>
        </Col>
        <Col xs={12} sm={12} lg={8}>
          <Card bordered={false}>
            <Statistic
              title="วันที่มีการลงเวลา"
              value={days.length}
              suffix="วัน"
              prefix={<CalendarOutlined />}
            />
          </Card>
        </Col>
      </Row>

      {err && <Alert type="error" showIcon message={err} style={{ marginBottom: 16 }} />}

      <Card className="team-calendar-card" loading={loading} bordered={false}>
        <Calendar
          value={value}
          onSelect={openDay}
          onPanelChange={setValue}
          cellRender={cellRender}
        />
      </Card>

      <Modal
        open={Boolean(selectedDay)}
        title={selectedDay ? `ผู้ที่ลงเวลา — ${dayjs(selectedDay.date).format("D MMMM YYYY")}` : ""}
        onCancel={() => setSelectedDay(null)}
        footer={null}
        width={680}
        centered
        className="attendance-modal"
        // จอเล็กกว่า 680px ต้องหดตามจอ ไม่งั้นเนื้อหาล้นออกนอกขอบ
        style={{ maxWidth: "calc(100vw - 24px)" }}
        styles={{ body: { maxHeight: "70vh", overflowY: "auto" } }}
      >
        {!selectedDay?.people?.length ? (
          <Empty description="ไม่มีผู้ลงเวลาในวันนี้" />
        ) : (
          <List
            itemLayout="horizontal"
            dataSource={selectedDay.people}
            renderItem={(person) => (
              <List.Item className="attendance-person-row">
                <List.Item.Meta
                  avatar={<Avatar size={44} icon={<UserOutlined />} />}
                  title={
                    <Space wrap>
                      <Text strong>{person.full_name}</Text>
                      <Tag>{person.employee_code}</Tag>
                    </Space>
                  }
                  description={
                    <div className="attendance-details">
                      <Space wrap size={[16, 6]}>
                        <Text className="time-in">
                          <LoginOutlined /> เข้า {thaiTime(person.first_in)}
                        </Text>
                        <Text className="time-out">
                          <LogoutOutlined /> ออก {thaiTime(person.last_out)}
                        </Text>
                        <Text type="secondary">
                          <ClockCircleOutlined /> ลงเวลาทั้งหมด {person.count} ครั้ง
                        </Text>
                      </Space>
                      <div className="attendance-locations">
                        <EnvironmentOutlined />
                        {person.locations.map((location) => (
                          <Tag key={location} color={locationColor(location)}>{location}</Tag>
                        ))}
                      </div>
                    </div>
                  }
                />
              </List.Item>
            )}
          />
        )}
      </Modal>
    </AppLayout>
  );
}

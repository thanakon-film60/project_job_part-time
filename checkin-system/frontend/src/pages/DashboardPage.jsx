import React, { useEffect, useMemo, useState } from "react";
import {
  Card,
  Calendar,
  Select,
  Row,
  Col,
  Statistic,
  Tag,
  Alert,
  Typography,
  Space,
} from "antd";
import dayjs from "dayjs";
import { getEmployee, getEmployees, getCalendar, getGeofence } from "../api";
import AppLayout from "../components/AppLayout.jsx";

const { Text } = Typography;

export default function DashboardPage() {
  const me = getEmployee();
  const [employees, setEmployees] = useState([]);
  const [empId, setEmpId] = useState(me?.id || null);
  const [value, setValue] = useState(dayjs());
  const [days, setDays] = useState([]);
  const [geo, setGeo] = useState(null);
  const [err, setErr] = useState("");

  useEffect(() => {
    getGeofence().then(setGeo).catch(() => {});
    if (me?.is_manager) {
      getEmployees()
        .then((list) => {
          setEmployees(list);
          const staff = list.find((e) => !e.is_manager) || list[0];
          if (staff) setEmpId(staff.id);
        })
        .catch(() => {});
    }
  }, []);

  useEffect(() => {
    if (!empId || !me?.is_manager) return;
    getCalendar(empId, value.year(), value.month() + 1)
      .then((res) => setDays(res.days))
      .catch((e) => setErr(String(e.message)));
  }, [empId, value]);

  const byDate = useMemo(() => {
    const m = {};
    days.forEach((d) => (m[d.date] = d));
    return m;
  }, [days]);

  const presentDays = days.filter((d) => d.within_geofence).length;

  function cellRender(current, info) {
    if (info.type !== "date") return info.originNode;
    const s = byDate[current.format("YYYY-MM-DD")];
    if (!s) return null;
    return (
      <div className="cal-cell">
        {s.first_in && (
          <div className="t-in">เข้า {dayjs(s.first_in).format("HH:mm")}</div>
        )}
        {s.last_out && (
          <div className="t-out">ออก {dayjs(s.last_out).format("HH:mm")}</div>
        )}
        <Tag color={s.within_geofence ? "green" : "orange"} style={{ marginTop: 2 }}>
          {s.within_geofence ? "ในออฟฟิศ" : "นอกเขต"}
        </Tag>
      </div>
    );
  }

  if (!me?.is_manager) {
    return (
      <AppLayout>
        <Alert
          type="info"
          showIcon
          message="หน้าปฏิทินรวมสำหรับผู้จัดการเท่านั้น"
          description="พนักงานทั่วไปใช้แอป Flutter เพื่อเช็คอิน และดูประวัติใบหน้าของตนเองที่แท็บ 'ประวัติใบหน้า'"
        />
      </AppLayout>
    );
  }

  return (
    <AppLayout>
      <Row gutter={[16, 16]} style={{ marginBottom: 16 }}>
        <Col xs={24} md={16}>
          <Card size="small">
            <Space wrap size="middle" style={{ width: "100%" }}>
              <span>
                <Text type="secondary">พนักงาน: </Text>
                <Select
                  value={empId}
                  style={{ minWidth: 220 }}
                  onChange={setEmpId}
                  options={employees.map((e) => ({
                    value: e.id,
                    label: `${e.full_name} (${e.employee_code})`,
                  }))}
                />
              </span>
              {geo && (
                <Text type="secondary">
                  {/* รองรับหลายสถานที่ — ถ้า API เก่ายังไม่ส่ง offices มา ให้ถอยไปใช้ฟิลด์เดิม */}
                  สถานที่เข้างาน:{" "}
                  {(geo.offices?.length
                    ? geo.offices
                    : [
                        {
                          name: geo.office_name,
                          radius_km: geo.radius_km,
                        },
                      ]
                  )
                    .map((o) => `${o.name} (${o.radius_km} กม.)`)
                    .join(" · ")}
                </Text>
              )}
            </Space>
          </Card>
        </Col>
        <Col xs={24} md={8}>
          <Card size="small">
            <Statistic
              title={`มาทำงานในเขต (${value.format("MMMM YYYY")})`}
              value={presentDays}
              suffix="วัน"
            />
          </Card>
        </Col>
      </Row>

      {err && <Alert type="error" message={err} style={{ marginBottom: 16 }} />}

      <Card>
        <Calendar
          value={value}
          onChange={setValue}
          onPanelChange={setValue}
          cellRender={cellRender}
        />
      </Card>
    </AppLayout>
  );
}

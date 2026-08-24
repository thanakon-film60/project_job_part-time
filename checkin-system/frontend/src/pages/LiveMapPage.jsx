import React, { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  Alert,
  Badge,
  Button,
  Card,
  Col,
  Empty,
  List,
  Row,
  Segmented,
  Skeleton,
  Space,
  Switch,
  Tag,
  Typography,
} from "antd";
import {
  AimOutlined,
  EnvironmentOutlined,
  ReloadOutlined,
  CompassOutlined,
} from "@ant-design/icons";
import {
  MapContainer,
  TileLayer,
  Marker,
  Popup,
  Circle,
  Polyline,
  useMap,
} from "react-leaflet";
import L from "leaflet";
import "leaflet/dist/leaflet.css";
import AppLayout from "../components/AppLayout.jsx";
import { getGeofence, getLiveLocations, getLocationTrail } from "../api";

const { Title, Text } = Typography;

const REFRESH_SECONDS = 20;
const DEFAULT_CENTER = [13.8712, 100.4155]; // บางบัวทอง — ใช้เมื่อยังไม่มีข้อมูลอะไรเลย
const DEFAULT_ZOOM = 13;

// สี/ข้อความประจำแต่ละสถานะ ใช้ร่วมกันทั้งหมุดบนแผนที่และรายชื่อด้านข้าง
// เพื่อไม่ให้สองที่นี้เพี้ยนกัน
const STATUS_META = {
  online: { color: "#2e7d32", label: "กำลังส่งตำแหน่ง", badge: "success" },
  stale: { color: "#f9a825", label: "ไม่อัปเดตสักพัก", badge: "warning" },
  offline: { color: "#c62828", label: "ขาดการติดต่อ", badge: "error" },
  no_data: { color: "#9e9e9e", label: "ไม่มีข้อมูล", badge: "default" },
};

function statusMeta(status) {
  return STATUS_META[status] || STATUS_META.no_data;
}

function formatAge(seconds) {
  if (seconds == null) return "ไม่เคยส่งพิกัด";
  if (seconds < 60) return "เมื่อสักครู่";
  const mins = Math.floor(seconds / 60);
  if (mins < 60) return `${mins} นาทีที่แล้ว`;
  const hours = Math.floor(mins / 60);
  if (hours < 24) return `${hours} ชม. ${mins % 60} นาทีที่แล้ว`;
  return `${Math.floor(hours / 24)} วันที่แล้ว`;
}

// หมุดเป็นวงกลมสีตามสถานะ พร้อมอักษรย่อของชื่อ -- ใช้ divIcon แทนไฟล์รูป
// เพราะ marker icon ของ leaflet ตั้งค่า path ยากเมื่อ bundle ด้วย Vite
function employeeIcon(person) {
  const { color } = statusMeta(person.status);
  const initial = (person.full_name || "?").trim().charAt(0);
  return L.divIcon({
    className: "",
    html: `<div style="
      width:30px;height:30px;border-radius:50%;
      background:${color};border:3px solid #fff;
      box-shadow:0 0 4px rgba(0,0,0,0.5);
      color:#fff;font-weight:700;font-size:13px;
      display:flex;align-items:center;justify-content:center;
      font-family:'Segoe UI','Noto Sans Thai',sans-serif;
    ">${initial}</div>`,
    iconSize: [30, 30],
    iconAnchor: [15, 15],
  });
}

// ขยับแผนที่ไปยังคนที่ถูกเลือก โดยไม่ต้อง re-mount ทั้ง MapContainer
function MapFocus({ target }) {
  const map = useMap();
  useEffect(() => {
    if (target) map.flyTo(target, Math.max(map.getZoom(), 16), { duration: 0.8 });
  }, [target, map]);
  return null;
}

// Leaflet จำขนาดกล่องแผนที่ไว้ตอน mount ถ้าขนาดเปลี่ยนทีหลัง (หมุนจอมือถือ,
// ย่อ/ขยายหน้าต่าง, sidebar เปิด-ปิด) จะเหลือแต่พื้นเทาเป็นแถบ ต้องสั่งวัดใหม่เอง
function ResizeAware() {
  const map = useMap();
  useEffect(() => {
    const refresh = () => map.invalidateSize();
    window.addEventListener("resize", refresh);
    window.addEventListener("orientationchange", refresh);
    // เผื่อกรณี layout ยังจัดไม่เสร็จตอน mount แรก
    const timer = setTimeout(refresh, 300);
    return () => {
      window.removeEventListener("resize", refresh);
      window.removeEventListener("orientationchange", refresh);
      clearTimeout(timer);
    };
  }, [map]);
  return null;
}

// ครอบคลุมทุกหมุดในครั้งแรกที่โหลดข้อมูลได้ เพื่อไม่ให้หัวหน้าต้องซูมหาเอง
function FitAllOnce({ points }) {
  const map = useMap();
  const done = useRef(false);
  useEffect(() => {
    if (done.current || points.length === 0) return;
    done.current = true;
    if (points.length === 1) {
      map.setView(points[0], 16);
    } else {
      map.fitBounds(L.latLngBounds(points), { padding: [40, 40] });
    }
  }, [points, map]);
  return null;
}

export default function LiveMapPage() {
  const [data, setData] = useState(null);
  const [geofence, setGeofence] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [lastUpdated, setLastUpdated] = useState(null);

  const [autoRefresh, setAutoRefresh] = useState(true);
  const [selectedId, setSelectedId] = useState(null);
  const [focusTarget, setFocusTarget] = useState(null);

  const [trail, setTrail] = useState([]);
  const [trailHours, setTrailHours] = useState(0); // 0 = ไม่แสดงเส้นทาง

  const load = useCallback(async (opts = {}) => {
    if (!opts.silent) setLoading(true);
    try {
      const res = await getLiveLocations();
      setData(res);
      setLastUpdated(new Date());
      setError(null);
    } catch (err) {
      setError(err?.message || "โหลดตำแหน่งพนักงานไม่สำเร็จ");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    load();
    getGeofence()
      .then(setGeofence)
      .catch(() => setGeofence(null)); // ไม่มีวงเขตก็ยังดูแผนที่ได้ ไม่ต้องขึ้น error
  }, [load]);

  // รีเฟรชเงียบๆ เป็นระยะ (silent = ไม่ขึ้น skeleton ไม่ให้หน้ากระพริบ)
  useEffect(() => {
    if (!autoRefresh) return undefined;
    const id = setInterval(() => load({ silent: true }), REFRESH_SECONDS * 1000);
    return () => clearInterval(id);
  }, [autoRefresh, load]);

  // โหลดเส้นทางย้อนหลังเมื่อเลือกคน + เปิดโหมดเส้นทาง
  useEffect(() => {
    if (!selectedId || trailHours === 0) {
      setTrail([]);
      return undefined;
    }
    let active = true;
    getLocationTrail(selectedId, trailHours)
      .then((rows) => {
        if (active) setTrail(rows);
      })
      .catch(() => {
        if (active) setTrail([]);
      });
    return () => {
      active = false;
    };
  }, [selectedId, trailHours]);

  const employees = data?.employees ?? [];
  const located = useMemo(
    () => employees.filter((e) => e.latitude != null && e.longitude != null),
    [employees],
  );
  const allPoints = useMemo(
    () => located.map((e) => [e.latitude, e.longitude]),
    [located],
  );

  const counts = useMemo(() => {
    const c = { online: 0, stale: 0, offline: 0, no_data: 0 };
    employees.forEach((e) => {
      c[e.status] = (c[e.status] || 0) + 1;
    });
    return c;
  }, [employees]);

  const offices = geofence?.offices?.length
    ? geofence.offices
    : geofence
      ? [
          {
            name: geofence.office_name,
            lat: geofence.office_lat,
            lng: geofence.office_lng,
            radius_km: geofence.radius_km,
          },
        ]
      : [];

  const mapCenter = allPoints[0] || (offices[0] ? [offices[0].lat, offices[0].lng] : DEFAULT_CENTER);

  const trailPositions = trail
    .filter((p) => p.latitude != null && p.longitude != null)
    .map((p) => [p.latitude, p.longitude]);

  function selectPerson(person) {
    setSelectedId(person.employee_id);
    if (person.latitude != null && person.longitude != null) {
      setFocusTarget([person.latitude, person.longitude]);
    }
  }

  return (
    <AppLayout>
      <Space direction="vertical" size={16} style={{ width: "100%" }}>
        <div>
          <Title level={4} style={{ margin: 0 }}>
            <EnvironmentOutlined /> แผนที่ติดตามพนักงาน
          </Title>
          <Text type="secondary">
            ดูว่าตอนนี้พนักงานแต่ละคนอยู่ตรงไหน อัปเดตอัตโนมัติทุก {REFRESH_SECONDS} วินาที
          </Text>
        </div>

        {error && <Alert type="error" showIcon message={error} />}

        <Row gutter={[12, 12]}>
          {[
            ["online", counts.online],
            ["stale", counts.stale],
            ["offline", counts.offline],
            ["no_data", counts.no_data],
          ].map(([status, value]) => {
            const meta = statusMeta(status);
            return (
              <Col xs={12} md={6} key={status}>
                <Card size="small" styles={{ body: { padding: 12 } }}>
                  <Space direction="vertical" size={0}>
                    <Text type="secondary" style={{ fontSize: "0.78rem" }}>
                      <Badge status={meta.badge} /> {meta.label}
                    </Text>
                    <Text strong style={{ fontSize: "1.5rem", color: meta.color }}>
                      {value}
                    </Text>
                  </Space>
                </Card>
              </Col>
            );
          })}
        </Row>

        <Card
          size="small"
          styles={{ body: { padding: 12 } }}
          title={
            <Space wrap size={12}>
              <Space size={6}>
                <ReloadOutlined />
                <Text style={{ fontSize: "0.85rem" }}>อัปเดตอัตโนมัติ</Text>
                <Switch size="small" checked={autoRefresh} onChange={setAutoRefresh} />
              </Space>
              {lastUpdated && (
                <Text type="secondary" style={{ fontSize: "0.78rem" }}>
                  ล่าสุด {lastUpdated.toLocaleTimeString("th-TH")}
                </Text>
              )}
            </Space>
          }
          extra={
            <Button
              size="small"
              icon={<ReloadOutlined />}
              loading={loading}
              onClick={() => load()}
            >
              รีเฟรช
            </Button>
          }
        >
          <Space wrap size={10}>
            <Text style={{ fontSize: "0.85rem" }}>
              <CompassOutlined /> เส้นทางย้อนหลังของคนที่เลือก:
            </Text>
            <Segmented
              size="small"
              value={trailHours}
              onChange={setTrailHours}
              options={[
                { label: "ไม่แสดง", value: 0 },
                { label: "1 ชม.", value: 1 },
                { label: "6 ชม.", value: 6 },
                { label: "24 ชม.", value: 24 },
              ]}
            />
            {trailHours > 0 && !selectedId && (
              <Text type="secondary" style={{ fontSize: "0.78rem" }}>
                เลือกชื่อพนักงานด้านล่างก่อน
              </Text>
            )}
          </Space>
        </Card>

        <Row gutter={[16, 16]}>
          <Col xs={24} lg={16}>
            <div className="live-map-frame">
              <MapContainer
                center={mapCenter}
                zoom={DEFAULT_ZOOM}
                style={{ height: "100%", width: "100%" }}
              >
                <TileLayer
                  attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
                  url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
                />

                <ResizeAware />
                <FitAllOnce points={allPoints} />
                <MapFocus target={focusTarget} />

                {/* วงเขตของแต่ละสถานที่ (geofence) -- radius มาเป็น กม. ต้องคูณ 1000 */}
                {offices.map((o) => (
                  <Circle
                    key={o.name}
                    center={[o.lat, o.lng]}
                    radius={(o.radius_km || 0) * 1000}
                    pathOptions={{ color: "#1565c0", fillColor: "#1565c0", fillOpacity: 0.08 }}
                  >
                    <Popup>
                      <strong>{o.name}</strong>
                      <br />
                      รัศมี {o.radius_km} กม.
                    </Popup>
                  </Circle>
                ))}

                {trailPositions.length > 1 && (
                  <Polyline
                    positions={trailPositions}
                    pathOptions={{ color: "#7b1fa2", weight: 4, opacity: 0.7 }}
                  />
                )}

                {located.map((person) => (
                  <Marker
                    key={person.employee_id}
                    position={[person.latitude, person.longitude]}
                    icon={employeeIcon(person)}
                    eventHandlers={{ click: () => setSelectedId(person.employee_id) }}
                  >
                    <Popup>
                      <strong>{person.full_name}</strong>
                      <br />
                      {statusMeta(person.status).label} — {formatAge(person.seconds_ago)}
                      <br />
                      {person.within_geofence
                        ? `อยู่ในเขต ${person.office_name || "ที่ทำงาน"}`
                        : `นอกเขต ห่าง ${person.distance_km?.toFixed(2)} กม. จาก ${person.office_name || "ที่ทำงาน"}`}
                      <br />
                      <a
                        href={`https://www.google.com/maps/dir/?api=1&destination=${person.latitude},${person.longitude}&travelmode=driving`}
                        target="_blank"
                        rel="noreferrer"
                      >
                        🧭 นำทางไปหา
                      </a>
                    </Popup>
                  </Marker>
                ))}
              </MapContainer>
            </div>
          </Col>

          <Col xs={24} lg={8}>
            <Card
              size="small"
              className="live-people-card"
              title={`พนักงานทั้งหมด (${employees.length})`}
              styles={{ body: { padding: 0 } }}
            >
              {loading && !data ? (
                <div style={{ padding: 16 }}>
                  <Skeleton active paragraph={{ rows: 6 }} />
                </div>
              ) : employees.length === 0 ? (
                <Empty
                  description="ยังไม่มีพนักงานในระบบ"
                  style={{ padding: 24 }}
                />
              ) : (
                <List
                  dataSource={employees}
                  renderItem={(person) => {
                    const meta = statusMeta(person.status);
                    const hasPos = person.latitude != null;
                    const isSelected = person.employee_id === selectedId;
                    return (
                      <List.Item
                        onClick={() => selectPerson(person)}
                        style={{
                          padding: "10px 14px",
                          cursor: "pointer",
                          background: isSelected ? "#eaf2fe" : undefined,
                        }}
                        actions={
                          hasPos
                            ? [
                                <Button
                                  key="focus"
                                  type="text"
                                  size="small"
                                  icon={<AimOutlined />}
                                  onClick={(e) => {
                                    e.stopPropagation();
                                    selectPerson(person);
                                  }}
                                />,
                              ]
                            : undefined
                        }
                      >
                        <List.Item.Meta
                          avatar={<Badge status={meta.badge} />}
                          title={
                            <Space size={6} wrap>
                              <Text strong>{person.full_name}</Text>
                              {person.is_manager && <Tag color="gold">Boss</Tag>}
                            </Space>
                          }
                          description={
                            <Space direction="vertical" size={0}>
                              <Text style={{ fontSize: "0.78rem", color: meta.color }}>
                                {meta.label} · {formatAge(person.seconds_ago)}
                              </Text>
                              {hasPos && (
                                <Text type="secondary" style={{ fontSize: "0.75rem" }}>
                                  {person.within_geofence
                                    ? `ในเขต ${person.office_name || "ที่ทำงาน"}`
                                    : `นอกเขต ${person.distance_km?.toFixed(1)} กม.`}
                                </Text>
                              )}
                            </Space>
                          }
                        />
                      </List.Item>
                    );
                  }}
                />
              )}
            </Card>
          </Col>
        </Row>

        <Alert
          type="info"
          showIcon
          message="ตำแหน่งมาจากแอปมือถือของพนักงาน"
          description="แอปจะส่งพิกัดมาเป็นระยะขณะเปิดใช้งาน ถ้าพนักงานปิดแอป ปิด GPS หรือเน็ตหลุด ตำแหน่งจะค้างอยู่ที่จุดสุดท้ายและสถานะจะเปลี่ยนเป็น 'ขาดการติดต่อ' เอง"
        />
      </Space>
    </AppLayout>
  );
}

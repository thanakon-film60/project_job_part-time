import React, { useCallback, useEffect, useMemo, useRef, useState } from "react";
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
import { CircleAlert, Compass, Crosshair, Info, MapPin, RefreshCw } from "lucide-react";
import AppLayout from "../components/AppLayout.jsx";
import { getGeofence, getLiveLocations, getLocationTrail } from "../api";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { EmptyState } from "@/components/ui/empty-state";
import { Skeleton } from "@/components/ui/skeleton";
import { Switch } from "@/components/ui/switch";
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group";
import { cn } from "@/lib/utils";

const REFRESH_SECONDS = 20;
const DEFAULT_CENTER = [13.8712, 100.4155]; // บางบัวทอง — ใช้เมื่อยังไม่มีข้อมูลอะไรเลย
const DEFAULT_ZOOM = 13;

// สี/ข้อความประจำแต่ละสถานะ ใช้ร่วมกันทั้งหมุดบนแผนที่และรายชื่อด้านข้าง
// เพื่อไม่ให้สองที่นี้เพี้ยนกัน (สี hex ใช้ตรง ๆ เพราะหมุด leaflet เป็น HTML ดิบ)
const STATUS_META = {
  online: { color: "#2e7d32", label: "กำลังส่งตำแหน่ง", dot: "bg-success" },
  stale: { color: "#f9a825", label: "ไม่อัปเดตสักพัก", dot: "bg-warning" },
  offline: { color: "#c62828", label: "ขาดการติดต่อ", dot: "bg-destructive" },
  no_data: { color: "#9e9e9e", label: "ไม่มีข้อมูล", dot: "bg-muted-foreground" },
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
      font-family:'Sarabun','Segoe UI',sans-serif;
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

  const mapCenter =
    allPoints[0] || (offices[0] ? [offices[0].lat, offices[0].lng] : DEFAULT_CENTER);

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
      <div className="space-y-4">
        <div className="hidden lg:block">
          <h2 className="flex items-center gap-2 text-2xl font-bold">
            <MapPin className="size-6" />
            แผนที่ติดตามพนักงาน
          </h2>
          <p className="text-muted-foreground text-sm">
            ดูว่าตอนนี้พนักงานแต่ละคนอยู่ตรงไหน อัปเดตอัตโนมัติทุก {REFRESH_SECONDS} วินาที
          </p>
        </div>

        {error && (
          <Alert variant="destructive">
            <CircleAlert />
            <AlertDescription className="text-foreground">{error}</AlertDescription>
          </Alert>
        )}

        {/* สรุปสถานะ — 2 คอลัมน์บนมือถือ, 4 บนแท็บเล็ตขึ้นไป */}
        <div className="grid grid-cols-2 gap-2 sm:gap-3 md:grid-cols-4">
          {["online", "stale", "offline", "no_data"].map((status) => {
            const meta = statusMeta(status);
            return (
              <Card key={status} className="gap-0 py-3">
                <CardContent className="px-3">
                  <div className="text-muted-foreground flex items-center gap-1.5 text-xs">
                    <span className={cn("size-2 shrink-0 rounded-full", meta.dot)} />
                    <span className="truncate">{meta.label}</span>
                  </div>
                  <div
                    className="text-2xl leading-tight font-semibold tabular-nums"
                    style={{ color: meta.color }}
                  >
                    {counts[status]}
                  </div>
                </CardContent>
              </Card>
            );
          })}
        </div>

        <Card className="gap-0 py-3">
          <CardContent className="flex flex-wrap items-center gap-x-4 gap-y-3 px-3">
            <label className="flex cursor-pointer items-center gap-2 text-sm">
              <RefreshCw className="text-muted-foreground size-4" />
              อัปเดตอัตโนมัติ
              <Switch checked={autoRefresh} onCheckedChange={setAutoRefresh} />
            </label>

            {lastUpdated && (
              <span className="text-muted-foreground text-xs">
                ล่าสุด {lastUpdated.toLocaleTimeString("th-TH")}
              </span>
            )}

            <Button
              variant="outline"
              size="sm"
              loading={loading}
              onClick={() => load()}
              className="ml-auto"
            >
              <RefreshCw />
              รีเฟรช
            </Button>

            <div className="flex w-full flex-wrap items-center gap-2 border-t pt-3">
              <span className="text-muted-foreground flex items-center gap-1.5 text-sm">
                <Compass className="size-4" />
                เส้นทางย้อนหลัง:
              </span>
              <ToggleGroup
                type="single"
                value={String(trailHours)}
                onValueChange={(v) => v && setTrailHours(Number(v))}
              >
                <ToggleGroupItem value="0">ไม่แสดง</ToggleGroupItem>
                <ToggleGroupItem value="1">1 ชม.</ToggleGroupItem>
                <ToggleGroupItem value="6">6 ชม.</ToggleGroupItem>
                <ToggleGroupItem value="24">24 ชม.</ToggleGroupItem>
              </ToggleGroup>
              {trailHours > 0 && !selectedId && (
                <span className="text-muted-foreground text-xs">เลือกชื่อพนักงานก่อน</span>
              )}
            </div>
          </CardContent>
        </Card>

        <div className="grid gap-4 lg:grid-cols-3">
          <div className="lg:col-span-2">
            <div className="live-map-frame">
              <MapContainer center={mapCenter} zoom={DEFAULT_ZOOM}>
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
          </div>

          <Card className="gap-0 py-0 lg:max-h-[640px] lg:overflow-hidden">
            <div className="border-b px-4 py-3 text-sm font-semibold">
              พนักงานทั้งหมด ({employees.length})
            </div>
            <div className="max-h-[420px] overflow-y-auto lg:max-h-[560px]">
              {loading && !data ? (
                <div className="space-y-3 p-4">
                  {[0, 1, 2, 3].map((i) => (
                    <Skeleton key={i} className="h-12 w-full" />
                  ))}
                </div>
              ) : employees.length === 0 ? (
                <EmptyState title="ยังไม่มีพนักงานในระบบ" />
              ) : (
                <ul className="divide-border divide-y">
                  {employees.map((person) => {
                    const meta = statusMeta(person.status);
                    const hasPos = person.latitude != null;
                    const isSelected = person.employee_id === selectedId;
                    return (
                      <li key={person.employee_id}>
                        <button
                          type="button"
                          onClick={() => selectPerson(person)}
                          className={cn(
                            "hover:bg-accent/60 flex w-full items-start gap-2.5 px-3 py-2.5 text-left transition-colors",
                            isSelected && "bg-primary/8",
                          )}
                        >
                          <span
                            className={cn("mt-1.5 size-2 shrink-0 rounded-full", meta.dot)}
                          />
                          <span className="min-w-0 flex-1">
                            <span className="flex flex-wrap items-center gap-1.5">
                              <span className="truncate text-sm font-medium">
                                {person.full_name}
                              </span>
                              {person.is_manager && <Badge variant="warning">Boss</Badge>}
                            </span>
                            <span
                              className="block text-xs"
                              style={{ color: meta.color }}
                            >
                              {meta.label} · {formatAge(person.seconds_ago)}
                            </span>
                            {hasPos && (
                              <span className="text-muted-foreground block text-xs">
                                {person.within_geofence
                                  ? `ในเขต ${person.office_name || "ที่ทำงาน"}`
                                  : `นอกเขต ${person.distance_km?.toFixed(1)} กม.`}
                              </span>
                            )}
                          </span>
                          {hasPos && (
                            <Crosshair className="text-muted-foreground mt-1 size-4 shrink-0" />
                          )}
                        </button>
                      </li>
                    );
                  })}
                </ul>
              )}
            </div>
          </Card>
        </div>

        <Alert variant="info">
          <Info />
          <AlertTitle>ตำแหน่งมาจากแอปมือถือของพนักงาน</AlertTitle>
          <AlertDescription>
            แอปจะส่งพิกัดมาเป็นระยะขณะเปิดใช้งาน ถ้าพนักงานปิดแอป ปิด GPS หรือเน็ตหลุด
            ตำแหน่งจะค้างอยู่ที่จุดสุดท้ายและสถานะจะเปลี่ยนเป็น &quot;ขาดการติดต่อ&quot; เอง
          </AlertDescription>
        </Alert>
      </div>
    </AppLayout>
  );
}

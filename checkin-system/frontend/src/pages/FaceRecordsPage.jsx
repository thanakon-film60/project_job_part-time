import React, { useEffect, useRef, useState } from "react";
import {
  Card,
  Row,
  Col,
  Input,
  Button,
  Select,
  Typography,
  Empty,
  Image,
  Spin,
  Alert,
  App,
} from "antd";
import { CameraOutlined } from "@ant-design/icons";
import {
  getEmployee,
  getEmployees,
  getMyFaces,
  getEmployeeFaces,
  enrollFace,
  fetchFacePhoto,
} from "../api";
import AppLayout from "../components/AppLayout.jsx";

const { Text, Title } = Typography;

function FaceThumb({ recordId, note, createdAt }) {
  const [url, setUrl] = useState(null);
  useEffect(() => {
    let alive = true;
    fetchFacePhoto(recordId)
      .then((u) => alive && setUrl(u))
      .catch(() => {});
    return () => {
      alive = false;
    };
  }, [recordId]);

  return (
    <Card
      size="small"
      cover={
        url ? (
          <Image src={url} height={150} style={{ objectFit: "cover" }} />
        ) : (
          <div
            style={{
              height: 150,
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              background: "#f0f0f0",
            }}
          >
            <Spin />
          </div>
        )
      }
    >
      <Text style={{ fontSize: 12 }} type="secondary">
        {new Date(createdAt).toLocaleString("th-TH")}
      </Text>
      {note && (
        <div style={{ fontSize: 12 }}>{note}</div>
      )}
    </Card>
  );
}

export default function FaceRecordsPage() {
  const me = getEmployee();
  const { message } = App.useApp();
  const videoRef = useRef(null);
  const streamRef = useRef(null);
  const [ready, setReady] = useState(false);
  const [camError, setCamError] = useState("");
  const [note, setNote] = useState("");
  const [saving, setSaving] = useState(false);

  const [employees, setEmployees] = useState([]);
  const [viewId, setViewId] = useState(me?.id || null);
  const [records, setRecords] = useState([]);

  useEffect(() => {
    async function start() {
      try {
        const stream = await navigator.mediaDevices.getUserMedia({
          video: { facingMode: "user" },
          audio: false,
        });
        streamRef.current = stream;
        if (videoRef.current) {
          videoRef.current.srcObject = stream;
          setReady(true);
        }
      } catch {
        setCamError(
          "เปิดกล้องไม่ได้ — ต้องรันผ่าน HTTPS และอนุญาตสิทธิ์กล้องของเบราว์เซอร์"
        );
      }
    }
    start();
    return () => streamRef.current?.getTracks().forEach((t) => t.stop());
  }, []);

  useEffect(() => {
    if (me?.is_manager) getEmployees().then(setEmployees).catch(() => {});
  }, []);

  async function loadRecords(id) {
    try {
      const data = me?.is_manager
        ? await getEmployeeFaces(id)
        : await getMyFaces();
      setRecords(data);
    } catch (e) {
      message.error(String(e.message));
    }
  }

  useEffect(() => {
    loadRecords(viewId);
  }, [viewId]);

  async function capture() {
    if (!ready || !videoRef.current) return;
    setSaving(true);
    const v = videoRef.current;
    const canvas = document.createElement("canvas");
    canvas.width = v.videoWidth;
    canvas.height = v.videoHeight;
    canvas.getContext("2d").drawImage(v, 0, 0);
    const blob = await new Promise((res) =>
      canvas.toBlob(res, "image/jpeg", 0.9)
    );
    try {
      await enrollFace(blob, note);
      setNote("");
      message.success("บันทึกใบหน้าเข้าประวัติแล้ว");
      if (!me?.is_manager || viewId === me?.id) loadRecords(me.id);
    } catch (e) {
      message.error(String(e.message));
    } finally {
      setSaving(false);
    }
  }

  return (
    <AppLayout>
      <Title level={4}>ประวัติใบหน้า (บันทึก/ตรวจสอบ)</Title>

      <Card style={{ marginBottom: 16 }}>
        <Row gutter={[16, 16]} align="middle">
          <Col xs={24} md={12}>
            {camError ? (
              <Alert type="warning" message={camError} showIcon />
            ) : (
              <video
                ref={videoRef}
                autoPlay
                playsInline
                muted
                className="mirror-video"
              />
            )}
          </Col>
          <Col xs={24} md={12}>
            <Text>
              บันทึกใบหน้าของ <Text strong>{me?.full_name}</Text> เข้าประวัติ
            </Text>
            <Input
              placeholder="หมายเหตุ (เช่น มุมหน้าตรง / ใส่แว่น)"
              value={note}
              onChange={(e) => setNote(e.target.value)}
              style={{ margin: "12px 0" }}
            />
            <Button
              type="primary"
              icon={<CameraOutlined />}
              onClick={capture}
              loading={saving}
              disabled={!ready}
              block
            >
              ถ่าย &amp; บันทึกใบหน้า
            </Button>
          </Col>
        </Row>
      </Card>

      <Row justify="space-between" align="middle" style={{ marginBottom: 12 }}>
        <Col>
          <Title level={5} style={{ margin: 0 }}>
            รายการที่บันทึกไว้
          </Title>
        </Col>
        {me?.is_manager && (
          <Col>
            <Text type="secondary">ดูของพนักงาน: </Text>
            <Select
              value={viewId}
              style={{ minWidth: 200 }}
              onChange={setViewId}
              options={employees.map((e) => ({
                value: e.id,
                label: `${e.full_name} (${e.employee_code})`,
              }))}
            />
          </Col>
        )}
      </Row>

      {records.length === 0 ? (
        <Empty description="ยังไม่มีข้อมูลใบหน้า" />
      ) : (
        <Row gutter={[12, 12]}>
          {records.map((r) => (
            <Col key={r.id} xs={12} sm={8} md={6} lg={4}>
              <FaceThumb
                recordId={r.id}
                note={r.note}
                createdAt={r.created_at}
              />
            </Col>
          ))}
        </Row>
      )}
    </AppLayout>
  );
}

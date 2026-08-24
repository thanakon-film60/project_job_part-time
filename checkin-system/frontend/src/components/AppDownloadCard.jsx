import React, { useEffect, useState } from "react";
import { Alert, Button, Card, Space, Spin, Tag, Typography, message } from "antd";
import {
  AndroidOutlined,
  DownloadOutlined,
  LinkOutlined,
  MobileOutlined,
} from "@ant-design/icons";
import dayjs from "dayjs";
import utc from "dayjs/plugin/utc";
import { appDownloadUrl, getAppInfo } from "../api";

dayjs.extend(utc);

const { Paragraph, Text, Title } = Typography;

const THAI_OFFSET_MINUTES = 7 * 60;

function prettySize(bytes) {
  if (!bytes) return "";
  const mb = bytes / (1024 * 1024);
  return `${mb.toFixed(1)} MB`;
}

/** การ์ดดาวน์โหลดแอป Flutter — โชว์บนหน้าแรกของพนักงาน
 *
 *  ข้อมูลไฟล์มาจาก GET /app/info (backend อ่านจาก storage/app)
 *  ถ้ายังไม่เคย build APK จะขึ้นข้อความบอกว่ายังไม่มีไฟล์ แทนที่จะโชว์ปุ่มเสีย ๆ
 */
export default function AppDownloadCard() {
  const [info, setInfo] = useState(null);
  const [loading, setLoading] = useState(true);
  const url = appDownloadUrl();

  useEffect(() => {
    let alive = true;
    getAppInfo()
      .then((data) => alive && setInfo(data))
      .catch(() => alive && setInfo({ available: false }))
      .finally(() => alive && setLoading(false));
    return () => {
      alive = false;
    };
  }, []);

  async function copyLink() {
    try {
      await navigator.clipboard.writeText(url);
      message.success("คัดลอกลิงก์แล้ว — เปิดลิงก์นี้ในมือถือเพื่อโหลดแอป");
    } catch {
      message.info(url);
    }
  }

  return (
    <Card bordered={false} className="app-download-card">
      <div className="app-download-head">
        <img src="/logo-checkin.png" alt="" aria-hidden="true" className="app-download-logo" />
        <div>
          <Title level={4} style={{ marginBottom: 2 }}>
            <MobileOutlined /> แอปเช็คอิน THANAKON-ROOM
          </Title>
          <Text type="secondary">
            ใช้เช็คอินด้วย GPS + สแกนใบหน้า จากมือถือได้โดยตรง
          </Text>
        </div>
      </div>

      {loading ? (
        <Spin />
      ) : !info?.available ? (
        <Alert
          type="warning"
          showIcon
          message="ยังไม่มีไฟล์ติดตั้งบนเซิร์ฟเวอร์"
          description="ผู้ดูแลระบบต้อง build แอปก่อน (deploy\windows-server\build-flutter-apk.ps1) แล้วปุ่มดาวน์โหลดจะขึ้นเอง"
        />
      ) : (
        <>
          <Space wrap size={[8, 8]} className="app-download-meta">
            <Tag color="green" icon={<AndroidOutlined />}>Android</Tag>
            {info.version && <Tag>เวอร์ชัน {info.version}</Tag>}
            {info.size_bytes ? <Tag>{prettySize(info.size_bytes)}</Tag> : null}
            {info.built_at && (
              <Tag>
                อัปเดต{" "}
                {dayjs(info.built_at)
                  .utcOffset(THAI_OFFSET_MINUTES)
                  .format("D MMM YYYY HH:mm")}
              </Tag>
            )}
          </Space>

          <Space wrap size={[8, 8]} className="app-download-actions">
            {/* ต้องเป็น <a> จริง ไม่ใช่ fetch — Android ถึงจะเปิดตัวติดตั้งให้ */}
            <Button
              type="primary"
              size="large"
              icon={<DownloadOutlined />}
              href={url}
              download
            >
              ดาวน์โหลดแอป (.apk)
            </Button>
            <Button icon={<LinkOutlined />} onClick={copyLink}>
              คัดลอกลิงก์
            </Button>
          </Space>

          <Paragraph type="secondary" className="app-download-steps">
            วิธีติดตั้งบน Android: เปิดลิงก์นี้จากมือถือ → กดดาวน์โหลด → เปิดไฟล์ที่โหลดมา
            → ถ้าขึ้นเตือน ให้กด “ตั้งค่า” แล้วอนุญาต “ติดตั้งแอปที่ไม่รู้จัก” ให้เบราว์เซอร์
            → กดติดตั้ง แล้วเข้าสู่ระบบด้วยบัญชีเดียวกับเว็บ
            <br />
            iPhone ยังไม่มีไฟล์ติดตั้ง ให้ใช้เว็บนี้แทน (กดแชร์ → “เพิ่มไปยังหน้าจอโฮม”)
          </Paragraph>
        </>
      )}
    </Card>
  );
}

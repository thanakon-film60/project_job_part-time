import React, { useEffect, useRef, useState } from "react";
import { toast } from "sonner";
import { Camera, TriangleAlert } from "lucide-react";
import {
  getEmployee,
  getEmployees,
  getMyFaces,
  getEmployeeFaces,
  enrollFace,
  fetchFacePhoto,
} from "../api";
import AppLayout from "../components/AppLayout.jsx";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { EmptyState } from "@/components/ui/empty-state";
import { ImagePreview } from "@/components/ui/image-preview";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { thaiDateTime } from "@/lib/attendance";

function FaceThumb({ recordId, note, createdAt }) {
  const [url, setUrl] = useState(null);

  useEffect(() => {
    let alive = true;
    let objectUrl = "";
    fetchFacePhoto(recordId)
      .then((u) => {
        objectUrl = u;
        if (alive) setUrl(u);
        else URL.revokeObjectURL(u);
      })
      .catch(() => {});
    return () => {
      alive = false;
      if (objectUrl) URL.revokeObjectURL(objectUrl);
    };
  }, [recordId]);

  return (
    <Card className="gap-0 overflow-hidden py-0">
      {url ? (
        <ImagePreview
          src={url}
          alt={note || "รูปใบหน้าที่บันทึกไว้"}
          wrapperClassName="aspect-square rounded-none"
          className="size-full"
        />
      ) : (
        <Skeleton className="aspect-square rounded-none" />
      )}
      <div className="space-y-0.5 p-2">
        <p className="text-muted-foreground text-[11px]">
          {thaiDateTime(createdAt)}
        </p>
        {note && <p className="truncate text-xs">{note}</p>}
      </div>
    </Card>
  );
}

export default function FaceRecordsPage() {
  const me = getEmployee();
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
          "เปิดกล้องไม่ได้ — ต้องรันผ่าน HTTPS และอนุญาตสิทธิ์กล้องของเบราว์เซอร์",
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
      const data = me?.is_manager ? await getEmployeeFaces(id) : await getMyFaces();
      setRecords(data);
    } catch (e) {
      toast.error(String(e.message));
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
    const blob = await new Promise((res) => canvas.toBlob(res, "image/jpeg", 0.9));
    try {
      await enrollFace(blob, note);
      setNote("");
      toast.success("บันทึกใบหน้าเข้าประวัติแล้ว");
      if (!me?.is_manager || viewId === me?.id) loadRecords(me.id);
    } catch (e) {
      toast.error(String(e.message));
    } finally {
      setSaving(false);
    }
  }

  return (
    <AppLayout>
      <div className="space-y-4">
        <div className="hidden lg:block">
          <h2 className="text-2xl font-bold">ประวัติใบหน้า</h2>
          <p className="text-muted-foreground text-sm">บันทึกและตรวจสอบรูปยืนยันตัวตน</p>
        </div>

        <Card>
          <CardContent className="grid gap-4 md:grid-cols-2 md:items-center md:gap-6">
            {camError ? (
              <Alert variant="warning">
                <TriangleAlert />
                <AlertTitle>เปิดกล้องไม่ได้</AlertTitle>
                <AlertDescription>{camError}</AlertDescription>
              </Alert>
            ) : (
              <video ref={videoRef} autoPlay playsInline muted className="mirror-video" />
            )}

            <div className="space-y-3">
              <p className="text-sm">
                บันทึกใบหน้าของ <strong>{me?.full_name}</strong> เข้าประวัติ
              </p>
              <div className="space-y-2">
                <Label htmlFor="face-note">หมายเหตุ</Label>
                <Input
                  id="face-note"
                  placeholder="เช่น มุมหน้าตรง / ใส่แว่น"
                  value={note}
                  onChange={(e) => setNote(e.target.value)}
                />
              </div>
              <Button
                size="lg"
                className="w-full"
                onClick={capture}
                loading={saving}
                disabled={!ready}
              >
                <Camera />
                ถ่าย &amp; บันทึกใบหน้า
              </Button>
            </div>
          </CardContent>
        </Card>

        <div className="flex flex-wrap items-center justify-between gap-3">
          <h3 className="text-base font-semibold">รายการที่บันทึกไว้</h3>
          {me?.is_manager && (
            <div className="flex min-w-0 items-center gap-2">
              <span className="text-muted-foreground shrink-0 text-sm">ดูของพนักงาน:</span>
              <Select
                value={viewId != null ? String(viewId) : undefined}
                onValueChange={(v) => setViewId(Number(v))}
              >
                <SelectTrigger className="w-[min(60vw,240px)]">
                  <SelectValue placeholder="เลือกพนักงาน" />
                </SelectTrigger>
                <SelectContent>
                  {employees.map((e) => (
                    <SelectItem key={e.id} value={String(e.id)}>
                      {e.full_name} ({e.employee_code})
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          )}
        </div>

        {records.length === 0 ? (
          <Card>
            <CardContent>
              <EmptyState title="ยังไม่มีข้อมูลใบหน้า" description="กดถ่ายรูปด้านบนเพื่อเริ่มบันทึก" />
            </CardContent>
          </Card>
        ) : (
          <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-6">
            {records.map((r) => (
              <FaceThumb key={r.id} recordId={r.id} note={r.note} createdAt={r.created_at} />
            ))}
          </div>
        )}
      </div>
    </AppLayout>
  );
}

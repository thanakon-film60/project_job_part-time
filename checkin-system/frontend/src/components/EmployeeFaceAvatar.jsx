import React, { useEffect, useState } from "react";
import { User } from "lucide-react";
import { fetchFacePhoto, getMyFaces } from "@/api";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { cn } from "@/lib/utils";

export default function EmployeeFaceAvatar({ faceRecordId, className, fallback, currentUser = false }) {
  const [src, setSrc] = useState("");

  useEffect(() => {
    let active = true;
    let objectUrl = "";
    async function load() {
      try {
        let recordId = faceRecordId;
        if (currentUser) {
          const records = await getMyFaces();
          recordId = records?.[0]?.id;
        }
        if (!recordId) return;
        objectUrl = await fetchFacePhoto(recordId);
        if (active) setSrc(objectUrl);
      } catch {
        // บัญชีเก่าที่ยังไม่มีรูปยังใช้งานได้ และจะแสดง fallback แทน
      }
    }
    load();
    return () => {
      active = false;
      if (objectUrl) URL.revokeObjectURL(objectUrl);
    };
  }, [currentUser, faceRecordId]);

  return (
    <Avatar className={cn("size-10", className)}>
      {src && <AvatarImage src={src} alt="รูปพนักงาน" />}
      <AvatarFallback>{fallback || <User className="size-4" />}</AvatarFallback>
    </Avatar>
  );
}

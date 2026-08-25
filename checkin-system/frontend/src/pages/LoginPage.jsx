import React, { useState } from "react";
import { useNavigate, useLocation } from "react-router-dom";
import { CircleAlert, Lock, User } from "lucide-react";
import { login } from "../api";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { PasswordInput } from "@/components/ui/password-input";

export default function LoginPage() {
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);
  const nav = useNavigate();
  const loc = useLocation();
  const from = loc.state?.from || "/";
  const expired = new URLSearchParams(loc.search).get("expired") === "1";

  async function onSubmit(event) {
    event.preventDefault();
    const data = new FormData(event.currentTarget);
    const username = String(data.get("username") || "").trim();
    const password = String(data.get("password") || "");
    if (!username || !password) {
      setError("กรอกรหัสพนักงาน/อีเมล และรหัสผ่านให้ครบ");
      return;
    }

    setError("");
    setLoading(true);
    try {
      await login(username, password);
      nav(from, { replace: true });
    } catch {
      setError("รหัสพนักงาน/อีเมล หรือรหัสผ่านไม่ถูกต้อง");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="from-primary/10 via-background to-background flex min-h-svh items-center justify-center bg-gradient-to-b px-4 py-8">
      <Card className="w-full max-w-md shadow-lg">
        <CardContent className="space-y-5">
          <div className="flex flex-col items-center text-center">
            <img
              src="/logo-checkin.svg"
              alt="THANAKON-ROOM"
              className="mb-3 size-16 object-contain sm:size-20"
            />
            <h1 className="text-xl font-bold sm:text-2xl">THANAKON-ROOM เช็คอิน</h1>
            <p className="text-muted-foreground mt-1 text-sm">
              เข้าสู่ระบบเพื่อดูปฏิทินและจัดการประวัติใบหน้า
            </p>
          </div>

          {(error || expired) && (
            <Alert variant="destructive">
              <CircleAlert />
              <AlertDescription className="text-foreground">
                {error || "เซสชันหมดอายุ กรุณาเข้าสู่ระบบใหม่"}
              </AlertDescription>
            </Alert>
          )}

          <form onSubmit={onSubmit} className="space-y-4" noValidate>
            <div className="space-y-2">
              <Label htmlFor="username">
                <User className="size-4" />
                รหัสพนักงาน / อีเมล
              </Label>
              <Input
                id="username"
                name="username"
                placeholder="เช่น EMP001"
                autoComplete="username"
                autoCapitalize="none"
                className="h-11 sm:h-11"
              />
            </div>

            <div className="space-y-2">
              <Label htmlFor="password">
                <Lock className="size-4" />
                รหัสผ่าน
              </Label>
              <PasswordInput
                id="password"
                name="password"
                placeholder="รหัสผ่าน"
                autoComplete="current-password"
                className="h-11 sm:h-11"
              />
            </div>

            <Button type="submit" size="lg" className="w-full" loading={loading}>
              เข้าสู่ระบบ
            </Button>
          </form>
        </CardContent>
      </Card>
    </div>
  );
}

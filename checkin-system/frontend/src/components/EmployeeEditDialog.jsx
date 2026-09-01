import React, { useEffect, useMemo, useState } from "react";
import { toast } from "sonner";
import { getEmploymentOptions, getThaiAddresses, updateEmployeeProfile } from "@/api";
import { validateThaiNationalId } from "@/lib/thai-id";
import { Button } from "@/components/ui/button";
import {
  Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";

const initialForm = (employee) => ({
  fullName: employee?.full_name || "",
  birthDate: employee?.birth_date || "",
  nationalId: "",
  phone: employee?.phone || "",
  email: employee?.email || "",
  addressLine: employee?.address_line || "",
  postalCode: employee?.postal_code || "",
  subdistrict: employee?.subdistrict || "",
  district: employee?.district || "",
  province: employee?.province || "",
  department: employee?.department || "",
  position: employee?.position || "",
  startDate: employee?.start_date || "",
});

function Field({ label, children, className = "" }) {
  return <div className={`space-y-1.5 ${className}`}><Label>{label}</Label>{children}</div>;
}

export default function EmployeeEditDialog({ open, onOpenChange, employee, onSaved }) {
  const [form, setForm] = useState(() => initialForm(employee));
  const [options, setOptions] = useState([]);
  const [addresses, setAddresses] = useState([]);
  const [saving, setSaving] = useState(false);
  const [lookupLoading, setLookupLoading] = useState(false);

  useEffect(() => {
    if (open) {
      setForm(initialForm(employee));
      getEmploymentOptions().then(setOptions).catch(() => toast.error("โหลดแผนกและตำแหน่งไม่สำเร็จ"));
    }
  }, [open, employee]);

  useEffect(() => {
    if (!open || !/^\d{5}$/.test(form.postalCode)) {
      setAddresses([]);
      return;
    }
    let active = true;
    setLookupLoading(true);
    const timer = setTimeout(() => {
      getThaiAddresses(form.postalCode)
        .then((rows) => active && setAddresses(rows))
        .catch(() => active && setAddresses([]))
        .finally(() => active && setLookupLoading(false));
    }, 250);
    return () => { active = false; clearTimeout(timer); };
  }, [open, form.postalCode]);

  const departments = useMemo(() => options.filter((item) => item.kind === "department"), [options]);
  const positions = useMemo(() => options.filter((item) => item.kind === "position"), [options]);
  const selectedAddress = addresses.find((item) =>
    item.subdistrict === form.subdistrict && item.district === form.district && item.province === form.province
  );

  const set = (name, value) => setForm((current) => ({ ...current, [name]: value }));

  async function save(event) {
    event.preventDefault();
    const required = ["fullName", "birthDate", "phone", "email", "addressLine", "postalCode", "subdistrict", "district", "province", "department", "position", "startDate"];
    if (!employee.national_id_masked) required.push("nationalId");
    if (required.some((name) => !String(form[name] || "").trim())) {
      toast.error("กรุณากรอกข้อมูลพนักงานให้ครบทุกช่อง");
      return;
    }
    if (!/^0\d{8,9}$/.test(form.phone)) {
      toast.error("เบอร์โทรต้องขึ้นต้นด้วย 0 และมี 9–10 หลัก");
      return;
    }
    if (form.nationalId) {
      const result = validateThaiNationalId(form.nationalId);
      if (!result.valid) { toast.error(result.message); return; }
    }
    setSaving(true);
    try {
      const payload = { ...form };
      if (!payload.nationalId) delete payload.nationalId;
      const updated = await updateEmployeeProfile(employee.id, payload);
      toast.success("บันทึกข้อมูลพนักงานแล้ว");
      onSaved(updated);
      onOpenChange(false);
    } catch (error) {
      toast.error(error.message || "แก้ไขข้อมูลไม่สำเร็จ");
    } finally {
      setSaving(false);
    }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-h-[90svh] overflow-y-auto sm:max-w-3xl">
        <DialogHeader>
          <DialogTitle>แก้ไขข้อมูล {employee?.employee_code}</DialogTitle>
          <DialogDescription>การแก้ไขจะถูกบันทึกลง Timeline แฟ้มพนักงาน เลขบัตรประชาชนเดิมจะไม่ถูกเปิดเผย</DialogDescription>
        </DialogHeader>
        <form onSubmit={save} className="space-y-5">
          <div className="grid gap-4 sm:grid-cols-2">
            <Field label="ชื่อ-นามสกุล"><Input value={form.fullName} onChange={(e) => set("fullName", e.target.value)} /></Field>
            <Field label="วันเกิด"><Input type="date" value={form.birthDate} onChange={(e) => set("birthDate", e.target.value)} /></Field>
            <Field label={employee?.national_id_masked ? "เลขบัตรประชาชนใหม่ (ไม่บังคับ)" : "เลขบัตรประชาชน"}><Input inputMode="numeric" maxLength={13} value={form.nationalId} onChange={(e) => set("nationalId", e.target.value.replace(/\D/g, ""))} placeholder={employee?.national_id_masked ? "เว้นว่างเพื่อใช้เลขเดิม" : "กรอกเลขบัตร 13 หลัก"} /></Field>
            <Field label="เบอร์โทร"><Input type="tel" value={form.phone} onChange={(e) => set("phone", e.target.value)} /></Field>
            <Field label="อีเมล"><Input type="email" value={form.email} onChange={(e) => set("email", e.target.value)} /></Field>
            <Field label="บ้านเลขที่ / ถนน / ซอย"><Input value={form.addressLine} onChange={(e) => set("addressLine", e.target.value)} /></Field>
            <Field label="รหัสไปรษณีย์"><Input inputMode="numeric" maxLength={5} value={form.postalCode} onChange={(e) => { setForm((current) => ({ ...current, postalCode: e.target.value.replace(/\D/g, ""), subdistrict: "", district: "", province: "" })); }} /></Field>
            <Field label="เลือกตำบล / อำเภอ / จังหวัด">
              <Select value={selectedAddress ? String(selectedAddress.id) : undefined} onValueChange={(id) => {
                const row = addresses.find((item) => String(item.id) === id);
                if (row) setForm((current) => ({ ...current, subdistrict: row.subdistrict, district: row.district, province: row.province }));
              }} disabled={lookupLoading || !addresses.length}>
                <SelectTrigger className="w-full"><SelectValue placeholder={lookupLoading ? "กำลังค้นหา..." : "เลือกที่อยู่"} /></SelectTrigger>
                <SelectContent>{addresses.map((row) => <SelectItem key={row.id} value={String(row.id)}>ต.{row.subdistrict} / อ.{row.district} / จ.{row.province}</SelectItem>)}</SelectContent>
              </Select>
            </Field>
            <Field label="ตำบล / แขวง"><Input readOnly value={form.subdistrict} /></Field>
            <Field label="อำเภอ / เขต"><Input readOnly value={form.district} /></Field>
            <Field label="จังหวัด"><Input readOnly value={form.province} /></Field>
            <Field label="แผนก">
              <Select value={form.department || undefined} onValueChange={(value) => set("department", value)}><SelectTrigger className="w-full"><SelectValue placeholder="เลือกแผนก" /></SelectTrigger><SelectContent>{departments.map((item) => <SelectItem key={item.id} value={item.name}>{item.name}</SelectItem>)}</SelectContent></Select>
            </Field>
            <Field label="ตำแหน่ง">
              <Select value={form.position || undefined} onValueChange={(value) => set("position", value)}><SelectTrigger className="w-full"><SelectValue placeholder="เลือกตำแหน่ง" /></SelectTrigger><SelectContent>{positions.map((item) => <SelectItem key={item.id} value={item.name}>{item.name}</SelectItem>)}</SelectContent></Select>
            </Field>
            <Field label="วันเริ่มงาน"><Input type="date" value={form.startDate} onChange={(e) => set("startDate", e.target.value)} /></Field>
          </div>
          <DialogFooter>
            <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>ยกเลิก</Button>
            <Button type="submit" loading={saving}>บันทึกการแก้ไข</Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

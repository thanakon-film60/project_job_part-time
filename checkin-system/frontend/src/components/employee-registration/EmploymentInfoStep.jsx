import React, { useState } from "react";
import { Menu, Plus } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import FormField from "./FormField.jsx";

function OptionSelect({ id, label, value, options, loading, error, onValueChange }) {
  return (
    <FormField id={id} label={label} error={error}>
      <Select value={value || undefined} onValueChange={onValueChange} disabled={loading}>
        <SelectTrigger id={id} className="w-full" aria-invalid={Boolean(error)}>
          <SelectValue placeholder={loading ? "กำลังโหลดตัวเลือก..." : `เลือก${label}`} />
        </SelectTrigger>
        <SelectContent>
          {options.map((option) => (
            <SelectItem key={option.id} value={option.name}>
              {option.name}
            </SelectItem>
          ))}
        </SelectContent>
      </Select>
    </FormField>
  );
}

export default function EmploymentInfoStep({
  data,
  errors,
  touched,
  employmentOptions,
  employmentLoading,
  onChange,
  onBlur,
  onSelect,
  onAddOption,
}) {
  const [managerOpen, setManagerOpen] = useState(false);
  const [newKind, setNewKind] = useState("department");
  const [newName, setNewName] = useState("");
  const [adding, setAdding] = useState(false);

  const departments = employmentOptions.filter((option) => option.kind === "department");
  const positions = employmentOptions.filter((option) => option.kind === "position");

  async function addOption() {
    const name = newName.trim();
    if (!name) {
      toast.error("กรุณากรอกชื่อตัวเลือก");
      return;
    }
    setAdding(true);
    try {
      await onAddOption(newKind, name);
      setNewName("");
      toast.success("เพิ่มตัวเลือกเรียบร้อยแล้ว");
    } catch (error) {
      toast.error(error.message || "เพิ่มตัวเลือกไม่สำเร็จ");
    } finally {
      setAdding(false);
    }
  }

  return (
    <div className="space-y-4">
      <div className="flex justify-end">
        <Button
          type="button"
          variant="outline"
          size="icon"
          aria-label="เปิดเมนูจัดการแผนกและตำแหน่ง"
          title="จัดการแผนกและตำแหน่ง"
          onClick={() => setManagerOpen(true)}
        >
          <Menu />
        </Button>
      </div>

      <div className="grid gap-5 sm:grid-cols-2">
        <OptionSelect
          id="department"
          label="แผนก"
          value={data.department}
          options={departments}
          loading={employmentLoading}
          error={touched.department && errors.department}
          onValueChange={(value) => onSelect("department", value)}
        />
        <OptionSelect
          id="position"
          label="ตำแหน่ง"
          value={data.position}
          options={positions}
          loading={employmentLoading}
          error={touched.position && errors.position}
          onValueChange={(value) => onSelect("position", value)}
        />
        <FormField id="startDate" label="วันเริ่มงาน" error={touched.startDate && errors.startDate}>
          <Input
            id="startDate"
            name="startDate"
            value={data.startDate}
            onChange={onChange}
            onBlur={onBlur}
            type="date"
            aria-invalid={Boolean(touched.startDate && errors.startDate)}
          />
        </FormField>
      </div>

      <Dialog open={managerOpen} onOpenChange={setManagerOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>จัดการแผนกและตำแหน่ง</DialogTitle>
            <DialogDescription>
              รายการที่เพิ่มจะบันทึกในระบบและแสดงใน Dropdown ทันที เฉพาะบัญชี Boss เท่านั้นที่เพิ่มได้
            </DialogDescription>
          </DialogHeader>

          <div className="grid gap-4 sm:grid-cols-[180px_1fr]">
            <FormField id="optionKind" label="ประเภท">
              <Select value={newKind} onValueChange={setNewKind}>
                <SelectTrigger id="optionKind" className="w-full">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="department">แผนก</SelectItem>
                  <SelectItem value="position">ตำแหน่ง</SelectItem>
                </SelectContent>
              </Select>
            </FormField>
            <FormField id="optionName" label="ชื่อตัวเลือก">
              <Input
                id="optionName"
                value={newName}
                onChange={(event) => setNewName(event.target.value)}
                onKeyDown={(event) => {
                  if (event.key === "Enter") {
                    event.preventDefault();
                    addOption();
                  }
                }}
                maxLength={120}
                placeholder={newKind === "department" ? "เช่น ฝ่ายการตลาด" : "เช่น เจ้าหน้าที่การตลาด"}
              />
            </FormField>
          </div>

          <Button type="button" onClick={addOption} loading={adding} className="sm:self-end">
            <Plus /> เพิ่มตัวเลือก
          </Button>
        </DialogContent>
      </Dialog>
    </div>
  );
}

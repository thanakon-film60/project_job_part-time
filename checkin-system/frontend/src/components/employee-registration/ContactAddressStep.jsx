import React from "react";
import { MapPin } from "lucide-react";
import { Input } from "@/components/ui/input";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import FormField from "./FormField.jsx";

export default function ContactAddressStep({
  data,
  errors,
  touched,
  addressOptions,
  addressLoading,
  addressError,
  selectedAddressValue,
  onChange,
  onBlur,
  onAddressSelect,
}) {
  const fieldProps = (name) => ({
    id: name,
    name,
    value: data[name],
    onChange,
    onBlur,
    "aria-invalid": Boolean(touched[name] && errors[name]),
    "aria-describedby": touched[name] && errors[name] ? `${name}-error` : undefined,
  });

  return (
    <div className="space-y-5">
      <div className="grid gap-5 sm:grid-cols-2">
        <FormField id="phone" label="เบอร์โทร" error={touched.phone && errors.phone}>
          <Input {...fieldProps("phone")} type="tel" inputMode="tel" autoComplete="tel" placeholder="08xxxxxxxx" />
        </FormField>
        <FormField id="email" label="อีเมล" error={touched.email && errors.email}>
          <Input {...fieldProps("email")} type="email" autoComplete="email" placeholder="name@example.com" />
        </FormField>
      </div>

      <FormField id="addressLine" label="บ้านเลขที่ / ถนน / ซอย" error={touched.addressLine && errors.addressLine}>
        <Input {...fieldProps("addressLine")} autoComplete="street-address" placeholder="เช่น 99/9 ถนนสุขุมวิท" />
      </FormField>

      <div className="grid items-start gap-5 sm:grid-cols-2">
        <FormField
          id="postalCode"
          label="รหัสไปรษณีย์"
          error={touched.postalCode && errors.postalCode}
          hint="ค้นหาจากฐานข้อมูล 7,452 ตำบลทั่วประเทศไทย"
        >
          <Input
            {...fieldProps("postalCode")}
            inputMode="numeric"
            autoComplete="postal-code"
            maxLength={5}
            placeholder="10110"
          />
        </FormField>

        <FormField
          id="addressChoice"
          label="เลือกตำบล / อำเภอ / จังหวัด"
          error={touched.addressChoice && errors.addressChoice}
        >
          <Select
            value={selectedAddressValue || undefined}
            onValueChange={onAddressSelect}
            disabled={addressLoading || addressOptions.length === 0}
          >
            <SelectTrigger id="addressChoice" className="w-full" aria-invalid={Boolean(touched.addressChoice && errors.addressChoice)}>
              <MapPin className="text-muted-foreground size-4" />
              <SelectValue
                placeholder={
                  addressLoading
                    ? "กำลังค้นหาที่อยู่..."
                    : addressError
                      ? "ค้นหาที่อยู่ไม่สำเร็จ"
                      : data.postalCode.length === 5
                        ? "ไม่พบที่อยู่สำหรับรหัสนี้"
                        : "กรอกรหัสไปรษณีย์ก่อน"
                }
              />
            </SelectTrigger>
            <SelectContent>
              {addressOptions.map((address) => (
                <SelectItem key={address.id} value={String(address.id)}>
                  ต.{address.subdistrict} / อ.{address.district} / จ.{address.province}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </FormField>
      </div>

      <div className="bg-muted/50 grid gap-4 rounded-lg border p-4 sm:grid-cols-3">
        <FormField id="subdistrict" label="ตำบล / แขวง">
          <Input id="subdistrict" value={data.subdistrict} readOnly placeholder="เติมอัตโนมัติ" />
        </FormField>
        <FormField id="district" label="อำเภอ / เขต">
          <Input id="district" value={data.district} readOnly placeholder="เติมอัตโนมัติ" />
        </FormField>
        <FormField id="province" label="จังหวัด">
          <Input id="province" value={data.province} readOnly placeholder="เติมอัตโนมัติ" />
        </FormField>
      </div>
    </div>
  );
}

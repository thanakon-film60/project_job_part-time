import React from "react";
import { Input } from "@/components/ui/input";
import FormField from "./FormField.jsx";

export default function PersonalInfoStep({ data, errors, touched, onChange, onBlur }) {
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
    <div className="grid gap-5 sm:grid-cols-2">
      <FormField id="firstName" label="ชื่อ" error={touched.firstName && errors.firstName}>
        <Input {...fieldProps("firstName")} autoComplete="given-name" placeholder="ชื่อจริง" />
      </FormField>
      <FormField id="lastName" label="นามสกุล" error={touched.lastName && errors.lastName}>
        <Input {...fieldProps("lastName")} autoComplete="family-name" placeholder="นามสกุล" />
      </FormField>
      <FormField id="birthDate" label="วันเกิด" error={touched.birthDate && errors.birthDate}>
        <Input {...fieldProps("birthDate")} type="date" max={new Date().toISOString().slice(0, 10)} />
      </FormField>
      <FormField
        id="nationalId"
        label="เลขบัตรประชาชน"
        error={touched.nationalId && errors.nationalId}
        hint="กรอกตัวเลข 13 หลัก ระบบจะตรวจ Modulo 11 ทันที"
      >
        <Input
          {...fieldProps("nationalId")}
          inputMode="numeric"
          autoComplete="off"
          maxLength={13}
          placeholder="x-xxxx-xxxxx-xx-x"
        />
      </FormField>
    </div>
  );
}


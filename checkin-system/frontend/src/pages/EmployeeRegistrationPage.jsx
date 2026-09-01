import React, { useEffect, useMemo, useState } from "react";
import { ArrowLeft, ArrowRight, Check, CircleCheck, KeyRound, UserPlus } from "lucide-react";
import { Link } from "react-router-dom";
import { toast } from "sonner";
import AppLayout from "@/components/AppLayout.jsx";
import { addEmploymentOption, getEmploymentOptions, getThaiAddresses, registerEmployee } from "@/api";
import ContactAddressStep from "@/components/employee-registration/ContactAddressStep.jsx";
import EmploymentInfoStep from "@/components/employee-registration/EmploymentInfoStep.jsx";
import PersonalInfoStep from "@/components/employee-registration/PersonalInfoStep.jsx";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { buildEmployeePayload, STEP_FIELDS, validateRegistration } from "@/lib/employee-registration";
import { cn } from "@/lib/utils";

const INITIAL_DATA = {
  firstName: "",
  lastName: "",
  birthDate: "",
  nationalId: "",
  phone: "",
  email: "",
  addressLine: "",
  postalCode: "",
  subdistrict: "",
  district: "",
  province: "",
  department: "",
  position: "",
  startDate: "",
};

const STEPS = [
  { title: "ข้อมูลส่วนตัว", short: "ส่วนตัว" },
  { title: "การติดต่อและที่อยู่", short: "ที่อยู่" },
  { title: "ข้อมูลการทำงาน", short: "การทำงาน" },
];

function StepProgress({ current }) {
  return (
    <ol className="grid grid-cols-3" aria-label="ขั้นตอนการลงทะเบียน">
      {STEPS.map((item, index) => {
        const done = index < current;
        const active = index === current;
        return (
          <li key={item.title} className="relative flex flex-col items-center gap-2 text-center">
            {index > 0 && (
              <span className={cn("absolute top-4 right-1/2 h-0.5 w-full", index <= current ? "bg-primary" : "bg-border")} />
            )}
            <span
              className={cn(
                "relative z-10 flex size-8 items-center justify-center rounded-full border text-sm font-semibold",
                done || active ? "border-primary bg-primary text-primary-foreground" : "border-border bg-card text-muted-foreground",
              )}
              aria-current={active ? "step" : undefined}
            >
              {done ? <Check className="size-4" /> : index + 1}
            </span>
            <span className={cn("text-xs sm:text-sm", active ? "font-semibold text-foreground" : "text-muted-foreground")}>
              <span className="sm:hidden">{item.short}</span>
              <span className="hidden sm:inline">{item.title}</span>
            </span>
          </li>
        );
      })}
    </ol>
  );
}

export default function EmployeeRegistrationPage() {
  const [step, setStep] = useState(0);
  const [data, setData] = useState(INITIAL_DATA);
  const [touched, setTouched] = useState({});
  const [submitting, setSubmitting] = useState(false);
  const [registrationResult, setRegistrationResult] = useState(null);
  const [addressOptions, setAddressOptions] = useState([]);
  const [addressLoading, setAddressLoading] = useState(false);
  const [addressError, setAddressError] = useState("");
  const [employmentOptions, setEmploymentOptions] = useState([]);
  const [employmentLoading, setEmploymentLoading] = useState(true);
  const addressLookupStatus = addressLoading
    ? "loading"
    : addressError
      ? "error"
      : /^\d{5}$/.test(data.postalCode)
        ? "success"
        : "idle";

  useEffect(() => {
    let active = true;
    setAddressOptions([]);
    setAddressError("");
    if (!/^\d{5}$/.test(data.postalCode)) {
      setAddressLoading(false);
      return () => {
        active = false;
      };
    }

    setAddressLoading(true);
    getThaiAddresses(data.postalCode)
      .then((rows) => active && setAddressOptions(rows))
      .catch((error) => active && setAddressError(error.message || "ค้นหาที่อยู่ไม่สำเร็จ"))
      .finally(() => active && setAddressLoading(false));

    return () => {
      active = false;
    };
  }, [data.postalCode]);

  useEffect(() => {
    let active = true;
    getEmploymentOptions()
      .then((options) => active && setEmploymentOptions(options))
      .catch((error) => active && toast.error(error.message || "โหลดแผนกและตำแหน่งไม่สำเร็จ"))
      .finally(() => active && setEmploymentLoading(false));
    return () => {
      active = false;
    };
  }, []);

  const errors = useMemo(
    () => validateRegistration(data, addressOptions, addressLookupStatus),
    [data, addressOptions, addressLookupStatus],
  );
  const selectedAddressValue = String(
    addressOptions.find(
      (item) =>
        item.subdistrict === data.subdistrict &&
        item.district === data.district &&
        item.province === data.province,
    )?.id ?? "",
  );

  function handleChange(event) {
    const { name } = event.target;
    let value = event.target.value;
    if (["nationalId", "phone", "postalCode"].includes(name)) {
      value = value.replace(/\D/g, "");
    }

    setData((current) => ({
      ...current,
      [name]: value,
      ...(name === "postalCode"
        ? { subdistrict: "", district: "", province: "" }
        : {}),
    }));

    // เลขบัตรต้องแจ้งผลทันทีตั้งแต่เริ่มกรอก
    if (name === "nationalId") {
      setTouched((current) => ({ ...current, nationalId: true }));
    }
  }

  function handleBlur(event) {
    setTouched((current) => ({ ...current, [event.target.name]: true }));
  }

  function handleAddressSelect(value) {
    const selected = addressOptions.find((item) => String(item.id) === value);
    if (!selected) return;
    setData((current) => ({
      ...current,
      subdistrict: selected.subdistrict,
      district: selected.district,
      province: selected.province,
    }));
    setTouched((current) => ({ ...current, addressChoice: true, postalCode: true }));
  }

  function handleEmploymentSelect(name, value) {
    setData((current) => ({ ...current, [name]: value }));
    setTouched((current) => ({ ...current, [name]: true }));
  }

  async function handleAddEmploymentOption(kind, name) {
    const created = await addEmploymentOption(kind, name);
    setEmploymentOptions((current) => [...current, created]);
    handleEmploymentSelect(kind, created.name);
    return created;
  }

  function validateCurrentStep() {
    const fields = STEP_FIELDS[step];
    setTouched((current) => ({
      ...current,
      ...Object.fromEntries(fields.map((field) => [field, true])),
    }));
    return fields.every((field) => !errors[field]);
  }

  function nextStep() {
    if (step === 1 && addressLoading) {
      toast.info("กรุณารอระบบค้นหาที่อยู่สักครู่");
      return;
    }
    if (!validateCurrentStep()) {
      toast.error("กรุณาตรวจสอบข้อมูลในขั้นตอนนี้");
      return;
    }
    setStep((current) => current + 1);
  }

  async function submit(event) {
    event.preventDefault();
    if (!validateCurrentStep()) {
      toast.error("กรุณาตรวจสอบข้อมูลก่อนส่ง");
      return;
    }

    const payload = buildEmployeePayload(data);
    setSubmitting(true);
    try {
      const result = await registerEmployee(payload);
      setRegistrationResult(result);
      toast.success("ลงทะเบียนและสร้างบัญชีพนักงานสำเร็จ");
    } catch (error) {
      toast.error(error.message || "ลงทะเบียนพนักงานไม่สำเร็จ");
    } finally {
      setSubmitting(false);
    }
  }

  const commonStepProps = { data, errors, touched, onChange: handleChange, onBlur: handleBlur };

  return (
    <AppLayout>
      <div className="mx-auto max-w-4xl space-y-4">
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div>
            <h2 className="text-2xl font-bold">ลงทะเบียนพนักงาน</h2>
            <p className="text-muted-foreground text-sm">กรอกข้อมูลให้ครบทั้ง 3 ขั้นตอน ระบบจะตรวจสอบก่อนส่งข้อมูล</p>
          </div>
          <Button variant="outline" asChild>
            <Link to="/employees"><ArrowLeft /> กลับหน้าพนักงาน</Link>
          </Button>
        </div>

        <Card>
          <CardHeader className="border-b">
            <StepProgress current={step} />
          </CardHeader>
          <form onSubmit={submit} noValidate>
            <CardHeader>
              <CardTitle className="flex items-center gap-2">
                <UserPlus className="text-primary size-5" />
                Step {step + 1}: {STEPS[step].title}
              </CardTitle>
              <CardDescription>ข้อมูลที่กรอกจะยังอยู่เมื่อกดย้อนกลับไปยังขั้นตอนก่อนหน้า</CardDescription>
            </CardHeader>
            <CardContent>
              {step === 0 && <PersonalInfoStep {...commonStepProps} />}
              {step === 1 && (
                <ContactAddressStep
                  {...commonStepProps}
                  addressOptions={addressOptions}
                  addressLoading={addressLoading}
                  addressError={addressError}
                  selectedAddressValue={selectedAddressValue}
                  onAddressSelect={handleAddressSelect}
                />
              )}
              {step === 2 && (
                <EmploymentInfoStep
                  {...commonStepProps}
                  employmentOptions={employmentOptions}
                  employmentLoading={employmentLoading}
                  onSelect={handleEmploymentSelect}
                  onAddOption={handleAddEmploymentOption}
                />
              )}
            </CardContent>
            <div className="mt-6 flex items-center justify-between border-t px-4 pt-5 sm:px-6">
              <Button type="button" variant="outline" onClick={() => setStep((current) => current - 1)} disabled={step === 0}>
                <ArrowLeft /> ย้อนกลับ
              </Button>
              {step < STEPS.length - 1 ? (
                <Button type="button" onClick={nextStep}>ถัดไป <ArrowRight /></Button>
              ) : (
                <Button type="submit" loading={submitting}><CircleCheck /> ยืนยันและส่งข้อมูล</Button>
              )}
            </div>
          </form>
        </Card>

        {registrationResult && (
          <Card className="border-success/40">
            <CardHeader>
              <CardTitle className="text-success flex items-center gap-2"><CircleCheck /> ลงทะเบียนพนักงานสำเร็จ</CardTitle>
              <CardDescription>รหัสผ่านนี้แสดงครั้งเดียว กรุณาส่งให้พนักงานผ่านช่องทางที่ปลอดภัย</CardDescription>
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="bg-muted grid gap-3 rounded-lg p-4 sm:grid-cols-2">
                <div>
                  <p className="text-muted-foreground text-xs">รหัสพนักงาน</p>
                  <p className="font-mono text-lg font-semibold">{registrationResult.employee.employee_code}</p>
                </div>
                <div>
                  <p className="text-muted-foreground text-xs">รหัสผ่านชั่วคราว</p>
                  <p className="flex items-center gap-2 font-mono text-lg font-semibold"><KeyRound className="size-4" />{registrationResult.temporary_password}</p>
                </div>
              </div>
              <Button asChild>
                <Link to={`/employees/${registrationResult.employee.id}/history`}>เปิดแฟ้มประวัติพนักงาน</Link>
              </Button>
            </CardContent>
          </Card>
        )}
      </div>
    </AppLayout>
  );
}

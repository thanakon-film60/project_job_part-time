# เปิด firewall เฉพาะพอร์ตเว็บ (80/443) สำหรับให้เข้าจากอินเทอร์เน็ต
# รันแบบ Administrator
# หมายเหตุ: ไม่ต้องเปิดพอร์ต 8000 และ 5432 ออกสู่ภายนอก
#   - 8000 (uvicorn) ให้ IIS คุยผ่าน 127.0.0.1 เท่านั้น
#   - 5432 (PostgreSQL) ให้ backend คุยผ่าน 127.0.0.1 เท่านั้น

New-NetFirewallRule -DisplayName "HTTP 80"  -Direction Inbound -Protocol TCP -LocalPort 80  -Action Allow -ErrorAction SilentlyContinue
New-NetFirewallRule -DisplayName "HTTPS 443" -Direction Inbound -Protocol TCP -LocalPort 443 -Action Allow -ErrorAction SilentlyContinue

Write-Host "เปิดพอร์ต 80/443 แล้ว" -ForegroundColor Green
Write-Host "อย่าลืม forward พอร์ต 80/443 ที่ router มายัง IP ของ Windows Server ด้วย"

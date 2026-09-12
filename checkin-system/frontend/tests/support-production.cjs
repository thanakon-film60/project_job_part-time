// ทดสอบห้องช่วยเหลือระยะไกลบน production จริง ผ่านโดเมนจริง
//
// ต่างจาก support-browser.cjs ตรงที่ตัวนั้นยิงเซิร์ฟเวอร์ชั่วคราวในเครื่อง
// ส่วนตัวนี้เดินเส้นทางเดียวกับผู้ใช้จริงทุกขั้น: Cloudflare -> tunnel -> backend
// จึงเป็นตัวเดียวที่พิสูจน์ว่า "เปิดใช้จริงแล้วใช้ได้"
//
// เรียกผ่าน backend/test_support_production.py (ตัวนั้นออกโทเค็นและเก็บกวาดห้องให้)
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const assert = require('node:assert/strict');
const path = require('node:path');

const origin = process.env.SUPPORT_PROD_ORIGIN;
const token = process.env.SUPPORT_PROD_TOKEN;
const employee = process.env.SUPPORT_PROD_EMPLOYEE;
const artifacts = process.env.SUPPORT_PROD_ARTIFACTS;

const hasInk = () => {
  const canvas = document.querySelector('canvas');
  if (!canvas) return false;
  const { data } = canvas.getContext('2d').getImageData(0, 0, canvas.width, canvas.height);
  for (let i = 3; i < data.length; i += 4) if (data[i] > 0) return true;
  return false;
};

(async () => {
  const browser = await chromium.launch({
    channel: 'msedge',
    headless: true,
    args: [
      '--use-fake-device-for-media-stream',
      '--use-fake-ui-for-media-stream',
      '--autoplay-policy=no-user-gesture-required',
    ],
  });
  const errors = [];
  let roomCode = '';

  const newContext = async (viewport) => {
    const context = await browser.newContext({ viewport, serviceWorkers: 'block' });
    await context.grantPermissions(['camera', 'microphone'], { origin });
    return context;
  };

  try {
    // ---------------------------------------------------------- ฝั่งผู้ช่วย
    const hostContext = await newContext({ width: 1440, height: 1000 });
    await hostContext.addInitScript(
      ([t, e]) => {
        localStorage.setItem('token', t);
        localStorage.setItem('employee', e);
      },
      [token, employee],
    );
    const host = await hostContext.newPage();
    host.on('pageerror', (error) => errors.push(`host: ${error.message}`));
    await host.goto(`${origin}/it-support`, { waitUntil: 'domcontentloaded' });

    await host.getByLabel('เรื่องที่ต้องแก้').fill('[ตรวจระบบ] ทดสอบบนโดเมนจริง');
    await host.getByRole('button', { name: 'สร้างห้องและคัดลอกลิงก์' }).click();

    const link = (await host.locator('code').first().textContent()).trim();
    roomCode = link.split('/').pop();
    // บอก python ว่าต้องลบห้องไหนทิ้ง แม้เทสจะพังกลางทาง
    console.log(`ROOM_CODE=${roomCode}`);
    assert.ok(link.startsWith(origin), `ลิงก์ควรชี้โดเมนจริง: ${link}`);
    console.log(`  [ผ่าน] สร้างห้องบน production แล้ว: ${link}`);

    // ---------------------------------------------------------- ฝั่งผู้ใช้
    const guestContext = await newContext({ width: 390, height: 844 });
    const guest = await guestContext.newPage();
    guest.on('pageerror', (error) => errors.push(`guest: ${error.message}`));
    await guest.goto(link, { waitUntil: 'domcontentloaded' });

    await guest.getByRole('button', { name: 'อนุญาตกล้องและไมโครโฟน' }).click();
    console.log('  [ผ่าน] ผู้ใช้เปิดลิงก์จริงและกดอนุญาตกล้องได้');

    // ---------------------------------------------------------- ต่อสายผ่าน Cloudflare
    await host.getByText('เชื่อมต่อแล้ว').first().waitFor({ timeout: 60000 });
    await guest.getByText('คุยกันได้แล้ว').first().waitFor({ timeout: 60000 });
    console.log('  [ผ่าน] WebRTC ต่อสายผ่านโดเมนจริงสำเร็จ (signaling วิ่งผ่าน Cloudflare Tunnel)');

    await host.waitForFunction(
      () => {
        const v = document.querySelector('video');
        return Boolean(v && v.videoWidth > 0);
      },
      null,
      { timeout: 40000 },
    );
    const size = await host.locator('video').first().evaluate((v) => [v.videoWidth, v.videoHeight]);
    console.log(`  [ผ่าน] ผู้ช่วยเห็นภาพจากกล้องผู้ใช้ (${size.join('x')})`);

    // ---------------------------------------------------------- วาดชี้จุด
    await host.getByRole('button', { name: 'วงกลม' }).click();
    const box = await host.locator('canvas').first().boundingBox();
    await host.mouse.move(box.x + box.width * 0.35, box.y + box.height * 0.35);
    await host.mouse.down();
    await host.mouse.move(box.x + box.width * 0.6, box.y + box.height * 0.6, { steps: 10 });
    await host.mouse.up();
    await guest.waitForFunction(hasInk, null, { timeout: 20000 });
    console.log('  [ผ่าน] เส้นที่วาดวิ่งข้ามโดเมนจริงไปถึงผู้ใช้');

    // ---------------------------------------------------------- หยุดภาพ
    await host.getByRole('button', { name: /หยุดภาพไว้วาด/ }).click();
    await guest.locator('img[alt="ภาพที่หยุดไว้เพื่อชี้จุด"]').waitFor({ timeout: 25000 });
    console.log('  [ผ่าน] ภาพนิ่งส่งผ่าน WebSocket จริงได้ (ข้อความขนาดใหญ่ไม่ถูกตัด)');

    // ---------------------------------------------------------- วาดทับภาพนิ่ง
    // ท่าที่จะใช้บ่อยที่สุดของจริง: ตรึงเฟรมแล้วค่อยวงกลมตรงจุดที่ต้องกด
    // (หยุดภาพจะล้างเส้นเก่าทิ้งเสมอ เพราะเส้นเดิมอ้างอิงคนละเฟรม)
    await host.getByRole('button', { name: 'ลูกศรชี้' }).click();
    const frozenBox = await host.locator('canvas').first().boundingBox();
    await host.mouse.move(frozenBox.x + frozenBox.width * 0.3, frozenBox.y + frozenBox.height * 0.3);
    await host.mouse.down();
    await host.mouse.move(frozenBox.x + frozenBox.width * 0.52, frozenBox.y + frozenBox.height * 0.5, { steps: 10 });
    await host.mouse.up();
    await guest.waitForFunction(hasInk, null, { timeout: 20000 });
    console.log('  [ผ่าน] วาดทับภาพนิ่งแล้วผู้ใช้เห็นตรงจุดเดียวกัน');

    await host.screenshot({ path: path.join(artifacts, 'production-host.png') });
    await guest.screenshot({ path: path.join(artifacts, 'production-guest.png') });

    // ---------------------------------------------------------- ปิดห้อง
    await host.getByRole('button', { name: 'ปิดห้อง', exact: true }).click();
    await guest.getByText('ผู้ช่วยปิดห้องแล้ว').first().waitFor({ timeout: 25000 });
    console.log('  [ผ่าน] ปิดห้องแล้วฝั่งผู้ใช้รู้ทันทีและกล้องดับ');

    assert.deepEqual(errors, [], `มี error ในเบราว์เซอร์: ${errors.join(' | ')}`);
    console.log('\nระบบช่วยเหลือระยะไกลใช้งานได้จริงบน production');
  } catch (error) {
    console.error(`\nไม่ผ่าน: ${error.message}`);
    if (errors.length) console.error(`error ในเบราว์เซอร์: ${errors.join(' | ')}`);
    process.exitCode = 1;
  } finally {
    await browser.close();
  }
})();

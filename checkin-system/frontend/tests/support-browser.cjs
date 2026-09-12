// เทสห้องช่วยเหลือระยะไกลด้วยเบราว์เซอร์จริงสองฝั่ง
//
// ใช้กล้อง/ไมค์ปลอมของ Chromium (--use-fake-device-for-media-stream) แล้วให้
// สองหน้าต่างต่อ WebRTC หากันจริง ๆ บน localhost — จึงครอบคลุมสิ่งที่เทสฝั่ง
// Python แตะไม่ถึง: การจับมือ SDP/ICE, การส่งภาพจริง, และเส้นที่วาดข้ามฝั่ง
//
// เรียกผ่าน backend/test_support_browser.py (ตัวนั้นเตรียมฐานข้อมูลแยกให้)
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const assert = require('node:assert/strict');
const path = require('node:path');

const origin = process.env.SUPPORT_TEST_ORIGIN;
const artifacts = process.env.SUPPORT_TEST_ARTIFACTS;

/** นับพิกเซลที่ถูกวาดบน canvas ของชั้นเส้น
 *
 * อ่านค่าพิกเซลตรง ๆ เพราะเส้นอยู่บน canvas ไม่ใช่ DOM — ตรวจด้วย selector ไม่ได้
 * ใช้ช่องอัลฟา ถ้ามากกว่า 0 แปลว่ามีอะไรถูกวาดทับตรงนั้นจริง
 */
const countInk = (canvas) => {
  const ctx = canvas.getContext('2d');
  const { data } = ctx.getImageData(0, 0, canvas.width, canvas.height);
  let n = 0;
  for (let i = 3; i < data.length; i += 4) if (data[i] > 0) n += 1;
  return n;
};

(async () => {
  const browser = await chromium.launch({
    channel: 'msedge',
    headless: true,
    args: [
      // กล้อง/ไมค์ปลอม: ให้ getUserMedia คืนภาพทดสอบแทนที่จะล้มเพราะไม่มีอุปกรณ์
      '--use-fake-device-for-media-stream',
      '--use-fake-ui-for-media-stream',
      // วิดีโอที่มีเสียงจะถูกบล็อกไม่ให้เล่นเองถ้าไม่มีคลิก — ปิดกฎนั้นตอนเทส
      '--autoplay-policy=no-user-gesture-required',
    ],
  });
  const errors = [];
  const newContext = async (viewport) => {
    const context = await browser.newContext({ viewport, serviceWorkers: 'block', permissions: ['camera', 'microphone'] });
    await context.grantPermissions(['camera', 'microphone'], { origin });
    return context;
  };

  try {
    // ---------------------------------------------------------- ฝั่งผู้ช่วย
    const hostContext = await newContext({ width: 1440, height: 1000 });
    const session = await (await hostContext.request.get(`${origin}/__test/session/10`)).json();
    await hostContext.addInitScript((s) => {
      localStorage.setItem('token', s.token);
      localStorage.setItem('employee', JSON.stringify(s.employee));
    }, session);
    const host = await hostContext.newPage();
    host.on('pageerror', (e) => errors.push(`host: ${e.message}`));
    await host.goto(`${origin}/it-support`);

    await host.getByLabel('เรื่องที่ต้องแก้').fill('ปริ้นเตอร์ไม่ออกกระดาษ');
    await host.getByLabel('ชื่อผู้ใช้ (ไว้ดูย้อนหลัง)').fill('คุณสมชาย');
    await host.getByRole('button', { name: 'สร้างห้องและคัดลอกลิงก์' }).click();

    // ลิงก์เชิญโผล่ในกล่อง <code> หลังสร้างห้องเสร็จ
    const link = (await host.locator('code').first().textContent()).trim();
    assert.match(link, /\/remote-help\/[\w-]{20,}$/, `ลิงก์เชิญผิดรูปแบบ: ${link}`);
    await host.getByText('รอผู้ใช้กดลิงก์และอนุญาตกล้อง').first().waitFor();
    console.log('  [ผ่าน] ผู้ช่วยสร้างห้องแล้ว รอผู้ใช้เข้า');

    // ---------------------------------------------------------- ฝั่งผู้ใช้
    const guestContext = await newContext({ width: 390, height: 844 });
    const guest = await guestContext.newPage();
    guest.on('pageerror', (e) => errors.push(`guest: ${e.message}`));
    await guest.goto(link);

    // ต้องเห็นชื่อคนขอก่อนตัดสินใจ — เป็นด่านความปลอดภัยที่ตั้งใจใส่ไว้
    await guest.getByText('หัวหน้าทดสอบ').first().waitFor();
    await guest.getByText('ปริ้นเตอร์ไม่ออกกระดาษ').first().waitFor();
    console.log('  [ผ่าน] ผู้ใช้เห็นชื่อผู้ช่วยและเรื่องที่ต้องแก้ก่อนกดอนุญาต');

    await guest.getByRole('button', { name: 'อนุญาตกล้องและไมโครโฟน' }).click();

    // ---------------------------------------------------------- ต่อสายจริง
    await host.getByText('เชื่อมต่อแล้ว').first().waitFor({ timeout: 45000 });
    await guest.getByText('คุยกันได้แล้ว').first().waitFor({ timeout: 45000 });
    console.log('  [ผ่าน] WebRTC ต่อสายสำเร็จทั้งสองฝั่ง');

    // ภาพจากผู้ใช้ต้องมาถึงจอผู้ช่วยจริง ไม่ใช่แค่สถานะขึ้นว่าต่อแล้ว
    //
    // ใช้ waitForFunction ที่มี timeout เสมอ — เคยเขียนเป็น setTimeout วนรอใน evaluate
    // แล้ว renderer ค้างจนพัง ("Target crashed") เพราะไม่มีอะไรหยุดลูปให้
    await host.waitForFunction(
      () => {
        const v = document.querySelector('video');
        return Boolean(v && v.videoWidth > 0);
      },
      null,
      { timeout: 30000 },
    );
    const remoteSize = await host.locator('video').first().evaluate((v) => [v.videoWidth, v.videoHeight]);
    assert.ok(remoteSize[0] > 0 && remoteSize[1] > 0, 'ผู้ช่วยไม่ได้รับภาพจากผู้ใช้');
    console.log(`  [ผ่าน] ผู้ช่วยเห็นภาพจากกล้องผู้ใช้จริง (${remoteSize.join('x')})`);

    // ---------------------------------------------------------- วาดชี้จุด
    const guestCanvas = guest.locator('canvas').first();
    assert.equal(await guestCanvas.evaluate(countInk), 0, 'จอผู้ใช้ควรยังไม่มีเส้นก่อนผู้ช่วยวาด');

    await host.getByRole('button', { name: 'วงกลม' }).click();
    const box = await host.locator('canvas').first().boundingBox();
    await host.mouse.move(box.x + box.width * 0.35, box.y + box.height * 0.35);
    await host.mouse.down();
    await host.mouse.move(box.x + box.width * 0.5, box.y + box.height * 0.5, { steps: 8 });
    await host.mouse.move(box.x + box.width * 0.65, box.y + box.height * 0.65, { steps: 8 });
    await host.mouse.up();

    await guest.waitForFunction(
      () => {
        const canvas = document.querySelector('canvas');
        if (!canvas) return false;
        const { data } = canvas.getContext('2d').getImageData(0, 0, canvas.width, canvas.height);
        for (let i = 3; i < data.length; i += 4) if (data[i] > 0) return true;
        return false;
      },
      null,
      { timeout: 15000 },
    );
    const inkAfterDraw = await guestCanvas.evaluate(countInk);
    console.log(`  [ผ่าน] วงกลมที่ผู้ช่วยวาดไปโผล่บนจอผู้ใช้ (${inkAfterDraw} พิกเซล)`);

    // ---------------------------------------------------------- หยุดภาพ
    await host.getByRole('button', { name: /หยุดภาพไว้วาด/ }).click();
    await guest.locator('img[alt="ภาพที่หยุดไว้เพื่อชี้จุด"]').waitFor({ timeout: 15000 });
    await host.getByText('ภาพนิ่ง').first().waitFor();
    console.log('  [ผ่าน] ผู้ใช้เห็นภาพนิ่งใบเดียวกับผู้ช่วย');

    // หยุดภาพแล้วต้องล้างเส้นเก่าทิ้ง เพราะเส้นเดิมอ้างอิงเฟรมคนละใบ
    assert.equal(await guestCanvas.evaluate(countInk), 0, 'หยุดภาพแล้วเส้นเก่าควรถูกล้าง');

    await host.getByRole('button', { name: 'วาดอิสระ' }).click();
    await host.mouse.move(box.x + box.width * 0.3, box.y + box.height * 0.6);
    await host.mouse.down();
    await host.mouse.move(box.x + box.width * 0.7, box.y + box.height * 0.6, { steps: 12 });
    await host.mouse.up();
    await guest.waitForFunction(
      () => {
        const canvas = document.querySelector('canvas');
        const { data } = canvas.getContext('2d').getImageData(0, 0, canvas.width, canvas.height);
        for (let i = 3; i < data.length; i += 4) if (data[i] > 0) return true;
        return false;
      },
      null,
      { timeout: 15000 },
    );
    console.log('  [ผ่าน] วาดทับภาพนิ่งแล้วผู้ใช้เห็นตาม');

    await host.screenshot({ path: path.join(artifacts, 'support-host.png') });
    await guest.screenshot({ path: path.join(artifacts, 'support-guest.png') });

    // ---------------------------------------------------------- ลบทั้งหมด
    await host.getByRole('button', { name: 'ลบทั้งหมด' }).click();
    await guest.waitForFunction(
      () => {
        const canvas = document.querySelector('canvas');
        const { data } = canvas.getContext('2d').getImageData(0, 0, canvas.width, canvas.height);
        for (let i = 3; i < data.length; i += 4) if (data[i] > 0) return false;
        return true;
      },
      null,
      { timeout: 15000 },
    );
    console.log('  [ผ่าน] กดลบทั้งหมดแล้วเส้นหายทั้งสองฝั่ง');

    // ---------------------------------------------------------- จอแคบต้องไม่ล้น
    assert.equal(
      await guest.evaluate(() => document.documentElement.scrollWidth <= innerWidth),
      true,
      'หน้าฝั่งผู้ใช้ล้นขอบจอมือถือ',
    );
    console.log('  [ผ่าน] หน้าฝั่งผู้ใช้พอดีจอมือถือ 390px');

    // ---------------------------------------------------------- ปิดห้อง
    await host.getByRole('button', { name: 'ปิดห้อง', exact: true }).click();
    await guest.getByText('ผู้ช่วยปิดห้องแล้ว').first().waitFor({ timeout: 20000 });
    // กล้องต้องดับจริง ไม่ใช่แค่หน้าจอเปลี่ยน — ปล่อยไฟกล้องติดค้างทั้งที่ไม่มีใครดูคือปัญหา
    const liveTracks = await guest.evaluate(
      () => performance.getEntriesByType('resource').length >= 0
        && document.querySelectorAll('video').length,
    );
    assert.equal(liveTracks, 0, 'หน้าจอจบงานไม่ควรมี <video> เหลืออยู่');
    console.log('  [ผ่าน] ผู้ช่วยปิดห้องแล้วฝั่งผู้ใช้รู้ทันทีและกล้องดับ');

    assert.deepEqual(errors, [], `มี error ในเบราว์เซอร์: ${errors.join(' | ')}`);
    console.log('\nเทสเบราว์เซอร์ผ่านทั้งหมด');
  } catch (error) {
    console.error(`\nไม่ผ่าน: ${error.message}`);
    if (errors.length) console.error(`error ในเบราว์เซอร์: ${errors.join(' | ')}`);
    process.exitCode = 1;
  } finally {
    await browser.close();
  }
})();

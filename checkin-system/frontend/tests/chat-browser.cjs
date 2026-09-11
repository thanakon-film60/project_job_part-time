const {chromium}=require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const assert=require('node:assert/strict');
const path=require('node:path');
const origin=process.env.CHAT_TEST_ORIGIN;
(async()=>{
  const browser=await chromium.launch({channel:'msedge',headless:true});
  const errors=[];
  try {
    async function login(id,viewport) {
      const context=await browser.newContext({viewport,serviceWorkers:'block'});
      const session=await (await context.request.get(`${origin}/__test/session/${id}`)).json();
      await context.addInitScript((session)=>{localStorage.setItem('token',session.token);localStorage.setItem('employee',JSON.stringify(session.employee));},session);
      const page=await context.newPage(); page.on('pageerror',e=>errors.push(e.message));
      await page.goto(origin);
      return {context,page,session};
    }
    const staff=await login(1,{width:390,height:844});
    const boss=await login(10,{width:1440,height:1000});
    const sp=staff.page,bp=boss.page;
    await sp.getByRole('button',{name:'แชท',exact:true}).click();
    await sp.getByRole('button',{name:/หัวหน้าทดสอบ/}).click();
    await sp.getByRole('textbox',{name:'พิมพ์ข้อความ'}).fill('สวัสดีครับหัวหน้า');
    await sp.getByRole('button',{name:'ยุบแชท',exact:true}).click();
    assert.equal(await sp.locator('#work-chat').isVisible(),false);
    await sp.getByRole('button',{name:'แชท',exact:true}).click();
    assert.equal(await sp.getByRole('textbox',{name:'พิมพ์ข้อความ'}).inputValue(),'สวัสดีครับหัวหน้า');
    await sp.getByRole('button',{name:'ส่งข้อความ',exact:true}).click();
    await sp.getByRole('log').getByText('สวัสดีครับหัวหน้า',{exact:true}).waitFor();
    await bp.getByRole('button',{name:/แชท มี 1 ข้อความ/}).waitFor({timeout:16000});
    await bp.getByRole('button',{name:/แชท มี 1 ข้อความ/}).click();
    await bp.getByRole('button',{name:/พนักงานทดสอบ/}).click();
    await bp.getByRole('log').getByText('สวัสดีครับหัวหน้า',{exact:true}).waitFor();
    await sp.getByRole('log').getByText(/อ่านแล้ว/).waitFor({timeout:10000});
    await bp.getByRole('textbox',{name:'พิมพ์ข้อความ'}).fill('รับทราบครับ\nเจอกันที่สำนักงาน');
    await bp.getByRole('button',{name:'ส่งข้อความ',exact:true}).click();
    await sp.getByRole('log').getByText('รับทราบครับ\nเจอกันที่สำนักงาน',{exact:true}).waitFor({timeout:10000});
    assert.equal(await sp.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true);
    const panel=await sp.locator('#work-chat').boundingBox(); assert.ok(panel.x>=0 && panel.x+panel.width<=390);
    await sp.screenshot({path:path.join(process.env.CHAT_TEST_ARTIFACTS,'chat-mobile.png'),fullPage:true});
    await bp.screenshot({path:path.join(process.env.CHAT_TEST_ARTIFACTS,'chat-desktop.png'),fullPage:true});

    // A message accepted by the server whose response is lost must not duplicate on retry.
    let once=true;
    await sp.route('**/chat/messages/10',async route=>{
      if(route.request().method()==='POST' && once){once=false;await route.fetch();return route.abort('failed');}
      return route.continue();
    });
    await sp.getByRole('textbox',{name:'พิมพ์ข้อความ'}).fill('ทดสอบส่งซ้ำหลังเน็ตหลุด');
    await sp.getByRole('button',{name:'ส่งข้อความ',exact:true}).click();
    await sp.getByRole('alert').getByText(/ส่งไม่สำเร็จ/).waitFor();
    assert.equal(await sp.getByRole('textbox',{name:'พิมพ์ข้อความ'}).inputValue(),'ทดสอบส่งซ้ำหลังเน็ตหลุด');
    await sp.getByRole('button',{name:'ส่งข้อความ',exact:true}).click();
    await sp.getByRole('log').getByText('ทดสอบส่งซ้ำหลังเน็ตหลุด',{exact:true}).waitFor();
    const result=await (await staff.context.request.get(`${origin}/chat/messages/10`,{headers:{Authorization:`Bearer ${staff.session.token}`}})).json();
    assert.equal(result.messages.filter(m=>m.body==='ทดสอบส่งซ้ำหลังเน็ตหลุด').length,1);

    // Changing pages must preserve the open panel and the draft; reload must restore history.
    await sp.getByRole('textbox',{name:'พิมพ์ข้อความ'}).fill('ข้อความที่ยังไม่ส่ง');
    await sp.locator('nav').last().getByRole('link',{name:'ประวัติใบหน้า',exact:true}).click();
    assert.equal(await sp.getByRole('textbox',{name:'พิมพ์ข้อความ'}).inputValue(),'ข้อความที่ยังไม่ส่ง');
    await sp.reload();
    await sp.getByRole('button',{name:/^แชท/}).click();
    await sp.getByRole('button',{name:/หัวหน้าทดสอบ/}).click();
    await sp.getByRole('log').getByText('สวัสดีครับหัวหน้า',{exact:true}).waitFor();
    await sp.getByRole('textbox',{name:'พิมพ์ข้อความ'}).fill('<img src=x onerror=alert(1)>');
    await sp.getByRole('button',{name:'ส่งข้อความ',exact:true}).click();
    await sp.getByRole('log').getByText('<img src=x onerror=alert(1)>',{exact:true}).waitFor();
    assert.equal(await sp.getByRole('log').locator('img').count(),0);
    await sp.keyboard.press('Escape'); assert.equal(await sp.locator('#work-chat').isVisible(),false);
    assert.deepEqual(errors,[]);
    console.log('PASS: real API between boss/staff browsers; unread/read receipts; bidirectional Thai messages; mobile/desktop; collapse/draft; navigation; persisted history; response-loss retry exactly once; HTML rendered as text; Escape.');
    await staff.context.close();await boss.context.close();
  } finally {await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});

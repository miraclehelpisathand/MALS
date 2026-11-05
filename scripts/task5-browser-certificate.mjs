// Optional end-to-end browser check using synthetic data only. Requires Vite on
// an isolated Vite server and Playwright/Chromium installed outside the repository.
// See TASK_5_IN_PROGRESS.md. No Supabase access or real user data is involved;
// this does not replace signed-in or physical-device tests.
import { writeFile, unlink } from 'node:fs/promises';
import { join, dirname } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import assert from 'node:assert/strict';

const root=dirname(dirname(fileURLToPath(import.meta.url)));
const modules=process.env.TASK5_BROWSER_NODE_MODULES;
if(!modules)throw Error('Set TASK5_BROWSER_NODE_MODULES to external node_modules containing playwright-core and @sparticuz/chromium.');
const {chromium}=await import(pathToFileURL(join(modules,'playwright-core/index.mjs')));
const {default:chrome}=await import(pathToFileURL(join(modules,'@sparticuz/chromium/build/index.js')));
const prefix=`_task5_test_${process.pid}`,html=join(root,`${prefix}.html`),jsx=join(root,`${prefix}.jsx`);
let browser, htmlCreated=false, jsxCreated=false;
try {
 await writeFile(html,`<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1" /></head><body><div id="root"></div><script type="module" src="/${prefix}.jsx"></script></body></html>`,{flag:'wx'});htmlCreated=true;
 await writeFile(jsx,`import React from 'react';import{createRoot}from'react-dom/client';import{PDFDocument,PDFName,rgb,degrees,StandardFonts}from'pdf-lib';import * as pdfjs from 'pdfjs-dist';import {CertificateEditor} from '/src/CertificateEditor.jsx';import{renderCertificatePdf,fromBase64,toBase64}from'/src/certificatePdf.js';
 window.makeTemplate=async rotation=>{const doc=await PDFDocument.create(),p=doc.addPage([800,600]),font=await doc.embedFont(StandardFonts.HelveticaBold);p.drawRectangle({x:0,y:0,width:800,height:600,color:rgb(.98,.98,.94)});p.drawRectangle({x:60,y:70,width:680,height:460,borderColor:rgb(.2,.4,.3),borderWidth:3});p.drawText('MIRACLE ACADEMY - TEST CERTIFICATE',{x:100,y:480,size:22,font,color:rgb(.1,.2,.15)});for(const [x,y,color] of [[52,62,rgb(1,0,0)],[732,62,rgb(0,1,0)],[52,522,rgb(0,0,1)],[732,522,rgb(1,1,0)]])p.drawRectangle({x,y,width:16,height:16,color});p.setCropBox(50,60,700,480);p.setRotation(degrees(rotation));p.node.set(PDFName.of('Annots'),doc.context.obj([{Type:'Annot',Subtype:'Link',Rect:[0,0,10,10],A:{S:'JavaScript',JS:'danger'}}]));doc.catalog.set(PDFName.of('OpenAction'),doc.context.obj({S:'JavaScript',JS:'danger'}));return toBase64(await doc.save())};
 window.inspectOutput=async()=>{const a=window.saved,certificate={id:'00000000-0000-4000-8000-000000000001',trainee_name:'Ngārimu Āwhina',course_title:'Safety',course_version:1,completion_date:'2026-11-01',expiry_date:'2027-11-01',layout:a.positions,status:'active'},bytes=await renderCertificatePdf({bytes:fromBase64(a.png_base64),width:a.page_width,height:a.page_height},certificate),doc=await pdfjs.getDocument({data:bytes.slice(),isEvalSupported:false}).promise,p=await doc.getPage(1),vp=p.getViewport({scale:1}),canvas=document.createElement('canvas');canvas.width=Math.ceil(vp.width);canvas.height=Math.ceil(vp.height);await p.render({canvasContext:canvas.getContext('2d'),viewport:vp}).promise;const out=canvas.getContext('2d');const img=new Image();img.src='data:image/png;base64,'+a.png_base64;await img.decode();const src=document.createElement('canvas');src.width=img.naturalWidth;src.height=img.naturalHeight;src.getContext('2d').drawImage(img,0,0);const xy=[[.01,.01],[.99,.01],[.01,.99],[.99,.99]],pixels=xy.map(([x,y])=>({out:Array.from(out.getImageData(Math.floor(x*(canvas.width-1)),Math.floor(y*(canvas.height-1)),1,1).data),src:Array.from(src.getContext('2d').getImageData(Math.floor(x*(src.width-1)),Math.floor(y*(src.height-1)),1,1).data)}));const items=(await p.getTextContent()).items.map(i=>({text:i.str,transform:i.transform}));const loaded=await PDFDocument.load(bytes);return{width:vp.width,height:vp.height,pixels,items,annots:loaded.getPage(0).node.Annots()?.size()||0,openAction:!!loaded.catalog.get(PDFName.of('OpenAction'))}};
 document.body.style.margin='12px';createRoot(document.getElementById('root')).render(<CertificateEditor course={{title:'Safety',family_id:'f',version_number:1}} courseChoices={[]} onSave={v=>window.saved=v} onCancel={()=>{}}/>);`,{flag:'wx'});jsxCreated=true;
 let png;
 for(const width of [320,390,1280]) {
  browser=await chromium.launch({executablePath:await chrome.executablePath(),args:chrome.args,headless:true});
  const page=await browser.newPage({viewport:{width,height:900}});
  const errors=[];page.on('pageerror',error=>errors.push(error.message));page.on('console',message=>{if(message.type()==='error')errors.push(message.text())});page.on('requestfailed',request=>errors.push(`${request.url()}: ${request.failure()?.errorText}`));
  await page.goto(`${process.env.TASK5_PREVIEW_URL||'http://127.0.0.1:5174'}/${prefix}.html`,{waitUntil:'networkidle'});
  if(errors.length)throw Error('Browser harness failed to start: '+errors.join('; '));
  try{await page.waitForFunction(()=>typeof window.makeTemplate==='function',null,{timeout:15000});}catch{throw Error('Browser harness did not load: '+errors.join('; '));}
  for(const angle of [0,90,180,270]) {
   const base64=await page.evaluate(a=>window.makeTemplate(a),angle);
   await page.locator('input[type=file]').setInputFiles({name:`fictional-${angle}.pdf`,mimeType:'application/pdf',buffer:Buffer.from(base64,'base64')});
   await page.getByRole('button',{name:'Position Trainee name'}).waitFor({timeout:30000});
   await page.waitForFunction(()=>{const button=[...document.querySelectorAll('button')].find(b=>b.textContent==='Save certificate settings');return button&&!button.disabled;},null,{timeout:30000});
   await page.getByLabel('Horizontal (%)').fill('30');
   await page.getByLabel('Vertical (%)').fill('35');
   await page.getByLabel('Font size', {exact:true}).fill('22');
   if(angle===0){
    const stage=await page.locator('.certificate-stage').boundingBox();
    const field=await page.getByRole('button',{name:'Position Trainee name'}).boundingBox();
    await page.mouse.move(field.x+5,field.y+5);await page.mouse.down();
    await page.mouse.move(stage.x+stage.width*.4,stage.y+stage.height*.4);await page.mouse.up();
   }
   await page.evaluate(()=>{window.saved=null});
   await page.getByRole('button',{name:'Save certificate settings'}).click();
   await page.waitForFunction(()=>window.saved!==null,{timeout:30000});
   const details=await page.evaluate(()=>window.inspectOutput());
   const saved=await page.evaluate(()=>window.saved);
   assert(Math.abs(saved.positions.name.x-(angle===0?40:30))<.5,'field horizontal input or drag');
   assert(Math.abs(saved.positions.name.y-(angle===0?40:35))<.5,'field vertical input or drag');
   assert.equal(saved.positions.name.size,22);
   const expected=angle%180?{width:480,height:700}:{width:700,height:480};
   assert.deepEqual({width:details.width,height:details.height},expected);
   assert.equal(details.annots,0);assert.equal(details.openAction,false);
   for(const pair of details.pixels)for(let c=0;c<3;c++)assert(Math.abs(pair.out[c]-pair.src[c])<15,`artwork mismatch at ${angle}°`);
   const stage=await page.locator('.certificate-stage').boundingBox();
   for(const [key,text,label] of [
    ['name','Ngārimu Āwhina','Trainee name'], ['course','Safety · Version 1','Course and version'],
    ['completion_date','1 November 2026','Completion date'], ['expiry_date','1 November 2027','Expiry date'],
    ['certificate_id','00000000-0000-4000-8000-000000000001','Certificate number'],
   ]){
    const item=details.items.find(i=>i.text===text),position=saved.positions[key];
    assert(item,`${key} missing at ${angle}°`);
    assert(Math.abs(item.transform[4]-expected.width*position.x/100)<.1,`${key} PDF horizontal position`);
    assert(Math.abs(item.transform[5]-(expected.height-expected.height*position.y/100-position.size))<.1,`${key} PDF vertical position`);
    const field=await page.getByRole('button',{name:`Position ${label}`}).boundingBox();
    assert(Math.abs(field.x-stage.x-stage.width*position.x/100)<2,`${key} editor horizontal position`);
    assert(Math.abs(field.y-stage.y-stage.height*position.y/100)<2,`${key} editor vertical position`);
   }
   const overflow=await page.evaluate(()=>document.documentElement.scrollWidth>window.innerWidth+1);
   assert(!overflow,`Horizontal overflow at ${width}px`);
   png={data:saved.png_base64,width:saved.page_width,height:saved.page_height};
  }
  assert.deepEqual(errors,[]);await page.close();await browser.close();browser=null;
  console.log(`Certificate browser checks passed at ${width}px for all four rotations.`);
 }
 // Test actual browser output through the same server-side PNG validator.
 const {PGlite}=await import('@electric-sql/pglite');const {readFile,readdir}=await import('node:fs/promises');const db=new PGlite();
 try {await db.exec("create role anon;create role authenticated;create schema auth;create table auth.users(id uuid primary key,email text);create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;grant usage on schema auth to authenticated;grant execute on function auth.uid() to authenticated;");for(const f of (await readdir(join(root,'supabase/migrations'))).filter(n=>n.endsWith('.sql')&&n<='202611010011_certificate_core.sql').sort())await db.exec(await readFile(join(root,'supabase/migrations',f),'utf8'));await db.query("select private.validate_certificate_png(decode($1,'base64'),$2,$3)",[png.data,png.width,png.height]);}finally{await db.close()}
 console.log('Browser certificate checks passed: fictional template, four rotations, field positions, flattened artwork, annotations/actions removed, mobile widths, and database PNG validation.');
} finally {if(browser)await browser.close();await Promise.all([htmlCreated?unlink(html):null,jsxCreated?unlink(jsx):null]);}

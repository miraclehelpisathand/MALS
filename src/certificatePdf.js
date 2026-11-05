// Uploaded PDF templates are rendered locally to a non-interactive bitmap.
// Only the bitmap is stored and delivered to learners; the PDF is discarded.
import fontUrl from './assets/DejaVuSans.ttf?url';

export const certificateFields = {
  name: 'Trainee name', course: 'Course and version', completion_date: 'Completion date',
  expiry_date: 'Expiry date', certificate_id: 'Certificate number',
};
export const defaultCertificateLayout = {
  name:{x:20,y:42,size:24}, course:{x:20,y:52,size:18}, completion_date:{x:20,y:62,size:12},
  expiry_date:{x:20,y:68,size:12}, certificate_id:{x:20,y:74,size:10},
};
export function toBase64(bytes) {
  let binary='';for(let i=0;i<bytes.length;i+=32768)binary+=String.fromCharCode(...bytes.subarray(i,i+32768));
  return btoa(binary);
}
export function fromBase64(text) {
  const binary=atob(text.replace(/\s/g,''));return Uint8Array.from(binary,c=>c.charCodeAt(0));
}
export async function inspectCertificateTemplate(bytes) {
  if(!(bytes instanceof Uint8Array)||bytes.length<8||bytes.length>3*1024*1024||new TextDecoder().decode(bytes.subarray(0,5))!=='%PDF-')throw Error('Choose a PDF template no larger than 3 MB.');
  const {PDFDocument}=await import('pdf-lib');let doc;
  try{doc=await PDFDocument.load(bytes,{updateMetadata:false});}catch{throw Error('This PDF could not be opened. Remove password protection or use a valid PDF.');}
  if(doc.getPageCount()!==1)throw Error('Use a single-page PDF certificate template.');
  const page=doc.getPage(0),angle=((page.getRotation().angle%360)+360)%360,media=page.getMediaBox(),crop=page.getCropBox();
  if(![0,90,180,270].includes(angle))throw Error('The PDF page rotation is not supported.');
  // PDF viewers use the intersection of the crop and media boxes. Preserve
  // their offsets while embedding and flatten the page rotation on output.
  const left=Math.max(media.x,crop.x),bottom=Math.max(media.y,crop.y),right=Math.min(media.x+media.width,crop.x+crop.width),top=Math.min(media.y+media.height,crop.y+crop.height),w=right-left,h=top-bottom;
  if(w<100||h<100||w>3000||h>3000)throw Error('The certificate page size is not supported.');
  return {width:angle%180?h:w,height:angle%180?w:h,rotation:angle,crop:{left,bottom,right,top}};
}
// Remove ancillary PNG chunks, including metadata. The database independently
// checks the essential chunk structure and dimensions; image decoding can still
// fail and must never be treated as a guarantee against all decoder defects.
export function stripPngMetadata(bytes) {
  const sig=[137,80,78,71,13,10,26,10];if(bytes.length<45||sig.some((v,i)=>bytes[i]!==v))throw Error('Could not create a certificate image.');
  const view=new DataView(bytes.buffer,bytes.byteOffset,bytes.byteLength),kept=[bytes.slice(0,8)];let pos=8,header=false,data=false,end=false;
  while(pos+12<=bytes.length){const len=view.getUint32(pos),next=pos+12+len;if(next>bytes.length)throw Error('Invalid certificate image.');const kind=String.fromCharCode(...bytes.slice(pos+4,pos+8));if(kind==='IHDR'){if(header||pos!==8||len!==13)throw Error('Invalid certificate image.');header=true;kept.push(bytes.slice(pos,next));}else if(kind==='IDAT'){if(!header||end)throw Error('Invalid certificate image.');data=true;kept.push(bytes.slice(pos,next));}else if(kind==='IEND'){if(!data||len!==0||next!==bytes.length)throw Error('Invalid certificate image.');end=true;kept.push(bytes.slice(pos,next));break;}pos=next;}
  if(!end)throw Error('Incomplete certificate image.');const result=new Uint8Array(kept.reduce((n,v)=>n+v.length,0));let offset=0;for(const part of kept){result.set(part,offset);offset+=part.length;}if(result.length>3*1024*1024)throw Error('The flattened certificate image exceeds 3 MB. Try a simpler PDF template.');return result;
}
export async function flattenCertificateTemplate(pdfBytes) {
  const dims=await inspectCertificateTemplate(pdfBytes),pdfjs=await import('pdfjs-dist'),worker=(await import('pdfjs-dist/build/pdf.worker.min.mjs?url')).default;
  pdfjs.GlobalWorkerOptions.workerSrc=worker;
  const load=pdfjs.getDocument({data:pdfBytes.slice(),isEvalSupported:false,enableXfa:false});
  try{const doc=await load.promise,page=await doc.getPage(1);const scale=Math.min(2,3598/Math.max(dims.width,dims.height),Math.sqrt(11900000/(dims.width*dims.height)));const viewport=page.getViewport({scale});const canvas=document.createElement('canvas');canvas.width=Math.ceil(viewport.width);canvas.height=Math.ceil(viewport.height);const context=canvas.getContext('2d',{alpha:false});if(!context)throw Error('This browser cannot render certificate templates.');await page.render({canvasContext:context,viewport,annotationMode:pdfjs.AnnotationMode.DISABLE}).promise;const blob=await new Promise(resolve=>canvas.toBlob(resolve,'image/png'));if(!blob)throw Error('This browser cannot create certificate images.');return {bytes:stripPngMetadata(new Uint8Array(await blob.arrayBuffer())),width:dims.width,height:dims.height};}finally{await load.destroy();}
}
const dateLabel=value=>value?new Intl.DateTimeFormat('en-NZ',{day:'numeric',month:'long',year:'numeric',timeZone:'UTC'}).format(new Date(`${value}T12:00:00Z`)):'No expiry';
export async function renderCertificatePdf(template,certificate,{fontBytes}={}) {
  const dims={width:Number(template.width),height:Number(template.height)};
  if(!(template.bytes instanceof Uint8Array)||![dims.width,dims.height].every(n=>Number.isFinite(n)&&n>=100&&n<=3000))throw Error('Certificate template image is invalid.');
  const [{PDFDocument,rgb,degrees},fontkitModule]=await Promise.all([import('pdf-lib'),import('@pdf-lib/fontkit')]);
  const response=fontBytes?null:await fetch(fontUrl);if(response&&!response.ok)throw Error('Certificate font could not be loaded.');
  const fontData=fontBytes||new Uint8Array(await response.arrayBuffer());
  const doc=await PDFDocument.create();doc.registerFontkit(fontkitModule.default||fontkitModule);
  const art=await doc.embedPng(template.bytes);const page=doc.addPage([dims.width,dims.height]);page.drawImage(art,{x:0,y:0,width:dims.width,height:dims.height});
  const font=await doc.embedFont(fontData,{subset:true});const supported=new Set(font.getCharacterSet());
  const values={name:certificate.trainee_name,course:`${certificate.course_title} · Version ${certificate.course_version}`,completion_date:dateLabel(certificate.completion_date),expiry_date:dateLabel(certificate.expiry_date),certificate_id:certificate.id};
  for(const [key,textValue] of Object.entries(values)) {
    const setting=certificate.layout?.[key],text=String(textValue||'');
    if(!setting||![setting.x,setting.y,setting.size].every(Number.isFinite)||setting.x<0||setting.x>100||setting.y<0||setting.y>100||setting.size<6||setting.size>72)throw Error('Certificate field positions are invalid.');
    if([...text].some(ch=>!supported.has(ch.codePointAt(0))))throw Error('This certificate contains characters not supported by the installed font.');
    const x=dims.width*setting.x/100,top=dims.height*setting.y/100;let size=setting.size;const available=dims.width-x-4;
    while(size>6&&font.widthOfTextAtSize(text,size)>available)size-=0.5;
    if(font.widthOfTextAtSize(text,size)>available||top+size>dims.height)throw Error(`The ${certificateFields[key]} field does not fit on the certificate. Move the field or reduce its font size.`);
    page.drawText(text,{x,y:dims.height-top-size,size,font,color:rgb(0.08,0.14,0.1)});
  }
  if(certificate.status==='revoked')page.drawText('REVOKED',{x:dims.width*.2,y:dims.height*.32,size:Math.min(64,dims.width*.12),font,color:rgb(.75,.05,.05),opacity:.42,rotate:degrees(25)});
  doc.setTitle(`Certificate ${certificate.id}`);doc.setProducer('Miracle Academy');return doc.save();
}

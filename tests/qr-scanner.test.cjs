const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
function setup({sede='',bodega=''}={}){
 const source=fs.readFileSync(process.env.QR_TEST_FILE||require('node:path').resolve(__dirname,'../dashboard.html'),'utf8');
 const start=source.indexOf('        // QR conserva el contenido leído');
 const nextImport=source.indexOf('        function importarReporteria()',start);
 const end=nextImport>=0?nextImport:source.indexOf('        let inventoryLoadToken',start);
 assert.ok(start>=0&&end>start);
 const elements=Object.fromEntries(['qr-scanner-area','qr-status','startQrScannerBtn','startScannerBtn','codigoBarra','sede','idBodega'].map(id=>[id,{value:'',disabled:false,textContent:'',classList:{add(){},remove(){}},setCustomValidity(s){this.validity=s},focus(){this.focused=true}}]));
 elements.sede.value=sede;elements.idBodega.value=bodega;
 let reader,lookups=[];
 class Scanner{constructor(){reader=this;this.isScanning=false}start(_camera,config,callback){this.config=config;this.callback=callback;this.isScanning=true;return Promise.resolve()}stop(){this.isScanning=false;this.stopped=true;return Promise.resolve()}clear(){this.cleared=true}}
 const context={document:{getElementById:id=>elements[id],querySelectorAll:()=>[]},navigator:{mediaDevices:{getUserMedia(){}}},window:{addEventListener(){}},Html5Qrcode:Scanner,Html5QrcodeSupportedFormats:{QR_CODE:0},console,scanning:false,barcodeStarting:false,stopScanner(){},showNotification(){},buscarArticulo:async value=>{lookups.push(value);elements.codigoBarra.value='catalog-value'}};
 vm.createContext(context);vm.runInContext(source.slice(start,end),context);
 return {context,elements,get reader(){return reader},lookups};
}
test('QR text is placed exactly in the barcode field and camera stops',async()=>{const a=setup();await a.context.startQrScanner();await a.reader.callback('QR-abc 123');assert.equal(a.elements.codigoBarra.value,'QR-abc 123');assert.equal(a.elements.codigoBarra.validity,'');assert.equal(a.reader.stopped,true);assert.deepEqual(a.lookups,[])});
test('numeric QR looks up item when site and warehouse are selected while preserving value',async()=>{const a=setup({sede:'San Pedro Sula',bodega:'030'});await a.context.startQrScanner();await a.reader.callback('0012345678905');assert.deepEqual(a.lookups,['0012345678905']);assert.equal(a.elements.codigoBarra.value,'0012345678905')});
test('multiline QR is rejected rather than silently truncated',async()=>{const a=setup();await a.context.startQrScanner();await a.reader.callback('first\nsecond');assert.equal(a.elements.codigoBarra.value,'');assert.match(a.elements['qr-status'].textContent,/varias líneas/);await a.context.stopQrScanner()});
test('stop button releases the scanner camera',async()=>{const a=setup();await a.context.startQrScanner();await a.context.stopQrScanner();assert.equal(a.reader.stopped,true);assert.equal(a.elements.startScannerBtn.disabled,false)});
test('QR guide fits narrow mobile viewfinders and remains bounded on tablets',async()=>{const a=setup();await a.context.startQrScanner();const small=a.reader.config.qrbox(200,300),large=a.reader.config.qrbox(1024,768);assert.equal(small.width,144);assert.equal(small.height,144);assert.equal(large.width,240);await a.context.stopQrScanner()});

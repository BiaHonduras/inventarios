import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
const require=createRequire(import.meta.url);
const {parseHTML}=require('linkedom');
const tools=await import('../inventory-tools.mjs');
const html=fs.readFileSync(new URL('../dashboard.html',import.meta.url),'utf8');
const {document,window:dom}=parseHTML(html);
Object.defineProperty(dom.HTMLSelectElement.prototype,'value',{configurable:true,get(){return this.querySelector('option[selected]')?.value ?? this.querySelector('option')?.value ?? '';},set(v){for(const o of this.querySelectorAll('option'))o.toggleAttribute('selected',o.value===String(v));}});
Object.defineProperty(dom.HTMLSelectElement.prototype,'selectedOptions',{configurable:true,get(){return this.querySelectorAll('option[selected]').length?this.querySelectorAll('option[selected]'):[this.querySelector('option')].filter(Boolean);}});
Object.defineProperty(dom.HTMLSelectElement.prototype,'options',{configurable:true,get(){return [...this.querySelectorAll('option')];}});
dom.HTMLElement.prototype.focus=function(){};
dom.HTMLElement.prototype.setCustomValidity=function(v){this.validityMessage=v;};
dom.HTMLElement.prototype.getContext=()=>({});
const callbacks=[],events={},requests=[];let writes=0,failExpiry=false,holdInsert=null;
const fixtures={bodegas:[{id_bodega:'030',sede:'San Pedro Sula',nombre:'030',tipos_bodega:{tipos_bodega:'PRINCIPAL',maneja_vencimiento:true}},{id_bodega:'033',sede:'San Pedro Sula',nombre:'033',tipos_bodega:{tipos_bodega:'PPV',maneja_vencimiento:true}},{id_bodega:'095',sede:'San Pedro Sula',nombre:'095',tipos_bodega:{tipos_bodega:'PFN',maneja_vencimiento:false}}],configuracion:[{clave:'dia_vencimiento',valor:tools.hondurasWeekday()}]};
function query(table){let op='read',payload,offset=0,end=Infinity,filters=[];const q={};for(const method of ['select','order','limit','in','gte','lte','delete','upsert','insert','update','eq','maybeSingle','single','range'])q[method]=(...args)=>{if(['insert','update','upsert','delete'].includes(method)){op=method;payload=args[0];}if(method==='eq')filters.push(args);if(method==='range')[offset,end]=args;if(['maybeSingle','single'].includes(method))q.singleResult=true;return q;};q.then=async(resolve,reject)=>{try{requests.push({table,op});let data=fixtures[table]||[],error=null;
if(op==='insert'&&table==='inventarios_diarios'){writes++;if(holdInsert)await holdInsert;data={id:'saved-row'};}
else if(op==='update'&&table==='inventarios_diarios'){writes++;data=null;}
else if(op==='upsert'&&table==='vencimientos_semanales'&&failExpiry)error={message:'expiry failure'};
else {data=data.filter(r=>filters.every(([k,v])=>r[k]===v)).slice(offset,end+1);if(q.singleResult)data=data[0]||null;}
resolve({data,error});}catch(error){reject(error)}};return q;}
const profile={username:'tester',email:'test@example.com',nombre_corto:'Usuario Prueba',role:'admin',sedes:['SPS'],can_write:true,can_delete:true,can_users:true};
const supabase={from:query,rpc:async()=>({data:{},error:null}),auth:{getUser:async()=>({data:{user:{id:'fixture'}}}),onAuthStateChange(){},signOut:async()=>({error:null})},functions:{invoke:async()=>({error:{}})}};
const documentAdd=document.addEventListener.bind(document);document.addEventListener=(name,fn,...rest)=>{if(name==='DOMContentLoaded')callbacks.push(fn);else documentAdd(name,fn,...rest)};
let timers=[];
const context={document,console,Intl,Date,Promise,Map,Set,Number,String,Math,URL,Blob,File:class{},Event:dom.Event,location:{origin:'https://biahonduras.github.io',pathname:'/inventarios/dashboard.html',hash:'',replace(){}},navigator:{},supabase,inventoryTools:tools,sessionStorage:{setItem(){},removeItem(){},getItem(){return null}},localStorage:{getItem(){return null}},setTimeout:(fn)=>{timers.push(fn);return timers.length;},clearTimeout(){},setInterval(){},requestAnimationFrame:fn=>fn(),Chart:class{destroy(){}},Audio:class{play(){return Promise.resolve()}},confirm:()=>false,alert(){}};
context.window=context;context.addEventListener=(event,fn)=>{events[event]=fn};context.requireInventorySession=async()=>({status:'ok',currentUser:profile});context.siteCode=v=>({'San Pedro Sula':'SPS','SPS':'SPS'})[v]||null;context.verificarConexion=async()=>true;
vm.createContext(context);
const scripts=[...html.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/g)].filter(x=>!x[1].includes('src='));
for(const script of scripts)vm.runInContext(script[2].replace(/^\s*import .*;\s*$/gm,''),context);
assert.equal(callbacks.length,1,'only one authenticated initializer');
await callbacks[0]();for(let i=0;i<8;i++)await new Promise(r=>setImmediate(r));
assert.equal(requests.filter(x=>x.table==='bodegas').length,1,'warehouse metadata fetched once');
assert.equal(requests.filter(x=>x.table==='configuracion').length,1,'expiry configuration fetched once');
document.getElementById('sede').value='San Pedro Sula';context.actualizarBodegasPorSede();document.getElementById('idBodega').value='033';await context.evaluarVencimiento();
assert.equal(document.getElementById('checkVencimiento').checked,true,'PPV expiry follows database metadata');
document.getElementById('idBodega').value='095';await context.evaluarVencimiento();assert.equal(document.getElementById('fechaVencimiento').disabled,true,'PFN cannot have expiry');
document.getElementById('idBodega').value='030';await context.evaluarVencimiento();
const values={codigoArticulo:'100020',codigoBarra:'QR-0001',fechaInventario:'2026-10-28',fechaVencimiento:'2027-01-01',masterpack:'1',cajasFardos:'2',unidades:'0'};
for(const[k,v]of Object.entries(values))document.getElementById(k).value=v;
let release;holdInsert=new Promise(r=>release=r);const first=context.agregarArticulo();await new Promise(r=>setImmediate(r));await context.agregarArticulo();assert.equal(writes,1,'double submission writes once');release();await first;holdInsert=null;
for(const[k,v]of Object.entries(values))document.getElementById(k).value=v;document.getElementById('checkVencimiento').checked=true;
failExpiry=true;await context.agregarArticulo();assert.equal(context.editandoId,'saved-row','partial save retains row for retry');const before=writes;failExpiry=false;await context.agregarArticulo();assert.equal(writes,before+1,'retry uses one update');assert.equal(context.editandoId,null);
assert.equal(document.querySelector('.inventory-brand img').getAttribute('src'),'https://biahonduras.github.io/contenedores/brand/bia-honduras-logo.png');
console.log('DOM integration passed: startup, warehouse/expiry metadata, double-save protection, retry and reset.');

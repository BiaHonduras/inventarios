import {test} from 'node:test';import assert from 'node:assert/strict';
import {parseCsv,fetchAllRows,createReadCache,hondurasDate,hondurasWeekday,inventoryDate} from '../inventory-tools.mjs';
test('CSV keeps quoted commas, escaped quotes, BOM and multiline descriptions',()=>{
 const r=parseCsv('\uFEFFCodigo,Descripcion\r\n001,"Cafe, paquete de ""6"""\r\n002,"Primera\nSegunda"\r\n');
 assert.deepEqual(r.headers,['Codigo','Descripcion']);assert.deepEqual(r.rows,[['001','Cafe, paquete de "6"'],['002','Primera\nSegunda']]);
 assert.deepEqual(parseCsv('Codigo;Descripcion\n001;Cafe').rows,[['001','Cafe']]);assert.throws(()=>parseCsv('Codigo,Descripcion\n001,"sin cerrar'),/comillas sin cerrar/);
});
test('paginated reads include every row and return errors instead of partial data',async()=>{
 const rows=Array.from({length:1201},(_,id)=>({id}));let requests=0;
 const r=await fetchAllRows(()=>({range:async(a,b)=>{requests++;return{data:rows.slice(a,b+1),error:null}}}));assert.equal(r.data.length,1201);assert.equal(requests,3);
 requests=0;const failed=await fetchAllRows(()=>({range:async(a,b)=>++requests===2?{error:{message:'offline'}}:{data:rows.slice(a,b+1),error:null}}));assert.equal(failed.data,null);assert.equal(failed.error.message,'offline');
});
test('cache coalesces concurrent lookups, can be invalidated and does not keep errors',async()=>{
 const cache=createReadCache();let calls=0;const read=async()=>({data:[++calls]});
 await Promise.all([cache.get('a',read),cache.get('a',read)]);assert.equal(calls,1);cache.clear();await cache.get('a',read);assert.equal(calls,2);
 await cache.get('error',async()=>({error:'offline'}));const retried=await cache.get('error',async()=>({data:'ok'}));assert.equal(retried.data,'ok');
});
test('Honduras date and weekday do not change at UTC midnight',()=>{const t=new Date('2026-10-28T02:00:00Z');assert.equal(hondurasDate(t),'2026-10-27');assert.equal(hondurasWeekday(t),2)});
test('invalid calendar dates are rejected before a replacement import',()=>{assert.equal(inventoryDate('28/10/2026'),'2026-10-28');assert.equal(inventoryDate('2028-02-29'),'2028-02-29');assert.throws(()=>inventoryDate('2026-02-30'),/calendario/)});

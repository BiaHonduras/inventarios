export async function readInventoryDate(supabase,date,dataset){
 const rows=[];
 for(let offset=0;;offset+=500){
  const {data,error}=await supabase.rpc('inventory_date_rows',{p_fecha:date,p_dataset:dataset,p_offset:offset});
  if(error)return {data:null,error};
  const page=Array.isArray(data)?data:[];rows.push(...page);
  if(page.length<500)return {data:rows,error:null};
 }
}
export function inventoryScope(rows,{site='Todas',type='Todas',search=''}={},warehouses=[],siteCode=v=>String(v??'').trim().toUpperCase()){
 const normalize=v=>String(v??'').trim().toLocaleLowerCase('es');
 return rows.filter(row=>{
  const warehouse=warehouses.find(w=>String(w.id_bodega).trim()===String(row.idBodega).trim());
  return (site==='Todas'||siteCode(warehouse?.sede||row.sede)===siteCode(site))&&
   (type==='Todas'||normalize((typeof warehouse?.tipos_bodega==='object'?warehouse.tipos_bodega?.tipos_bodega:warehouse?.tipos_bodega)||row.tipos_bodega)===normalize(type))&&
   (!search||[row.idBodega,row.fecha,row.codigo,row.codigo_barra,row.descripcion,row.proveedor,row.sede].some(v=>normalize(v).includes(normalize(search))));
 });
}
export function inventoryMetrics(base,counts){
 const key=r=>`${String(r.idBodega).trim()}|${String(r.codigo).trim()}`;
 const expected=new Set(base.map(key)),counted=new Set(counts.map(key));
 const completed=[...expected].filter(k=>counted.has(k)).length;
 return {pending:expected.size-completed,counted:counted.size,percent:expected.size?completed/expected.size*100:0};
}

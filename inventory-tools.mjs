// Shared helpers used by the live inventory page; no credentials or stored user data.
export function hondurasDate(date = new Date()) {
  const parts = new Intl.DateTimeFormat('en-CA', {timeZone:'America/Tegucigalpa',year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(date);
  const values = Object.fromEntries(parts.map(part => [part.type, part.value]));
  return `${values.year}-${values.month}-${values.day}`;
}
export function hondurasWeekday(date = new Date()) {
  return new Date(`${hondurasDate(date)}T12:00:00Z`).getUTCDay();
}
export function inventoryDate(value) {
  let text=String(value||'').trim();
  const local=/^(\d{1,2})\/(\d{1,2})\/(\d{4})$/.exec(text);
  if(local)text=`${local[3]}-${local[2].padStart(2,'0')}-${local[1].padStart(2,'0')}`;
  if(!/^\d{4}-\d{2}-\d{2}$/.test(text))throw new Error('Usa fechas AAAA-MM-DD o DD/MM/AAAA.');
  const date=new Date(`${text}T12:00:00Z`);
  if(!Number.isFinite(date.getTime())||date.toISOString().slice(0,10)!==text)throw new Error('La fecha no existe en el calendario.');
  return text;
}
export function parseCsv(text = '') {
  const input = String(text).replace(/^\uFEFF/, '');
  let quoted = false, first = '', separator = ',';
  for (let i=0;i<input.length;i++) {
    const char=input[i];
    if(char==='"') { if(quoted&&input[i+1]==='"') {i++;continue} quoted=!quoted; }
    if(!quoted&&(char==='\r'||char==='\n')) break;
    if(!quoted) first+=char;
  }
  const candidates=[',',';','\t'].map(value=>({value,count:first.split(value).length-1})).sort((a,b)=>b.count-a.count);
  if(candidates[0].count) separator=candidates[0].value;
  const records=[];let row=[],field='';quoted=false;
  const endRow=()=>{row.push(field);field='';if(row.some(value=>value.trim()!==''))records.push(row);row=[];};
  for(let i=0;i<input.length;i++) {
    const char=input[i];
    if(char==='"') {
      if(quoted&&input[i+1]==='"'){field+='"';i++;}
      else if(quoted||field.trim()==='') quoted=!quoted;
      else field+=char;
    } else if(char===separator&&!quoted){row.push(field);field='';}
    else if((char==='\r'||char==='\n')&&!quoted){if(char==='\r'&&input[i+1]==='\n')i++;endRow();}
    else field+=char;
  }
  if(quoted) throw new Error('El archivo CSV contiene comillas sin cerrar. Revisa el archivo antes de importar.');
  endRow();
  return {headers:(records.shift()||[]).map(value=>value.trim()),rows:records};
}
export async function fetchAllRows(createQuery, pageSize=500) {
  const rows=[];
  for(let offset=0;;offset+=pageSize){
    const result=await createQuery().range(offset,offset+pageSize-1);
    if(result.error)return {data:null,error:result.error};
    const page=Array.isArray(result.data)?result.data:[];
    rows.push(...page);
    if(page.length<pageSize)return {data:rows,error:null};
  }
}
export function createReadCache(ttl=30000) {
  const entries=new Map();
  return {
    clear(){entries.clear();},
    async get(key,read){
      let entry=entries.get(key);
      if(entry&&entry.expires>Date.now())return entry.promise;
      if(entries.size>=20)entries.delete(entries.keys().next().value);
      entry={expires:Date.now()+ttl,promise:Promise.resolve().then(read)};
      entries.set(key,entry);
      try {const result=await entry.promise;if(result?.error&&entries.get(key)===entry)entries.delete(key);return result;}
      catch(error){if(entries.get(key)===entry)entries.delete(key);throw error;}
    }
  };
}

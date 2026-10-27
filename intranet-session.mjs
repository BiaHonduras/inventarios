export const siteNames={SPS:'San Pedro Sula',CBA:'La Ceiba',SRC:'Santa Rosa de Copan',TGU:'Tegucigalpa',AMT:'Amarateca'};
export function siteCode(value){const normalized=String(value||'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').trim().toUpperCase();return Object.entries(siteNames).find(([code,name])=>code===normalized||name.toUpperCase()===normalized)?.[0]||null;}
export async function inventorySession(supabase){
  try {
    const {data,error}=await supabase.auth.getUser();
    if(error||!data?.user)return {status:'login'};
    const user=data.user;
    if(user.app_metadata?.must_change_password)return {status:'password'};
    const result=await supabase.rpc('bia_profile');
    if(result.error?.message?.includes('CAMBIO_PASSWORD_REQUERIDO'))return {status:'password'};
    if(result.error)return {status:'error'};
    const profile=result.data;
    if(!profile?.is_active||!profile.applications?.includes('inventarios')||!profile.sedes?.length)return {status:'denied'};
    const legacy=await supabase.from('usuarios').select('usuario,sede,tipo_bodega').eq('auth_user_id',user.id).maybeSingle();
    const row=legacy.error?null:legacy.data;
    const sites=profile.sedes.filter(s=>siteNames[s]);
    if(!sites.length)return {status:'denied'};
    const oldSite=siteCode(row?.sede);
    const site=sites.includes(oldSite)?oldSite:(sites.includes(profile.agency)?profile.agency:sites[0]);
    const name=row?.usuario||user.email||'';
    return {status:'ok',profile,currentUser:{username:name,usuario:name,email:user.email,correo:user.email,nombre_corto:profile.nombre_corto||'',role:profile.role,role_code:profile.role_code,sede:siteNames[site],sedes:sites,tipoBodega:row?.tipo_bodega||null,tipos_bodega:row?.tipo_bodega||null,can_write:profile.permissions?.write===true,can_catalogs:profile.permissions?.catalogs===true,can_delete:profile.permissions?.delete===true,can_users:profile.permissions?.users===true}};
  } catch {return {status:'error'};}
}
export async function requireInventorySession(supabase){
  const session=await inventorySession(supabase);
  if(session.status==='password')location.replace('../control-tiempos/cambiar-password.html');
  else if(session.status==='login'||session.status==='denied')location.replace('../control-tiempos/intranet.html');
  else if(session.status==='error'){document.documentElement.style.visibility='visible';document.body.innerHTML='<main style="font-family:sans-serif;padding:2rem">No fue posible verificar el acceso a Inventarios. <a href="../control-tiempos/intranet.html">Volver a la Intranet</a>.</main>';}
  return session;
}

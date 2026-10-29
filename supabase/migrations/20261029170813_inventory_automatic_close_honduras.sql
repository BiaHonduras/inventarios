-- Scheduled inventory close: 23:50 Honduras, Monday through Saturday.
create extension if not exists pg_cron;
alter table bia_acl_private.inventory_daily_closures alter column closed_by drop not null;
create function bia_acl_private.inventory_auto_close_one(p_fecha date,p_bodega text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare existente bia_acl_private.inventory_daily_closures; b public.bodegas;
 base jsonb; conteos jsonb; justificaciones jsonb; fuente jsonb; resumen jsonb; huella text;
 cierre_id uuid; nombre text; faltan int; sin_fecha int;
begin
 if p_fecha is null or p_fecha>(now() at time zone 'America/Tegucigalpa')::date then raise exception 'FECHA_DE_CIERRE_INVALIDA'; end if;

 select * into b from public.bodegas where id_bodega=p_bodega;
 if b.id_bodega is null then raise exception 'BODEGA_NO_CONFIGURADA'; end if;
 -- Same advisory lock as baseline import; consistent lock order for all mutations.
 perform pg_advisory_xact_lock(hashtext('inventarios-reporteria-import'));
 select * into existente from bia_acl_private.inventory_daily_closures where fecha=p_fecha and bodega=p_bodega;
 if existente.id is not null then return jsonb_build_object('cerrado',true,'ya_cerrado',true,'id',existente.id,'resumen',existente.resumen); end if;
 if true then
  lock table public.inventarios_diarios,public.inventario_reporteria,public.inventario_justificaciones in share row exclusive mode;
 end if;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]') into base from public.inventario_reporteria x where x.fecha=p_fecha and x."idBodega"=p_bodega;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]') into conteos from public.inventarios_diarios x where x.fecha=p_fecha and x."idBodega"=p_bodega;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]') into justificaciones from public.inventario_justificaciones x where x.fecha_registro=p_fecha and x."idBodega"=p_bodega;
 select count(*) into sin_fecha from public.inventario_justificaciones x where x.fecha_registro is null and x."idBodega"=p_bodega;
 -- Retain the source workbook fields from the latest applied matching upload, when available.
 select coalesce(jsonb_agg(r),'[]') into fuente from jsonb_array_elements(coalesce((select u.payload from bia_acl_private.excel_inventory_uploads u where u.applied_at is not null and u.result->>'fecha'=p_fecha::text and u.result->'bodegas' ? p_bodega order by u.applied_at desc limit 1),'[]')) r where lpad(r->>'Bodega',3,'0')=p_bodega;
 select count(distinct x->>'codigo') into faltan from jsonb_array_elements(base) x where not exists(select 1 from jsonb_array_elements(conteos) c where c->>'codigo'=x->>'codigo');
 huella:=md5(base::text||conteos::text||justificaciones::text||sin_fecha::text);
 resumen:=jsonb_build_object('fecha',p_fecha,'bodega',p_bodega,'sede',b.sede,
  'registros_base',jsonb_array_length(base),'registros_conteo',jsonb_array_length(conteos),'justificaciones',jsonb_array_length(justificaciones),
  'sku_sin_conteo',faltan,'justificaciones_sin_fecha',sin_fecha,
  'unidades_base',(select coalesce(sum((x->>'inventario_reporteria')::numeric),0) from jsonb_array_elements(base) x),
  'unidades_contadas',(select coalesce(sum(coalesce((x->>'total')::numeric,coalesce((x->>'cajas_fardos')::numeric,0)*coalesce((x->>'masterpack')::numeric,0)+coalesce((x->>'unidades')::numeric,0))),0) from jsonb_array_elements(conteos) x));
 insert into bia_acl_private.inventory_daily_closures(fecha,bodega,sede,closed_by,closed_name,resumen,datos)
 values(p_fecha,p_bodega,b.sede,null,'Cierre automático',resumen,
 jsonb_build_object('base',base,'conteos',conteos,'justificaciones',justificaciones,'fuente_excel',fuente,'justificaciones_sin_fecha',(select coalesce(jsonb_agg(to_jsonb(j)),'[]') from public.inventario_justificaciones j where j.fecha_registro is null and j."idBodega"=p_bodega))) returning id into cierre_id;
 -- Exact date/warehouse scope; deletion failures roll the entire snapshot back.
 delete from public.inventario_justificaciones where fecha_registro=p_fecha and "idBodega"=p_bodega;
 delete from public.inventarios_diarios where fecha=p_fecha and "idBodega"=p_bodega;
 delete from public.inventario_reporteria where fecha=p_fecha and "idBodega"=p_bodega;
 return jsonb_build_object('cerrado',true,'id',cierre_id,'resumen',resumen);
end $$;
revoke all on function bia_acl_private.inventory_auto_close_one(date,text) from public,anon,authenticated;
create function bia_acl_private.inventory_auto_close() returns jsonb language plpgsql security definer set search_path='' as $$
declare local_now timestamp := now() at time zone 'America/Tegucigalpa'; b record; n int:=0;
begin
 if extract(isodow from local_now)=7 or local_now::time<time '23:50' then return jsonb_build_object('omitido',true); end if;
 perform pg_advisory_xact_lock(hashtext('inventarios-reporteria-import'));
 lock table public.inventarios_diarios,public.inventario_reporteria,public.inventario_justificaciones in share row exclusive mode;
 for b in select distinct x.bodega from (
 select "idBodega" as bodega from public.inventario_reporteria where fecha=local_now::date
 union select "idBodega" from public.inventarios_diarios where fecha=local_now::date
 union select "idBodega" from public.inventario_justificaciones where fecha_registro=local_now::date
 ) x join public.bodegas w on w.id_bodega=x.bodega order by x.bodega loop
 perform bia_acl_private.inventory_auto_close_one(local_now::date,b.bodega); n:=n+1;
 end loop;
 return jsonb_build_object('fecha',local_now::date,'bodegas',n);
end $$;
revoke all on function bia_acl_private.inventory_auto_close() from public,anon,authenticated;
-- UTC Tue-Sun 05:50 equals Honduras Mon-Sat 23:50. Scheduler timezone is GMT.
select cron.schedule('inventory-close-honduras','50 5 * * 0,2-6','select bia_acl_private.inventory_auto_close();');
-- Closing is performed by the scheduler; readers retain historical access.
revoke execute on function public.inventory_close_day(date,text,boolean,text,boolean) from authenticated;

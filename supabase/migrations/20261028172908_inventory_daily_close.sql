-- Immutable daily snapshots. JSONB retains complete original rows and exact numerics.
create table bia_acl_private.inventory_daily_closures (
 id uuid primary key default gen_random_uuid(), fecha date not null, bodega text not null,
 sede text not null, closed_at timestamptz not null default now(), closed_by uuid not null,
 closed_name text not null, resumen jsonb not null, datos jsonb not null,
 unique(fecha,bodega)
);
alter table bia_acl_private.inventory_daily_closures enable row level security;
revoke all on bia_acl_private.inventory_daily_closures from public,anon,authenticated;

create function public.inventory_can_close(p_bodega text) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and public.bia_inventory_bodega_allowed('write',p_bodega)
 and exists(select 1 from bia_acl_private.accounts a where a.user_id=auth.uid() and a.role in ('administrador','jefatura_zn','jefatura_zc'));
$$;
revoke all on function public.inventory_can_close(text) from public,anon;
grant execute on function public.inventory_can_close(text) to authenticated;

create function public.inventory_close_day(p_fecha date,p_bodega text,p_confirmar boolean default false,p_huella text default null,p_aceptar_pendientes boolean default false)
returns jsonb language plpgsql security definer set search_path='' as $$
declare existente bia_acl_private.inventory_daily_closures; b public.bodegas;
 base jsonb; conteos jsonb; justificaciones jsonb; fuente jsonb; resumen jsonb; huella text;
 cierre_id uuid; nombre text; faltan int; sin_fecha int;
begin
 if p_fecha is null or p_fecha>(now() at time zone 'America/Tegucigalpa')::date then raise exception 'FECHA_DE_CIERRE_INVALIDA'; end if;
 if not public.inventory_can_close(p_bodega) then raise exception 'SIN_PERMISO_PARA_CERRAR_BODEGA'; end if;
 select * into b from public.bodegas where id_bodega=p_bodega;
 if b.id_bodega is null then raise exception 'BODEGA_NO_CONFIGURADA'; end if;
 -- Same advisory lock as baseline import; consistent lock order for all mutations.
 perform pg_advisory_xact_lock(hashtext('inventarios-reporteria-import'));
 select * into existente from bia_acl_private.inventory_daily_closures where fecha=p_fecha and bodega=p_bodega;
 if existente.id is not null then return jsonb_build_object('cerrado',true,'ya_cerrado',true,'id',existente.id,'resumen',existente.resumen); end if;
 if p_confirmar is true then
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
 if p_confirmar is not true then return jsonb_build_object('cerrado',false,'huella',huella,'resumen',resumen); end if;
 if p_huella is distinct from huella then raise exception 'DATOS_CAMBIARON_VUELVA_A_VALIDAR'; end if;
 if jsonb_array_length(base)=0 then raise exception 'NO_HAY_BASE_PARA_ESTA_FECHA_Y_BODEGA'; end if;
 if jsonb_array_length(conteos)=0 then raise exception 'NO_HAY_CONTEOS_PARA_CERRAR'; end if;
 if sin_fecha>0 then raise exception 'HAY_JUSTIFICACIONES_SIN_FECHA_CORRIJALAS_ANTES_DE_CERRAR'; end if;
 if faltan>0 and not coalesce(p_aceptar_pendientes,false) then raise exception 'CONFIRME_LOS_SKU_SIN_CONTEO'; end if;
 select coalesce(nullif(a.nombre_corto,''),'Usuario') into nombre from bia_acl_private.accounts a where a.user_id=auth.uid();
 insert into bia_acl_private.inventory_daily_closures(fecha,bodega,sede,closed_by,closed_name,resumen,datos)
 values(p_fecha,p_bodega,b.sede,auth.uid(),coalesce(nombre,'Usuario'),resumen,
 jsonb_build_object('base',base,'conteos',conteos,'justificaciones',justificaciones,'fuente_excel',fuente)) returning id into cierre_id;
 -- Exact date/warehouse scope; deletion failures roll the entire snapshot back.
 delete from public.inventario_justificaciones where fecha_registro=p_fecha and "idBodega"=p_bodega;
 delete from public.inventarios_diarios where fecha=p_fecha and "idBodega"=p_bodega;
 delete from public.inventario_reporteria where fecha=p_fecha and "idBodega"=p_bodega;
 return jsonb_build_object('cerrado',true,'id',cierre_id,'resumen',resumen);
end $$;
revoke all on function public.inventory_close_day(date,text,boolean,text,boolean) from public,anon;
grant execute on function public.inventory_close_day(date,text,boolean,text,boolean) to authenticated;

create function public.inventory_closed_days(p_desde date default null,p_hasta date default null,p_bodega text default null,p_offset int default 0)
returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not public.bia_can('inventarios','read') then raise exception 'PERMISO_INSUFICIENTE'; end if;
 return coalesce((select jsonb_agg(x) from (select c.id,c.fecha,c.bodega,c.sede,c.closed_at,c.closed_name,c.resumen from bia_acl_private.inventory_daily_closures c
 where (p_desde is null or c.fecha>=p_desde) and (p_hasta is null or c.fecha<=p_hasta) and (p_bodega is null or c.bodega=p_bodega)
 and public.bia_inventory_site_allowed('read',c.sede)
 order by c.fecha desc,c.closed_at desc,c.id limit 50 offset greatest(0,least(coalesce(p_offset,0),100000))) x),'[]');
end $$;
create function public.inventory_closed_detail(p_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare c bia_acl_private.inventory_daily_closures;
begin
 if auth.uid() is null or not public.bia_can('inventarios','read') then raise exception 'PERMISO_INSUFICIENTE'; end if;
 select * into c from bia_acl_private.inventory_daily_closures where id=p_id;
 if c.id is null or not public.bia_inventory_site_allowed('read',c.sede) then raise exception 'CIERRE_NO_DISPONIBLE'; end if;
 return to_jsonb(c)-'closed_by';
end $$;
revoke all on function public.inventory_closed_days(date,date,text,int),public.inventory_closed_detail(uuid) from public,anon;
grant execute on function public.inventory_closed_days(date,date,text,int),public.inventory_closed_detail(uuid) to authenticated;

-- Prevent stale browser tabs, imports and direct writes from recreating a closed day.
create function bia_acl_private.inventory_guard_closed_day() returns trigger language plpgsql security definer set search_path='' as $$
declare d date; anterior date;
begin
 d:=case when tg_table_name='inventario_justificaciones' then (to_jsonb(new)->>'fecha_registro')::date else (to_jsonb(new)->>'fecha')::date end;
 if exists(select 1 from bia_acl_private.inventory_daily_closures c where c.fecha=d and c.bodega=new."idBodega") then raise exception 'DIA_INVENTARIO_CERRADO'; end if;
 if tg_op='UPDATE' then
  anterior:=case when tg_table_name='inventario_justificaciones' then (to_jsonb(old)->>'fecha_registro')::date else (to_jsonb(old)->>'fecha')::date end;
  if exists(select 1 from bia_acl_private.inventory_daily_closures c where c.fecha=anterior and c.bodega=old."idBodega") then raise exception 'DIA_INVENTARIO_CERRADO'; end if;
 end if;
 return new;
end $$;
revoke all on function bia_acl_private.inventory_guard_closed_day() from public,anon,authenticated;
create trigger inventory_closed_guard before insert or update on public.inventarios_diarios for each row execute function bia_acl_private.inventory_guard_closed_day();
create trigger inventory_closed_guard before insert or update on public.inventario_reporteria for each row execute function bia_acl_private.inventory_guard_closed_day();
create trigger inventory_closed_guard before insert or update on public.inventario_justificaciones for each row execute function bia_acl_private.inventory_guard_closed_day();
notify pgrst,'reload schema';

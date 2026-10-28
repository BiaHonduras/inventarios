-- Excel uploads are staged; only the signed-in owner can commit them.
alter table public.inventario_reporteria alter column inventario_reporteria type numeric using inventario_reporteria::numeric;
alter table public.inventarios_diarios alter column inventario_reporteria type numeric using inventario_reporteria::numeric;
create table bia_acl_private.excel_inventory_uploads (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id),
 token_hash text not null unique, expires_at timestamptz not null default now()+interval '30 minutes',
 created_at timestamptz not null default now(), received_at timestamptz, applied_at timestamptz,
 payload jsonb, result jsonb
);
alter table bia_acl_private.excel_inventory_uploads enable row level security;
revoke all on bia_acl_private.excel_inventory_uploads from public,anon,authenticated;
create function public.excel_inventory_pass() returns jsonb language plpgsql security definer set search_path='' as $$
declare token text; lote uuid;
begin
 if auth.uid() is null or not public.bia_can('inventarios','write') then raise exception 'PERMISO_INSUFICIENTE'; end if;
 if (select count(*) from bia_acl_private.excel_inventory_uploads where user_id=auth.uid() and created_at>now()-interval '1 hour')>=20 then raise exception 'LIMITE_DE_SOLICITUDES'; end if;
 -- Revoke previous unreceived passes and remove expired, unapplied payloads after seven days.
 update bia_acl_private.excel_inventory_uploads set expires_at=now() where user_id=auth.uid() and received_at is null;
 delete from bia_acl_private.excel_inventory_uploads where user_id=auth.uid() and applied_at is null and created_at<now()-interval '7 days';
 token:=replace(gen_random_uuid()::text||gen_random_uuid()::text,'-','');
 insert into bia_acl_private.excel_inventory_uploads(user_id,token_hash) values(auth.uid(),encode(sha256(convert_to(token,'UTF8')),'hex')) returning id into lote;
 return jsonb_build_object('id',lote,'codigo',token,'vence',now()+interval '30 minutes');
end $$;
create function public.excel_inventory_receive(p_codigo text,p_registros jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare lote bia_acl_private.excel_inventory_uploads;
begin
 if p_codigo is null or p_codigo !~ '^[a-f0-9]{64}$' then raise exception 'CODIGO_INVALIDO'; end if;
 select * into lote from bia_acl_private.excel_inventory_uploads where token_hash=encode(sha256(convert_to(p_codigo,'UTF8')),'hex') for update;
 if lote.id is null or lote.expires_at<now() or lote.received_at is not null then raise exception 'CODIGO_VENCIDO_O_UTILIZADO'; end if;
 if not bia_acl_private.can_for(lote.user_id,'inventarios','write',null) then raise exception 'PERMISO_INSUFICIENTE'; end if;
 if jsonb_typeof(p_registros) is distinct from 'array' then raise exception 'FORMATO_INVALIDO'; end if;
 if jsonb_array_length(p_registros) not between 1 and 20000 or octet_length(p_registros::text)>20000000 then raise exception 'TAMANO_NO_PERMITIDO'; end if;
 if exists(select 1 from jsonb_array_elements(p_registros) r where jsonb_typeof(r)<>'object') then raise exception 'FILA_INVALIDA'; end if;
 update bia_acl_private.excel_inventory_uploads set payload=p_registros,received_at=now() where id=lote.id;
 return jsonb_build_object('ok',true,'recibidos',jsonb_array_length(p_registros),'mensaje','Carga recibida. Revise y confirme en la web; aun no se han reemplazado existencias.');
end $$;
create function public.excel_inventory_batches() returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not public.bia_can('inventarios','write') then raise exception 'PERMISO_INSUFICIENTE'; end if;
 return coalesce((select jsonb_agg(x) from (select id,created_at,received_at,applied_at,result from bia_acl_private.excel_inventory_uploads where user_id=auth.uid() and received_at is not null order by created_at desc limit 10) x),'[]'::jsonb);
end $$;
create function public.excel_inventory_apply(p_id uuid,p_confirmar boolean default false) returns jsonb language plpgsql security definer set search_path='' as $$
declare lote bia_acl_private.excel_inventory_uploads; r jsonb; b public.bodegas; salida jsonb:='[]'; omitidos jsonb:='{}'; cant numeric; pack numeric; codigo text; fecha date; actual date; resumen jsonb; actor text; origen_date date; n int:=0;
begin
 if auth.uid() is null or not public.bia_can('inventarios','write') then raise exception 'PERMISO_INSUFICIENTE'; end if;
 select * into lote from bia_acl_private.excel_inventory_uploads where id=p_id and user_id=auth.uid() for update;
 if lote.id is null or lote.received_at is null then raise exception 'CARGA_NO_DISPONIBLE'; end if;
 if lote.applied_at is not null then return lote.result||jsonb_build_object('ya_aplicada',true); end if;
 if lote.created_at<now()-interval '7 days' then raise exception 'CARGA_VENCIDA'; end if;
 actual:=(now() at time zone 'America/Tegucigalpa')::date;
 for r in select value from jsonb_array_elements(lote.payload) loop
  n:=n+1;
  if coalesce(r->>'Bodega','') !~ '^\d{1,3}$' then raise exception 'Fila %: Bodega invalida',n; end if;
  select * into b from public.bodegas where id_bodega=lpad(r->>'Bodega',3,'0');
  if b.id_bodega is null then
   codigo:=lpad(r->>'Bodega',3,'0'); omitidos:=jsonb_set(omitidos,array[codigo],to_jsonb(coalesce((omitidos->>codigo)::int,0)+1)); continue;
  end if;
  if not public.bia_inventory_bodega_allowed('write',b.id_bodega) then raise exception 'Fila %: sin permiso para bodega %',n,b.id_bodega; end if;
  codigo:=trim(r->>'CodArticulo');
  if codigo is null or codigo !~ '^\d{1,10}$' or codigo::numeric>2147483647 then raise exception 'Fila %: codigo no compatible con catalogo actual',n; end if;
  if nullif(trim(r->>'CodDescrip'),'') is null then raise exception 'Fila %: falta descripcion',n; end if;
  if coalesce(r->>'Cantidades','') !~ '^-?[0-9]+([.][0-9]+)?$' or coalesce(r->>'Masterpack','') !~ '^[0-9]+([.][0-9]+)?$' then raise exception 'Fila %: cantidad o masterpack invalido',n; end if;
  cant:=(r->>'Cantidades')::numeric; pack:=(r->>'Masterpack')::numeric;
  if abs(cant)>1000000000000 or pack<>trunc(pack) or pack>2147483647 then raise exception 'Fila %: cantidad o masterpack fuera de rango',n; end if;
  if coalesce(r->>'Fecha','') !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'Fila %: fecha invalida',n; end if;
  fecha:=(r->>'Fecha')::date;
  if origen_date is null then origen_date:=fecha; elsif origen_date<>fecha then raise exception 'LA_CARGA_CONTIENE_VARIAS_FECHAS'; end if;
  salida:=salida||jsonb_build_array(jsonb_build_object('fecha',fecha,'codigo',codigo::int,'descripcion',trim(r->>'CodDescrip'),'proveedor',trim(r->>'Proveedor'),'masterpack',pack::int,'inventario_reporteria',cant,'idBodega',b.id_bodega));
 end loop;
 if jsonb_array_length(salida)=0 then raise exception 'NINGUNA_BODEGA_CONFIGURADA'; end if;
 if exists(select 1 from jsonb_to_recordset(salida) as x(codigo int,"idBodega" text) group by codigo,"idBodega" having count(*)>1) then raise exception 'ARTICULO_REPETIDO_EN_BODEGA_REVISAR_SOCIEDAD'; end if;
 resumen:=jsonb_build_object('incluidos',jsonb_array_length(salida),'omitidos',omitidos,'fecha',origen_date,'bodegas',(select jsonb_agg(distinct x."idBodega") from jsonb_to_recordset(salida) as x("idBodega" text)));
 if not p_confirmar then return resumen||jsonb_build_object('aplicada',false); end if;
 if origen_date<>actual then raise exception 'SOLO_SE_PUEDE_IMPORTAR_EL_DIA_ACTUAL_DE_HONDURAS'; end if;
 perform pg_advisory_xact_lock(hashtext('inventarios-reporteria-import'));
 -- Lock counts while deciding if a baseline can be replaced. Concurrent inserts wait until commit.
 lock table public.inventarios_diarios in share row exclusive mode;
 if exists(select 1 from public.inventarios_diarios d where d.fecha=origen_date and d."idBodega" in (select x."idBodega" from jsonb_to_recordset(salida) as x("idBodega" text))) then raise exception 'CONTEO_INICIADO_NO_SE_PUEDE_CAMBIAR_LA_BASE'; end if;
 -- Reporter lookup uses a single current baseline; prevent silently discarding an older count.
 if exists(select 1 from public.inventarios_diarios d where d."idBodega" in (select x."idBodega" from jsonb_to_recordset(salida) as x("idBodega" text)) and d.fecha<>origen_date) then raise exception 'HAY_CONTEOS_ANTERIORES_CIERRE_EL_DIA_ANTES_DE_REEMPLAZAR'; end if;
 delete from public.inventario_reporteria where "idBodega" in (select x."idBodega" from jsonb_to_recordset(salida) as x("idBodega" text));
 insert into public.inventario_reporteria(fecha,codigo,descripcion,proveedor,masterpack,inventario_reporteria,"idBodega") select fecha,codigo,descripcion,proveedor,masterpack,inventario_reporteria,"idBodega" from jsonb_populate_recordset(null::public.inventario_reporteria,salida);
 select coalesce(nullif(trim(usuario),''),correo) into actor from public.usuarios where auth_user_id=auth.uid() limit 1;
 insert into public.inventario_importaciones(usuario,fecha_importacion,cantidad_registros,tipo_importacion) values(coalesce(actor,auth.uid()::text),now(),jsonb_array_length(salida),'inventario');
 resumen:=resumen||jsonb_build_object('aplicada',true);
 update bia_acl_private.excel_inventory_uploads set applied_at=now(),result=resumen where id=p_id;
 return resumen;
end $$;
revoke all on function public.excel_inventory_pass() from public,anon;
revoke all on function public.excel_inventory_batches() from public,anon;
revoke all on function public.excel_inventory_apply(uuid,boolean) from public,anon;
revoke all on function public.excel_inventory_receive(text,jsonb) from public;
grant execute on function public.excel_inventory_pass(),public.excel_inventory_batches(),public.excel_inventory_apply(uuid,boolean) to authenticated;
grant execute on function public.excel_inventory_receive(text,jsonb) to anon,authenticated;
notify pgrst,'reload schema';

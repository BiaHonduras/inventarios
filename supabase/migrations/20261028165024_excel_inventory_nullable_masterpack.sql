create or replace function public.excel_inventory_apply(p_id uuid,p_confirmar boolean default false) returns jsonb language plpgsql security definer set search_path='' as $$
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
  if coalesce(r->>'Cantidades','') !~ '^-?[0-9]+([.][0-9]+)?$' or (nullif(trim(r->>'Masterpack'),'') is not null and r->>'Masterpack' !~ '^[0-9]+([.][0-9]+)?$') then raise exception 'Fila %: cantidad o masterpack invalido',n; end if;
  cant:=(r->>'Cantidades')::numeric; pack:=nullif(trim(r->>'Masterpack'),'')::numeric;
  if abs(cant)>1000000000000 or pack<>trunc(pack) or pack>2147483647 then raise exception 'Fila %: cantidad o masterpack fuera de rango',n; end if;
  if coalesce(r->>'Fecha','') !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'Fila %: fecha invalida',n; end if;
  fecha:=(r->>'Fecha')::date;
  if origen_date is null then origen_date:=fecha; elsif origen_date<>fecha then raise exception 'LA_CARGA_CONTIENE_VARIAS_FECHAS'; end if;
  salida:=salida||jsonb_build_array(jsonb_build_object('fecha',fecha,'codigo',codigo::int,'descripcion',trim(r->>'CodDescrip'),'proveedor',trim(r->>'Proveedor'),'masterpack',pack::int,'inventario_reporteria',cant,'idBodega',b.id_bodega));
 end loop;
 if jsonb_array_length(salida)=0 then raise exception 'NINGUNA_BODEGA_CONFIGURADA'; end if;
 if exists(select 1 from jsonb_to_recordset(salida) as x(codigo int,"idBodega" text) group by x.codigo,x."idBodega" having count(*)>1) then raise exception 'ARTICULO_REPETIDO_EN_BODEGA_REVISAR_SOCIEDAD'; end if;
 resumen:=jsonb_build_object('incluidos',jsonb_array_length(salida),'sin_masterpack',(select count(*) from jsonb_to_recordset(salida) as x(masterpack int) where x.masterpack is null),'omitidos',omitidos,'fecha',origen_date,'bodegas',(select jsonb_agg(distinct x."idBodega") from jsonb_to_recordset(salida) as x("idBodega" text)));
 if not p_confirmar then return resumen||jsonb_build_object('aplicada',false); end if;
 if origen_date<>actual then raise exception 'SOLO_SE_PUEDE_IMPORTAR_EL_DIA_ACTUAL_DE_HONDURAS'; end if;
 perform pg_advisory_xact_lock(hashtext('inventarios-reporteria-import'));
 -- Lock counts while deciding if a baseline can be replaced. Concurrent inserts wait until commit.
 lock table public.inventarios_diarios in share row exclusive mode;
 if exists(select 1 from public.inventarios_diarios d where d.fecha=origen_date and d."idBodega" in (select x."idBodega" from jsonb_to_recordset(salida) as x("idBodega" text))) then raise exception 'CONTEO_INICIADO_NO_SE_PUEDE_CAMBIAR_LA_BASE'; end if;
 -- Reporter lookup uses a single current baseline; prevent silently discarding an older count.
 if exists(select 1 from public.inventarios_diarios d where d."idBodega" in (select x."idBodega" from jsonb_to_recordset(salida) as x("idBodega" text)) and d.fecha<>origen_date) then raise exception 'HAY_CONTEOS_ANTERIORES_CIERRE_EL_DIA_ANTES_DE_REEMPLAZAR'; end if;
 delete from public.inventario_reporteria where "idBodega" in (select x."idBodega" from jsonb_to_recordset(salida) as x("idBodega" text));
 insert into public.inventario_reporteria(fecha,codigo,descripcion,proveedor,masterpack,inventario_reporteria,"idBodega") select x.fecha,x.codigo,x.descripcion,x.proveedor,x.masterpack,x.inventario_reporteria,x."idBodega" from jsonb_populate_recordset(null::public.inventario_reporteria,salida) x;
 select coalesce(nullif(trim(usuario),''),correo) into actor from public.usuarios where auth_user_id=auth.uid() limit 1;
 insert into public.inventario_importaciones(usuario,fecha_importacion,cantidad_registros,tipo_importacion) values(coalesce(actor,auth.uid()::text),now(),jsonb_array_length(salida),'inventario');
 resumen:=resumen||jsonb_build_object('aplicada',true);
 update bia_acl_private.excel_inventory_uploads set applied_at=now(),result=resumen where id=p_id;
 return resumen;
end $$;

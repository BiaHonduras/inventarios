-- Atomic replacement for the existing delete-then-insert browser workflow.
-- The same Intranet app, role and warehouse checks apply to every imported row.
create or replace function public.rpc_importar_inventario_reporteria(p_registros jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare total integer; actor text;
begin
 if auth.uid() is null or not public.bia_can('inventarios','write') then raise exception 'PERMISO_INSUFICIENTE'; end if;
 if jsonb_typeof(p_registros) is distinct from 'array' then raise exception 'FORMATO_INVALIDO'; end if;
 if jsonb_array_length(p_registros)=0 or jsonb_array_length(p_registros)>100000 then raise exception 'CANTIDAD_FILAS_INVALIDA'; end if;
 -- Typed expansion validates dates, integers and varchar lengths before replacement.
 if exists(select 1 from jsonb_populate_recordset(null::public.inventario_reporteria,p_registros) r
   where r.codigo is null or r.fecha is null or nullif(trim(r.descripcion),'') is null
   or r.masterpack is null or r.masterpack<=0 or r.inventario_reporteria is null
   or not exists(select 1 from public.bodegas b where b.id_bodega=r."idBodega")
   or not public.bia_inventory_bodega_allowed('write',r."idBodega"))
 then raise exception 'FILA_INVALIDA_O_BODEGA_NO_AUTORIZADA'; end if;
 select coalesce(nullif(trim(u.usuario),''),u.correo) into actor from public.usuarios u where u.auth_user_id=auth.uid() limit 1;
 if actor is null then raise exception 'USUARIO_NO_VINCULADO'; end if;
 perform pg_advisory_xact_lock(hashtext('inventarios-reporteria-import'));
 delete from public.inventario_reporteria where codigo is not null and public.bia_inventory_bodega_allowed('write',"idBodega");
 insert into public.inventario_reporteria(fecha,proveedor,codigo_barra,codigo,descripcion,inventario_reporteria,masterpack,"idBodega")
 select r.fecha,r.proveedor,r.codigo_barra,r.codigo,r.descripcion,r.inventario_reporteria,r.masterpack,r."idBodega"
 from jsonb_populate_recordset(null::public.inventario_reporteria,p_registros) r;
 get diagnostics total = row_count;
 insert into public.inventario_importaciones(usuario,fecha_importacion,cantidad_registros,tipo_importacion)
 values(actor,now(),total,'inventario');
 return jsonb_build_object('ok',true,'registros',total);
end $$;
revoke all on function public.rpc_importar_inventario_reporteria(jsonb) from public,anon;
grant execute on function public.rpc_importar_inventario_reporteria(jsonb) to authenticated;
notify pgrst,'reload schema';

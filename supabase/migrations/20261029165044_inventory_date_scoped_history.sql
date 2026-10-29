-- Read one consistent dataset for a selected date, scoped to the caller's sites.
create function public.inventory_date_rows(p_fecha date,p_dataset text,p_offset int default 0)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare live_table text; backup_table text; date_column text; result jsonb;
begin
 if auth.uid() is null or not public.bia_can('inventarios','read') then raise exception 'PERMISO_INSUFICIENTE'; end if;
 if p_fecha is null then raise exception 'FECHA_REQUERIDA'; end if;
 case p_dataset
 when 'base' then live_table:='inventario_reporteria';date_column:='fecha';
 when 'conteos' then live_table:='inventarios_diarios';date_column:='fecha';
 when 'justificaciones' then live_table:='inventario_justificaciones';date_column:='fecha_registro';
 else raise exception 'DATASET_INVALIDO'; end case;
 backup_table:=live_table||'_backup';
 execute format($q$
 with permitted as (
 select b.id_bodega,b.sede,c.id as closure_id,c.datos
 from public.bodegas b left join bia_acl_private.inventory_daily_closures c on c.bodega=b.id_bodega and c.fecha=$1
 where public.bia_inventory_bodega_allowed('read',b.id_bodega)
 ), selected as (
 select (r.value || jsonb_build_object('sede',p.sede,'_closed',true)) as row_data
 from permitted p cross join lateral jsonb_array_elements(coalesce(p.datos->$2,'[]')) r where p.closure_id is not null
 union all
 select to_jsonb(x)||jsonb_build_object('sede',p.sede,'_closed',false) from public.%I x join permitted p on p.id_bodega=x."idBodega"
 where p.closure_id is null and x.%I=$1 and $1=(now() at time zone 'America/Tegucigalpa')::date
 union all
 select r.row_data||jsonb_build_object('sede',p.sede,'_closed',true) from permitted p cross join lateral (
 select distinct on (x.id) to_jsonb(x) as row_data from public.%I x
 where x."idBodega"=p.id_bodega and x.%I=$1 order by x.id,x.backup_fecha desc,x.backup_id desc
 ) r where p.closure_id is null and $1<>(now() at time zone 'America/Tegucigalpa')::date
 ) select coalesce(jsonb_agg(row_data),'[]') from (select row_data from selected order by row_data->>'idBodega',row_data->>'codigo',row_data->>'id' limit 500 offset $3) page
 $q$,live_table,date_column,backup_table,date_column) into result using p_fecha,p_dataset,greatest(0,coalesce(p_offset,0));
 return result;
end $$;
revoke all on function public.inventory_date_rows(date,text,int) from public,anon;
grant execute on function public.inventory_date_rows(date,text,int) to authenticated;
notify pgrst,'reload schema';

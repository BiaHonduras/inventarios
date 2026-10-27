import { supabase } from './supabase-config.js';

// ===== USUARIOS =====
export async function crearUsuario(usuario, correo, contraseña, rol) {
    try {
        const { data, error } = await supabase
            .from('usuarios')
            .insert([{
                usuario: usuario,
                correo: correo,
                contraseña: contraseña, // IMPORTANTE: Implementar hash en backend
                rol: rol
            }])
            .select();
        
        if (error) throw error;
        return { success: true, data };
    } catch (error) {
        console.error('Error al crear usuario:', error);
        return { success: false, error };
    }
}

export async function obtenerUsuarios() {
    try {
        const { data, error } = await supabase
            .from('usuarios')
            .select('*')
            .order('usuario', { ascending: true });
        
        if (error) throw error;
        return { success: true, data };
    } catch (error) {
        console.error('Error al obtener usuarios:', error);
        return { success: false, error };
    }
}

export async function eliminarUsuario(id) {
    try {
        const { error } = await supabase
            .from('usuarios')
            .delete()
            .eq('id', id);
        
        if (error) throw error;
        return { success: true };
    } catch (error) {
        console.error('Error al eliminar usuario:', error);
        return { success: false, error };
    }
}

// ===== SKUs (BASE DE CÓDIGOS) =====
export async function obtenerSKUs() {
    try {
        const { data, error } = await supabase
            .from('skus')
            .select('*');
        
        if (error) throw error;
        return { success: true, data };
    } catch (error) {
        console.error('Error al obtener SKUs:', error);
        return { success: false, error };
    }
}

export async function obtenerSKUPorCodigo(codigo) {
    try {
        const { data, error } = await supabase
            .from('skus')
            .select('*')
            .eq('código', codigo)
            .single();
        
        if (error && error.code !== 'PGRST116') throw error; // PGRST116 = no rows
        return { success: true, data };
    } catch (error) {
        console.error('Error al obtener SKU:', error);
        return { success: false, error };
    }
}

export async function importarSKUs(datos) {
    try {
        const { data, error } = await supabase
            .from('skus')
            .upsert(datos, { onConflict: 'código' });
        
        if (error) throw error;
        return { success: true, data };
    } catch (error) {
        console.error('Error al importar SKUs:', error);
        return { success: false, error };
    }
}

// ===== INVENTARIO REPORTERÍA =====
export async function obtenerInventarioReporteria() {
    try {
        const { data, error } = await supabase
            .from('inventario_reporteria')
            .select('*');
        
        if (error) throw error;
        return { success: true, data };
    } catch (error) {
        console.error('Error al obtener inventario reportería:', error);
        return { success: false, error };
    }
}

export async function importarInventarioReporteria(datos) {
    try {
        const { data, error } = await supabase
            .from('inventario_reporteria')
            .upsert(datos, { onConflict: 'código' });
        
        if (error) throw error;
        return { success: true, data };
    } catch (error) {
        console.error('Error al importar inventario reportería:', error);
        return { success: false, error };
    }
}

// ===== INVENTARIOS DIARIOS =====
export async function agregarArticuloInventario(articulo) {
    try {
        const { data, error } = await supabase
            .from('inventarios_diarios')
            .insert([{
                código: articulo.codigo,
                descripción: articulo.descripcion,
                proveedor: articulo.proveedor,
                masterpack: articulo.masterpack,
                codigo_barra: articulo.codigoBarras,
                cajas_fardos: articulo.cajasFardos,
                unidades: articulo.unidades,
                total: articulo.total
            }])
            .select();
        
        if (error) throw error;
        return { success: true, data };
    } catch (error) {
        console.error('Error al agregar artículo:', error);
        return { success: false, error };
    }
}

export async function obtenerInventariosActuales() {
    try {
        const { data, error } = await supabase
            .from('inventarios_diarios')
            .select('*')
            .order('created_at', { ascending: false });
        
        if (error) throw error;
        return { success: true, data };
    } catch (error) {
        console.error('Error al obtener inventarios:', error);
        return { success: false, error };
    }
}

export async function eliminarArticuloInventario(id) {
    try {
        const { error } = await supabase
            .from('inventarios_diarios')
            .delete()
            .eq('id', id);
        
        if (error) throw error;
        return { success: true };
    } catch (error) {
        console.error('Error al eliminar artículo:', error);
        return { success: false, error };
    }
}

export async function obtenerInventarioPorFecha(fecha) {
    try {
        const { data, error } = await supabase
            .from('inventarios_diarios')
            .select('*')
            .eq('fecha', fecha);
        
        if (error) throw error;
        return { success: true, data };
    } catch (error) {
        console.error('Error al obtener inventario por fecha:', error);
        return { success: false, error };
    }
}

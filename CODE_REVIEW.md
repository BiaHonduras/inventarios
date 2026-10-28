# Revisión de Inventarios — 28 de octubre de 2026

## Cambios incluidos

- Logo BIA con el mismo fondo blanco, relleno y borde redondeado que Devoluciones.
- Una sola inicialización autenticada y una sola fuente de bodegas. El manejo de vencimiento usa `tipos_bodega.maneja_vencimiento` y el día configurado; se retiraron las versiones contradictorias que forzaban lunes o ignoraban PPV.
- Un solo manejador de guardado, bloqueo de envíos simultáneos y reintento sobre el mismo ID si falla el guardado complementario del vencimiento.
- Limpieza explícita del formulario, cancelación de búsquedas antiguas y conservación del contenido QR al editar un registro.
- Caché de lecturas de catálogo durante 30 segundos, paginación de consultas y reutilización del resultado del Resumen para sus indicadores y gráficos. El Dashboard secundario comparte tres lecturas en lugar de seis y no consulta la columna inexistente `proveedor` en las justificaciones.
- Parser CSV compartido con soporte de comillas escapadas, descripciones con comas y saltos de línea, BOM y separadores coma/punto y coma/tabulador.
- Escapado de texto importado al renderizar tablas. Limpieza de cámaras al salir y cancelación de un inicio de cámara que terminó después de detenerlo.
- Retirada de funciones de usuarios y formularios obsoletos, código de respaldo sin llamadas, validaciones duplicadas y código de demostración. `dashboard_p.html` conserva su URL mediante redirección al dashboard vigente; `inventario.js` y `supabase-funtions.js` no tenían referencias en las páginas activas.
- Rutas de entrada y retorno directas a `/intranet/intranet.html`. No se cambiaron las asignaciones de cuentas ni las reglas de acceso.

## Validación

`npm ci && npm test`

Las pruebas cubren el inicio de la página con datos ficticios, las bodegas Principal/PPV/PFN, el día de vencimiento, los dobles envíos y reintentos, el QR, la sesión, el CSV y la paginación. También se comprobó el diseño estático en Chromium a 375, 820 y 1440 píxeles, sin desbordamiento horizontal y con fondo blanco en el logo. No se usaron credenciales de usuarios reales ni se escribieron registros de inventario en producción durante las pruebas.

## Mejora pendiente de instalación en Supabase

La importación actual de reportería aún utiliza la función anterior de limpieza y luego inserta el archivo. Se añadió validación del archivo antes de ejecutar esa limpieza, pero esas dos operaciones no son una transacción.

Se preparó y probó por separado una RPC atómica que revierte la sustitución completa ante cualquier error. Su instalación fue impedida por el conector de Supabase con `Invalid or expired requestState`; por eso no se activó en la página publicada. La migración y el cambio de llamada se mantienen en una propuesta separada. Hasta aplicar esa mejora, se recomienda conservar el archivo de origen para reimportarlo si se interrumpe una carga.

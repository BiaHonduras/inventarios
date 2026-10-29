# Cierre automático e histórico

El servidor ejecuta el cierre a las 23:50, hora de Honduras, de lunes a sábado. No requiere un equipo encendido ni una página abierta. Los domingos se omiten. El trabajo de Supabase Cron se llama `inventory-close-honduras`; su horario UTC es `50 5 * * 0,2-6`.

Cada bodega con actividad del día conserva una instantánea completa y atómica de la base importada, los conteos diarios, las justificaciones fechadas y las filas originales del último Excel aplicado. Se conservan los SKU pendientes aunque no se haya registrado ningún conteo. Las justificaciones sin fecha se copian por separado como pendientes de identificar y permanecen en la tabla de trabajo; no se les asigna una fecha supuesta.

Tras conservar el respaldo se retiran exclusivamente los registros de esa fecha y bodega de las tablas de trabajo. La fecha queda bloqueada para nuevas capturas. La operación es idempotente. Los usuarios no pueden ejecutar el cierre manual.

`inventory_date_rows` consulta el cierre cuando existe. Para fechas anteriores sin un cierre nuevo consulta las tablas de backup existentes, conservando la última versión por registro. Para el día actual consulta las tablas de trabajo hasta el cierre. Las lecturas respetan los permisos de Inventarios y las bodegas/sedes autorizadas; se paginan de 500 en 500.

En Ver Inventario, sede y tipo de bodega se aplican al mismo conjunto de datos que utiliza la tabla y sus indicadores. Cada SKU se identifica por bodega y código. El porcentaje mide los SKU de la base que ya tienen conteo; no cuenta registros repetidos como productos adicionales.

Los detalles del histórico se pueden exportar a Excel, incluidas las justificaciones y la fuente Excel. Los campos de consulta empiezan en la fecha actual de Honduras.

Verificación: revisar `cron.job` y `cron.job_run_details`, y consultar el histórico después de las 23:50. Las pruebas de cierre se realizan en transacciones revertidas para conservar los datos operativos.

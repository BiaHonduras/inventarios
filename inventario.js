
// Función para convertir fecha de yyyy-mm-dd a dd/mm/yyyy
function formatearFecha(fechaISO) {
    const [año, mes, día] = fechaISO.split("-");
    return `${día}/${mes}/${año}`;
}

// Evento para agregar artículo al inventario
function agregarArticulo() {
    const fechaInput = document.getElementById("fecha").value;
    const fechaFormateada = formatearFecha(fechaInput);

    const tabla = document.getElementById("tablaInventario");
    const nuevaFila = tabla.insertRow(-1);

    const celdaFecha = nuevaFila.insertCell(0);
    celdaFecha.textContent = fechaFormateada;

    // Aquí puedes agregar más celdas si deseas incluir otros datos del artículo
}

// Esperar a que el DOM cargue para asignar eventos
window.onload = function() {
    const botonAgregar = document.getElementById("btnAgregarArticulo");
    if (botonAgregar) {
        botonAgregar.addEventListener("click", agregarArticulo);
    }
};

using System.ComponentModel.DataAnnotations.Schema;

namespace OneGoalDiscover_Backend_AttendanceApi.Models
{
    // Fila cruda de pDSVRRHHauxiliarHorarioObtenerInformacion. Solo las columnas que usa la API;
    // las que la versión del SP en la BD no devuelva (cve_emp, c_permiso, c_nomina_cerrada...) quedan en su default.
    internal sealed class AttendanceRow
    {
        [Column("id_emp")] public int IdEmpleado { get; set; }
        [Column("cve_emp")] public string? ClaveEmpleado { get; set; }
        [Column("nom_cort")] public string? NombreEmpleado { get; set; }
        [Column("fec_ent")] public DateTime FechaEntrada { get; set; }
        [Column("turno")] public string? Turno { get; set; }

        [Column("hel")] public DateTime HorarioEntradaLaboral { get; set; }
        [Column("hic")] public DateTime HorarioSalidaComida { get; set; }
        [Column("hfc")] public DateTime HorarioEntradaComida { get; set; }
        [Column("hfl")] public DateTime HorarioSalidaLaboral { get; set; }

        [Column("hr_ent_lab")] public DateTime HoraEntradaLaboral { get; set; }
        [Column("codeV_i")] public string? TipoEntradaLaboral { get; set; }
        [Column("device_i")] public string? LugarEntradaLaboral { get; set; }
        [Column("hr_ini_com")] public DateTime HoraSalidaComida { get; set; }
        [Column("codeV_bl")] public string? TipoSalidaComida { get; set; }
        [Column("device_bl")] public string? LugarSalidaComida { get; set; }
        [Column("hr_fin_com")] public DateTime HoraEntradaComida { get; set; }
        [Column("codeV_el")] public string? TipoEntradaComida { get; set; }
        [Column("device_el")] public string? LugarEntradaComida { get; set; }
        [Column("hr_fin_lab")] public DateTime HoraFinLaboral { get; set; }
        [Column("codeV_o")] public string? TipoFinLaboral { get; set; }
        [Column("device_o")] public string? LugarFinLaboral { get; set; }

        [Column("tmr")] public int MinutosRetardo { get; set; }
        [Column("tma")] public int MinutosAnticipados { get; set; }
        [Column("hrs_prog")] public DateTime HorasProgramadas { get; set; }
        [Column("hrs_real")] public DateTime HorasTrabajadas { get; set; }
        [Column("HorasExtra")] public decimal HorasExtra { get; set; }

        [Column("fj")] public bool AusenciaJustificada { get; set; }
        [Column("fi")] public bool AusenciaInjustificada { get; set; }
        [Column("rcg")] public bool RetardoConGoce { get; set; }
        [Column("rsg")] public bool RetardoSinGoce { get; set; }
        [Column("vac")] public bool EsVacacion { get; set; }
        [Column("he_aut")] public bool HorasExtraAutorizadas { get; set; }
        [Column("id_tipo_incidencia_otro")] public int? IdTipoIncidenciaOtro { get; set; }
        [Column("fes")] public bool EsFestivo { get; set; }
        [Column("c_des")] public bool EsDescanso { get; set; }
        [Column("c_permiso")] public int Permiso { get; set; }

        // Mismas banderas de cierre que usa Discover: nómina cerrada (bloquea edición en pantalla)
        // y cierre manual del periodo (botón "Cerrar periodo").
        [Column("c_nomina_cerrada")] public bool NominaCerrada { get; set; }
        [Column("c_cerrado_manual")] public bool CerradoManual { get; set; }
    }

    internal sealed class EmployeeBranch
    {
        public int id_emp { get; set; }
        public int id_suc { get; set; }
    }
}

namespace OneGoalDiscover_Backend_AttendanceApi.Models
{
    /// <summary>Una checada (entrada, salida a comida, regreso de comida o salida).</summary>
    public class PunchDto
    {
        /// <summary>Fecha y hora de la checada.</summary>
        public DateTime Time { get; set; }

        /// <summary>Huella, Cara, Manual o Automática (null si se desconoce).</summary>
        public string? Type { get; set; }

        /// <summary>Código del dispositivo biométrico donde se checó.</summary>
        public string? DeviceCode { get; set; }
    }

    public class AttendanceRecordDto
    {
        public int EmployeeId { get; set; }
        public string? EmployeeCode { get; set; }
        public string? EmployeeName { get; set; }
        public DateOnly Date { get; set; }
        public string? Shift { get; set; }

        /// <summary>Horario programado (HH:mm); null si no aplica.</summary>
        public string? ScheduledEntry { get; set; }
        public string? ScheduledMealStart { get; set; }
        public string? ScheduledMealEnd { get; set; }
        public string? ScheduledExit { get; set; }

        /// <summary>Checadas registradas; null si no hubo.</summary>
        public PunchDto? CheckIn { get; set; }
        public PunchDto? MealOut { get; set; }
        public PunchDto? MealIn { get; set; }
        public PunchDto? CheckOut { get; set; }

        public int LateMinutes { get; set; }
        public int EarlyMinutes { get; set; }
        public string? ScheduledHours { get; set; }
        public string? WorkedHours { get; set; }
        public decimal OvertimeHours { get; set; }

        /// <summary>Tipo de incidencia (ej. Ausencia Justificada, Retardo con goce, Vacaciones); null si no hay.</summary>
        public string? IncidentType { get; set; }

        /// <summary>Festivo, Descanso, Vacación, Permiso o Normal.</summary>
        public string DayType { get; set; } = "Normal";

        /// <summary>true si este registro pertenece a una nómina/periodo cerrado y ya no se modifica.</summary>
        public bool IsClosed { get; set; }
    }

    public class AttendanceResponse
    {
        public DateOnly StartDate { get; set; }
        public DateOnly EndDate { get; set; }

        /// <summary>true si TODOS los registros del rango consultado están cerrados (false si no hay registros o alguno sigue abierto).</summary>
        public bool IsPeriodClosed { get; set; }

        public int ClosedRecords { get; set; }
        public int OpenRecords { get; set; }

        public int Page { get; set; }
        public int PageSize { get; set; }
        public int TotalRecords { get; set; }
        public List<AttendanceRecordDto> Records { get; set; } = [];
    }
}

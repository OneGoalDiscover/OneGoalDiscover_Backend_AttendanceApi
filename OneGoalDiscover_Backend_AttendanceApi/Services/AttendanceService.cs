using Dapper;
using OneGoalDiscover_Backend_AttendanceApi.Models;
using OneGoalDiscover_Helpers.System;
using OneGoalDiscover_Models.DTOs.RRHH.AttendanceControl.ScheduleAssistant;
using OneGoalDiscover_Utilities.System.Database.Interfaces;
using System.Globalization;

namespace OneGoalDiscover_Backend_AttendanceApi.Services
{
    public record AttendanceSession(string Cfg, short CompanyId, int BranchId, int UserId);

    public interface IAttendanceService
    {
        Task<AttendanceResponse> GetAttendanceAsync(AttendanceSession session, DateOnly startDate, DateOnly endDate, int? employeeId, int page, int pageSize);
    }

    public class AttendanceService(IDatabaseConnectionUtility databaseConnectionUtility, IConfiguration configuration) : IAttendanceService
    {
        // Ids fijos del catálogo de tipos de incidencia (sis_tip tipo=90); mismos que usa SchedulingAssitantMain.
        private const int AusenciaJustificadaId = 44001;
        private const int AusenciaInjustificadaId = 44002;
        private const int RetardoConGoceId = 44003;
        private const int RetardoSinGoceId = 44004;
        private const int HorasExtraSinCatalogoId = -1;

        private static readonly CompareInfo CompareInfo = CultureInfo.GetCultureInfo("es-MX").CompareInfo;

        public async Task<AttendanceResponse> GetAttendanceAsync(AttendanceSession session, DateOnly startDate, DateOnly endDate, int? employeeId, int page, int pageSize)
        {
            await new DatabaseHelper(databaseConnectionUtility).configureConnections(configuration["CFGsPath"] ?? string.Empty, session.Cfg, session.CompanyId);

            List<AttendanceRow> rows = await readRows(startDate, endDate, employeeId);
            rows = await filterByPermittedBranches(rows, session);

            List<IncidentTypeDTO> incidentTypes = await databaseConnectionUtility.getListAsync<IncidentTypeDTO>(configuration.Sp("pDSVRRHHauxiliarHorarioInformacionTipoIncidencias"), null, true);

            int closed = rows.Count(isClosed);
            List<AttendanceRecordDto> records = rows
                .Skip((page - 1) * pageSize).Take(pageSize)
                .Select(row => map(row, incidentTypes))
                .ToList();

            return new AttendanceResponse
            {
                StartDate = startDate,
                EndDate = endDate,
                IsPeriodClosed = rows.Count > 0 && closed == rows.Count,
                ClosedRecords = closed,
                OpenRecords = rows.Count - closed,
                Page = page,
                PageSize = pageSize,
                TotalRecords = rows.Count,
                Records = records
            };
        }

        private async Task<List<AttendanceRow>> readRows(DateOnly startDate, DateOnly endDate, int? employeeId)
        {
            // OJO: en la versión nueva del SP @pIdUser expande a los subordinados del empleado; por eso
            // se filtra con @pEmpleados y @pIdUser se deja en NULL.
            DynamicParameters parameters = new DynamicParameters();
            parameters.Add("@pIdUser", null);
            parameters.Add("@pFechaDe", startDate.ToString("yyyyMMdd"));
            parameters.Add("@pFechaA", endDate.ToString("yyyyMMdd"));
            parameters.Add("@pTipoNominas", string.Empty);
            parameters.Add("@pDepartamentos", string.Empty);
            parameters.Add("@pTurnos", string.Empty);
            parameters.Add("@pZonas", string.Empty);
            parameters.Add("@pEmpleados", employeeId?.ToString() ?? string.Empty);
            parameters.Add("@pIncidencias", string.Empty);
            parameters.Add("@pFaltantes", string.Empty);
            parameters.Add("@pEstatusIncidencias", string.Empty);

            return await databaseConnectionUtility.getListAsync<AttendanceRow>(configuration.Sp("pDSVRRHHauxiliarHorarioObtenerInformacion"), parameters, true);
        }

        // Misma seguridad por sucursal que la pantalla de Discover; si el login indicó una sucursal, además se limita a ella.
        private async Task<List<AttendanceRow>> filterByPermittedBranches(List<AttendanceRow> rows, AttendanceSession session)
        {
            DynamicParameters parameters = new DynamicParameters();
            parameters.Add("@pIdUsr", session.UserId);
            parameters.Add("@pIdCmp", session.CompanyId);
            List<BranchPermissionDTO> permitted = await databaseConnectionUtility.getListAsync<BranchPermissionDTO>(configuration.Sp("pDSVRRHHauxiliarHorarioInformacionSucursales"), parameters, true);

            HashSet<int> branches = (permitted ?? []).Select(branch => branch.idSuc).ToHashSet();
            if (session.BranchId > 0)
                branches.IntersectWith([session.BranchId]);
            if (branches.Count == 0)
                return [];

            List<EmployeeBranch> employeeBranches = await databaseConnectionUtility.getListAsync<EmployeeBranch>(configuration.Sp("pDSVRRHHauxiliarHorarioSucursalesEmpleado"));
            HashSet<int> employees = employeeBranches.Where(x => branches.Contains(x.id_suc)).Select(x => x.id_emp).ToHashSet();

            return rows.Where(row => employees.Contains(row.IdEmpleado)).ToList();
        }

        private static bool isClosed(AttendanceRow row) => row.NominaCerrada || row.CerradoManual;

        private static AttendanceRecordDto map(AttendanceRow row, List<IncidentTypeDTO> incidentTypes) => new()
        {
            EmployeeId = row.IdEmpleado,
            EmployeeCode = row.ClaveEmpleado,
            EmployeeName = row.NombreEmpleado,
            Date = DateOnly.FromDateTime(row.FechaEntrada),
            Shift = row.Turno is "-" ? null : row.Turno,
            ScheduledEntry = timeOfDay(row.HorarioEntradaLaboral),
            ScheduledMealStart = timeOfDay(row.HorarioSalidaComida),
            ScheduledMealEnd = timeOfDay(row.HorarioEntradaComida),
            ScheduledExit = timeOfDay(row.HorarioSalidaLaboral),
            CheckIn = punch(row.HoraEntradaLaboral, row.TipoEntradaLaboral, row.LugarEntradaLaboral),
            MealOut = punch(row.HoraSalidaComida, row.TipoSalidaComida, row.LugarSalidaComida),
            MealIn = punch(row.HoraEntradaComida, row.TipoEntradaComida, row.LugarEntradaComida),
            CheckOut = punch(row.HoraFinLaboral, row.TipoFinLaboral, row.LugarFinLaboral),
            LateMinutes = row.MinutosRetardo,
            EarlyMinutes = row.MinutosAnticipados,
            ScheduledHours = timeOfDay(row.HorasProgramadas),
            WorkedHours = timeOfDay(row.HorasTrabajadas),
            OvertimeHours = Math.Round(row.HorasExtra, 2),
            IncidentType = incidentText(row, incidentTypes),
            DayType = dayType(row),
            IsClosed = isClosed(row)
        };

        // Discover usa 00:00:00 como "sin dato" tanto en horarios como en checadas.
        private static string? timeOfDay(DateTime value) => value.TimeOfDay == TimeSpan.Zero ? null : value.ToString("HH:mm");

        private static PunchDto? punch(DateTime time, string? type, string? deviceCode) =>
            time.TimeOfDay == TimeSpan.Zero ? null : new PunchDto
            {
                Time = time,
                Type = punchType(type),
                DeviceCode = string.IsNullOrWhiteSpace(deviceCode) ? null : deviceCode
            };

        private static string? punchType(string? code) => code switch
        {
            null or "" or "0" => null,
            "1" => "Huella",
            "5" => "Manual",
            "15" => "Cara",
            "99" => "Automática",
            _ => code
        };

        private static string dayType(AttendanceRow row) =>
            row.EsFestivo ? "Festivo" : row.EsDescanso ? "Descanso" : row.EsVacacion ? "Vacación" : row.Permiso is 1 or 2 or 3 ? "Permiso" : "Normal";

        // Misma precedencia que ResolveTipoIncidenciaId de SchedulingAssitantMain (sin el caso de incapacidad por periodo).
        private static string? incidentText(AttendanceRow row, List<IncidentTypeDTO> incidentTypes)
        {
            bool partialPermit = row.Permiso == 2;
            int id =
                row.AusenciaJustificada && !partialPermit ? AusenciaJustificadaId :
                row.AusenciaInjustificada && !partialPermit ? AusenciaInjustificadaId :
                row.RetardoConGoce ? RetardoConGoceId :
                row.RetardoSinGoce ? RetardoSinGoceId :
                row.EsVacacion ? findTypeId(incidentTypes, "VACACION") ?? 0 :
                row.IdTipoIncidenciaOtro.HasValue ? row.IdTipoIncidenciaOtro.Value :
                row.HorasExtraAutorizadas ? findTypeId(incidentTypes, "HORA EXTRA", "HORAS EXTRA") ?? HorasExtraSinCatalogoId : 0;

            if (id == HorasExtraSinCatalogoId) return "Horas Extra";
            if (id == 0) return null;
            return incidentTypes.FirstOrDefault(type => type.id == id)?.descripcion;
        }

        private static int? findTypeId(List<IncidentTypeDTO> incidentTypes, params string[] texts) =>
            incidentTypes.FirstOrDefault(type => texts.Any(text =>
                CompareInfo.IndexOf(type.descripcion ?? string.Empty, text, CompareOptions.IgnoreCase | CompareOptions.IgnoreNonSpace) >= 0))?.id;
    }
}

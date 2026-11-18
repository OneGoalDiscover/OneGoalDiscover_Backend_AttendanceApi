using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using OneGoalDiscover_Backend_AttendanceApi.Models;
using OneGoalDiscover_Backend_AttendanceApi.Services;
using OneGoalDiscover_Utilities.System.Cryptographic;
using System.Security.Claims;

namespace OneGoalDiscover_Backend_AttendanceApi.Controllers
{
    [Route("api/[controller]")]
    [ApiController]
    [Authorize]
    public class AttendanceController(IAttendanceService attendanceService, IConfiguration configuration) : ControllerBase
    {
        private const int MaxPageSize = 5000;

        /// <summary>Consulta los registros de checadas por periodo, de todos los empleados o de uno.</summary>
        /// <param name="startDate">Fecha inicial (yyyy-MM-dd).</param>
        /// <param name="endDate">Fecha final (yyyy-MM-dd). El rango máximo lo define el servidor (31 días por defecto).</param>
        /// <param name="employeeId">Id del empleado (id_emp). Si se omite se consultan todos los que el usuario puede ver.</param>
        /// <param name="page">Página, desde 1.</param>
        /// <param name="pageSize">Registros por página (máx. 5000).</param>
        [HttpGet]
        [ProducesResponseType(typeof(AttendanceResponse), StatusCodes.Status200OK)]
        public async Task<IActionResult> Get([FromQuery] DateOnly startDate, [FromQuery] DateOnly endDate, [FromQuery] int? employeeId = null,
            [FromQuery] int page = 1, [FromQuery] int pageSize = 1000)
        {
            int maxRangeDays = configuration.GetValue<int?>("AttendanceApi:MaxRangeDays") ?? 31;

            if (startDate == default || endDate == default)
                return BadRequest(new { message = "startDate y endDate son obligatorios (yyyy-MM-dd)." });
            if (startDate > endDate)
                return BadRequest(new { message = "startDate no puede ser mayor que endDate." });
            if (endDate.DayNumber - startDate.DayNumber + 1 > maxRangeDays)
                return BadRequest(new { message = $"El rango máximo permitido es de {maxRangeDays} días." });
            if (employeeId is <= 0)
                return BadRequest(new { message = "employeeId inválido." });
            if (page < 1 || pageSize < 1 || pageSize > MaxPageSize)
                return BadRequest(new { message = $"page debe ser >= 1 y pageSize entre 1 y {MaxPageSize}." });

            AttendanceSession? session = readSession();
            if (session == null)
                return Unauthorized();

            return Ok(await attendanceService.GetAttendanceAsync(session, startDate, endDate, employeeId, page, pageSize));
        }

        private AttendanceSession? readSession()
        {
            string? cfg = User.FindFirstValue("cfg");
            if (string.IsNullOrEmpty(cfg)
                || !short.TryParse(User.FindFirstValue("idCompany"), out short companyId)
                || !int.TryParse(User.FindFirstValue("idBranch"), out int branchId)
                || !int.TryParse(User.FindFirstValue("idUser"), out int userId))
                return null;

            return new AttendanceSession(BouncyCastleUtility.decrypt(cfg), companyId, branchId, userId);
        }
    }
}

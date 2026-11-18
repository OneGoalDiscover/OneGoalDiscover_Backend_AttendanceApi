using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using OneGoalDiscover_Backend_AttendanceApi.Models;
using OneGoalDiscover_Backend_AttendanceApi.Services;

namespace OneGoalDiscover_Backend_AttendanceApi.Controllers
{
    [Route("api/[controller]")]
    [ApiController]
    public class AuthController(IAuthService authService) : ControllerBase
    {
        /// <summary>Genera el access token (60 min) y el refresh token (7 días).</summary>
        /// <remarks>Cfg, CompanyId y BranchId son opcionales; si se omiten se usan los configurados en el servidor.</remarks>
        [HttpPost("login")]
        [EnableRateLimiting("login")]
        [ProducesResponseType(typeof(LoginResponse), StatusCodes.Status200OK)]
        public async Task<IActionResult> Login([FromBody] LoginRequest request) => toActionResult(await authService.LoginAsync(request));

        /// <summary>Obtiene un access token nuevo con el refresh token, sin volver a mandar la contraseña.</summary>
        /// <remarks>
        /// Revalida al usuario en cada llamada: si ya caducó, perdió acceso a la empresa o sucursal, o cambió su contraseña, responde 401/409/403.
        /// El refresh token no se renueva: vence 7 días después del login y entonces hay que volver a iniciar sesión.
        /// </remarks>
        [HttpPost("refresh")]
        [EnableRateLimiting("login")]
        [ProducesResponseType(typeof(RefreshResponse), StatusCodes.Status200OK)]
        public async Task<IActionResult> Refresh([FromBody] RefreshRequest request) => toActionResult(await authService.RefreshAsync(request.RefreshToken));

        private IActionResult toActionResult(LoginResult result) => result.Status switch
        {
            LoginStatus.Success => Ok(result.Response),
            LoginStatus.InvalidCredentials => Unauthorized(new { message = "Usuario o contraseña incorrectos." }),
            LoginStatus.InvalidRefreshToken => Unauthorized(new { message = "Refresh token inválido, vencido o ya no vigente. Inicie sesión de nuevo." }),
            LoginStatus.UserExpired => Conflict(new { message = "El usuario ha caducado." }),
            LoginStatus.PasswordResetRequired => Conflict(new { message = "El usuario requiere establecer una nueva contraseña." }),
            LoginStatus.CompanyAccessDenied => StatusCode(StatusCodes.Status403Forbidden, new { message = "El usuario no tiene acceso a la empresa indicada." }),
            LoginStatus.BranchAccessDenied => StatusCode(StatusCodes.Status403Forbidden, new { message = "El usuario no tiene acceso a la sucursal indicada." }),
            _ => BadRequest(new { message = "Configuración, empresa o sucursal inválida." })
        };
    }
}

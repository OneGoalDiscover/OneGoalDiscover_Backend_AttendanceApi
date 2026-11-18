using System.ComponentModel.DataAnnotations;

namespace OneGoalDiscover_Backend_AttendanceApi.Models
{
    public class LoginRequest
    {
        /// <summary>Usuario de Discover.</summary>
        [Required, StringLength(10)]
        public string User { get; set; } = string.Empty;

        [Required, StringLength(100)]
        public string Password { get; set; } = string.Empty;

        /// <summary>Configuración (ambiente). Opcional: si se omite se usa la configurada en el servidor.</summary>
        [StringLength(50)]
        public string? Cfg { get; set; }

        /// <summary>Id de empresa. Opcional: si se omite se usa la configurada en el servidor.</summary>
        public short? CompanyId { get; set; }

        /// <summary>Id de sucursal. Opcional.</summary>
        public int? BranchId { get; set; }
    }

    public class RefreshRequest
    {
        /// <summary>Refresh token entregado por /api/auth/login.</summary>
        [Required, StringLength(4000)]
        public string RefreshToken { get; set; } = string.Empty;
    }

    /// <summary>Respuesta de /api/auth/refresh: solo un access token nuevo.</summary>
    public class RefreshResponse
    {
        public string AccessToken { get; set; } = string.Empty;
        public DateTime ExpiresAtUtc { get; set; }
        public string UserName { get; set; } = string.Empty;
    }

    /// <summary>Respuesta de /api/auth/login: access token y refresh token.</summary>
    public class LoginResponse : RefreshResponse
    {
        /// <summary>Úselo en /api/auth/refresh para obtener un access token nuevo sin volver a mandar la contraseña.</summary>
        public string RefreshToken { get; set; } = string.Empty;
        public DateTime RefreshExpiresAtUtc { get; set; }
    }

    public enum LoginStatus
    {
        Success,
        InvalidCredentials,
        InvalidRefreshToken,
        UserExpired,
        PasswordResetRequired,
        InvalidContext,
        CompanyAccessDenied,
        BranchAccessDenied
    }

    public class LoginResult
    {
        public LoginStatus Status { get; set; }
        public RefreshResponse? Response { get; set; }
    }
}

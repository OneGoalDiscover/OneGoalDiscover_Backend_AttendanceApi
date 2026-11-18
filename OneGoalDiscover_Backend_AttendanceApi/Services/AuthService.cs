using Dapper;
using Microsoft.IdentityModel.Tokens;
using OneGoalDiscover_Backend_AttendanceApi.Models;
using OneGoalDiscover_Helpers.System;
using OneGoalDiscover_Models.DTOs.Auth;
using OneGoalDiscover_Models.DTOs.Menu;
using OneGoalDiscover_Utilities.System;
using OneGoalDiscover_Utilities.System.Cryptographic;
using OneGoalDiscover_Utilities.System.Database.Interfaces;
using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;

namespace OneGoalDiscover_Backend_AttendanceApi.Services
{
    public interface IAuthService
    {
        Task<LoginResult> LoginAsync(LoginRequest request);
        Task<LoginResult> RefreshAsync(string refreshToken);
    }

    public class AuthService(IDatabaseConnectionUtility databaseConnectionUtility, IConfiguration configuration) : IAuthService
    {
        // El refresh token lleva otra audiencia: así el access token (audiencia normal) no sirve en /refresh
        // y el refresh token no sirve como Bearer en el resto de la API.
        private const string RefreshAudienceSuffix = ".refresh";

        public async Task<LoginResult> LoginAsync(LoginRequest request)
        {
            string cfg = string.IsNullOrWhiteSpace(request.Cfg) ? configuration["AttendanceApi:DefaultCfg"] ?? string.Empty : request.Cfg.Trim();
            short companyId = request.CompanyId is > 0 ? request.CompanyId.Value : configuration.GetValue<short>("AttendanceApi:DefaultCompanyId");
            int branchId = request.BranchId is > 0 ? request.BranchId.Value : configuration.GetValue<int>("AttendanceApi:DefaultBranchId");

            return await AuthenticateAsync(cfg, companyId, branchId, request.User,
                user => user.Contrasena == CypherUtility.encryptCypher(user.IdUsuario, request.User, request.Password.ToUpper()),
                LoginStatus.InvalidCredentials, issueRefreshToken: true);
        }

        public async Task<LoginResult> RefreshAsync(string refreshToken)
        {
            ClaimsPrincipal? principal = readRefreshToken(refreshToken);
            string? encryptedCfg = principal?.FindFirstValue("cfg");
            string? userName = principal?.FindFirstValue(ClaimTypes.Name);
            string? passwordFingerprint = principal?.FindFirstValue("pwd");

            if (principal == null || string.IsNullOrEmpty(encryptedCfg) || string.IsNullOrEmpty(userName) || string.IsNullOrEmpty(passwordFingerprint)
                || !short.TryParse(principal.FindFirstValue("idCompany"), out short companyId)
                || !int.TryParse(principal.FindFirstValue("idBranch"), out int branchId))
                return Fail(LoginStatus.InvalidRefreshToken);

            // Si el usuario cambió su contraseña, la huella ya no coincide y el refresh token deja de servir.
            return await AuthenticateAsync(BouncyCastleUtility.decrypt(encryptedCfg), companyId, branchId, userName,
                user => passwordFingerprintOf(user) == passwordFingerprint,
                LoginStatus.InvalidRefreshToken, issueRefreshToken: false);
        }

        // Validaciones comunes de login y refresh (mismas que el login de Discover). El usuario se revalida en cada refresh.
        private async Task<LoginResult> AuthenticateAsync(string cfg, short companyId, int branchId, string userName,
            Func<UserLogInDTO, bool> credentialsAreValid, LoginStatus invalidCredentialsStatus, bool issueRefreshToken)
        {
            string cfgsPath = configuration["CFGsPath"] ?? string.Empty;

            // El cfg se usa como nombre de carpeta: solo se aceptan los que existen en CFGs.
            string? validCfg = CFGUtility.getAvailableCFGPaths(cfgsPath)
                .Select(folder => folder.Name)
                .FirstOrDefault(name => string.Equals(name, cfg, StringComparison.OrdinalIgnoreCase));

            if (validCfg == null || companyId <= 0)
                return Fail(LoginStatus.InvalidContext);

            await new DatabaseHelper(databaseConnectionUtility).configureConnections(cfgsPath, validCfg, companyId);

            // El usuario se consulta en la MCP, igual que en el login de Discover.
            DynamicParameters userParameters = new DynamicParameters();
            userParameters.Add("@Usuario", userName);
            UserLogInDTO? user = await databaseConnectionUtility.getUniqueValueAsync<UserLogInDTO>(configuration.Sp("pDSV_CFG_Usuario"), userParameters, true, true);

            // Usuario inexistente, KIOSKO o credencial incorrecta responden igual para no revelar qué usuarios existen.
            if (user == null || OneGoalDiscover_Helpers.Auth.KioskToken.EsUsuarioKiosco(user.IdTipoUsuario))
                return Fail(invalidCredentialsStatus);

            if (user.EstaCaducado)
                return Fail(LoginStatus.UserExpired);

            if (string.IsNullOrEmpty(user.Contrasena))
                return Fail(LoginStatus.PasswordResetRequired);

            if (!credentialsAreValid(user))
                return Fail(invalidCredentialsStatus);

            DynamicParameters companyParameters = new DynamicParameters();
            companyParameters.Add("@Usuario", userName);
            List<UserCompanyDTO> companies = await databaseConnectionUtility.getListAsync<UserCompanyDTO>(sql: configuration.Sp("pDSV_CFG_ConfiguracionEmpresaUsuario"), parameters: companyParameters, useConsolidationDatabase: true);
            if (companies == null || !companies.Any(company => company.IdCompania == companyId))
                return Fail(LoginStatus.CompanyAccessDenied);

            if (branchId > 0)
            {
                DynamicParameters branchParameters = new DynamicParameters();
                branchParameters.Add("@Usuario", userName);
                List<BranchDTO> branches = await databaseConnectionUtility.getListAsync<BranchDTO>(sql: configuration.Sp("pDSV_CFG_ConfiguracionSucursalesUsuario"), parameters: branchParameters);
                if (branches == null || !branches.Any(branch => branch.idSucursal == branchId))
                    return Fail(LoginStatus.BranchAccessDenied);
            }

            return new LoginResult { Status = LoginStatus.Success, Response = issueTokens(user, validCfg, companyId, branchId, issueRefreshToken) };
        }

        private RefreshResponse issueTokens(UserLogInDTO user, string cfg, short companyId, int branchId, bool issueRefreshToken)
        {
            int accessMinutes = configuration.GetValue<int?>("Jwt:ExpirationMinutes") ?? 60;
            DateTime accessExpiresAtUtc = DateTime.UtcNow.AddMinutes(accessMinutes);

            List<Claim> claims =
            [
                new Claim("cfg", BouncyCastleUtility.encrypt(cfg)),
                new Claim("idCompany", companyId.ToString()),
                new Claim("idBranch", branchId.ToString()),
                new Claim("idUser", user.IdUsuario.ToString()),
                new Claim(ClaimTypes.Name, user.Usuario),
                new Claim(JwtRegisteredClaimNames.Jti, Guid.NewGuid().ToString())
            ];

            RefreshResponse response = issueRefreshToken ? new LoginResponse() : new RefreshResponse();
            response.AccessToken = buildToken(claims, configuration["Jwt:Audience"]!, accessExpiresAtUtc);
            response.ExpiresAtUtc = accessExpiresAtUtc;
            response.UserName = user.Nombre;

            if (response is LoginResponse loginResponse)
            {
                int refreshDays = configuration.GetValue<int?>("Jwt:RefreshExpirationDays") ?? 7;
                DateTime refreshExpiresAtUtc = DateTime.UtcNow.AddDays(refreshDays);

                claims.Add(new Claim("pwd", passwordFingerprintOf(user)));
                claims.RemoveAll(claim => claim.Type == JwtRegisteredClaimNames.Jti);
                claims.Add(new Claim(JwtRegisteredClaimNames.Jti, Guid.NewGuid().ToString()));

                loginResponse.RefreshToken = buildToken(claims, configuration["Jwt:Audience"] + RefreshAudienceSuffix, refreshExpiresAtUtc);
                loginResponse.RefreshExpiresAtUtc = refreshExpiresAtUtc;
            }

            return response;
        }

        // Huella de la contraseña guardada (no la contraseña): cambia cuando el usuario la cambia o se la resetean.
        private static string passwordFingerprintOf(UserLogInDTO user) =>
            Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(user.Contrasena)))[..32];

        private SymmetricSecurityKey signingKey() => new(Encoding.UTF8.GetBytes(configuration["Jwt:SecretKey"]!));

        private string buildToken(List<Claim> claims, string audience, DateTime expiresAtUtc) =>
            new JwtSecurityTokenHandler().WriteToken(new JwtSecurityToken(
                issuer: configuration["Jwt:Issuer"],
                audience: audience,
                claims: claims,
                notBefore: DateTime.UtcNow,
                expires: expiresAtUtc,
                signingCredentials: new SigningCredentials(signingKey(), SecurityAlgorithms.HmacSha256)));

        private ClaimsPrincipal? readRefreshToken(string refreshToken)
        {
            try
            {
                return new JwtSecurityTokenHandler().ValidateToken(refreshToken, new TokenValidationParameters
                {
                    ValidateIssuer = true,
                    ValidIssuer = configuration["Jwt:Issuer"],
                    ValidateAudience = true,
                    ValidAudience = configuration["Jwt:Audience"] + RefreshAudienceSuffix,
                    ValidateLifetime = true,
                    ClockSkew = TimeSpan.FromMinutes(1),
                    ValidateIssuerSigningKey = true,
                    IssuerSigningKey = signingKey()
                }, out _);
            }
            catch (Exception ex) when (ex is SecurityTokenException or ArgumentException)
            {
                return null;
            }
        }

        private static LoginResult Fail(LoginStatus status) => new LoginResult { Status = status };
    }
}

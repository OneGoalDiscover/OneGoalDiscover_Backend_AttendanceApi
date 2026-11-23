using Dapper;
using OneGoalDiscover_Models.DTOs.System;
using OneGoalDiscover_Utilities.System.Database;
using OneGoalDiscover_Utilities.System.Database.Interfaces;

namespace OneGoalDiscover_Backend_AttendanceApi.Services
{
    public static class SqlSchemaExtensions
    {
        // Esquema de los SPs: "dsv" en el ambiente de Discover; "dbo" en BDs donde aún no existe dsv (AttendanceApi:SqlSchema).
        public static string Sp(this IConfiguration configuration, string procedureName) =>
            $"[{configuration["AttendanceApi:SqlSchema"] ?? "dsv"}].[{procedureName}]";

        // Equivale a DatabaseHelper.configureConnections de OneGoalDiscover_Helpers, pero el SP de configuración de empresa
        // se llama con el esquema configurado: el helper compartido lo tiene fijo y no se debe depender de él (otro repositorio).
        public static async Task ConfigureConnectionsAsync(this IDatabaseConnectionUtility databaseUtility, IConfiguration configuration, string cfg, short companyId)
        {
            string cfgsPath = configuration["CFGsPath"] ?? string.Empty;

            databaseUtility.cfg = await TenantConnectionCache.getCfgAsync(cfgsPath, cfg);
            databaseUtility.cfg.transactionalDatabase = await TenantConnectionCache.getCompanyDatabaseAsync(cfgsPath, cfg, companyId, async () =>
            {
                DynamicParameters parameters = new DynamicParameters();
                parameters.Add("@IdCompania", companyId);

                CompanyConfigurationDTO? company = await databaseUtility.getUniqueValueAsync<CompanyConfigurationDTO>(configuration.Sp("pDSV_CFG_ConfiguracionEmpresa"), parameters, true, true);

                return company?.BaseDatos ?? throw new InvalidOperationException("No se encontró la configuración para la compañía especificada.");
            });
        }
    }
}

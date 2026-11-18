namespace OneGoalDiscover_Backend_AttendanceApi.Services
{
    public static class SqlSchemaExtensions
    {
        // Esquema de los SPs: "dsv" en el ambiente de Discover; "dbo" en BDs restauradas donde aún no existe dsv.
        public static string Sp(this IConfiguration configuration, string procedureName) =>
            $"[{configuration["AttendanceApi:SqlSchema"] ?? "dsv"}].[{procedureName}]";
    }
}

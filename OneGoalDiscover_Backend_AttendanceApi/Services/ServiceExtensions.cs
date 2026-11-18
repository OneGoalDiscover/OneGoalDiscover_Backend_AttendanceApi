using OneGoalDiscover_Utilities.System.Database;
using OneGoalDiscover_Utilities.System.Database.Interfaces;

namespace OneGoalDiscover_Backend_AttendanceApi.Services
{
    public static class ServiceExtensions
    {
        public static void AddApplicationServices(this IServiceCollection services)
        {
            services.AddScoped<IDatabaseConnectionUtility, DatabaseConnectionUtility>();
            services.AddScoped<IAuthService, AuthService>();
            services.AddScoped<IAttendanceService, AttendanceService>();
        }
    }
}

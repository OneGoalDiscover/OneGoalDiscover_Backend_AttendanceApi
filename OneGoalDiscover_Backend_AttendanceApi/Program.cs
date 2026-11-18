using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.IdentityModel.Tokens;
using Microsoft.OpenApi.Models;
using OneGoalDiscover_Backend_AttendanceApi.Services;
using System.Reflection;
using System.Threading.RateLimiting;
using System.Text;

var builder = WebApplication.CreateBuilder(args);

Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);

builder.Services.AddApplicationServices();
builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(options =>
{
    options.SwaggerDoc("v1", new OpenApiInfo
    {
        Title = "OneGoal Discover - API de Checadas",
        Version = "v1",
        Description = "Autenticación y consulta de registros de checadas por empleado y periodo."
    });

    options.AddSecurityDefinition(JwtBearerDefaults.AuthenticationScheme, new OpenApiSecurityScheme
    {
        Name = "Authorization",
        Description = "Token obtenido en /api/auth/login (solo el token, sin 'Bearer').",
        In = ParameterLocation.Header,
        Type = SecuritySchemeType.Http,
        Scheme = JwtBearerDefaults.AuthenticationScheme,
        BearerFormat = "JWT"
    });
    options.AddSecurityRequirement(new OpenApiSecurityRequirement
    {
        {
            new OpenApiSecurityScheme
            {
                Reference = new OpenApiReference { Type = ReferenceType.SecurityScheme, Id = JwtBearerDefaults.AuthenticationScheme }
            },
            Array.Empty<string>()
        }
    });

    string xmlPath = Path.Combine(AppContext.BaseDirectory, $"{Assembly.GetExecutingAssembly().GetName().Name}.xml");
    if (File.Exists(xmlPath))
        options.IncludeXmlComments(xmlPath);
});

// Llave, emisor y audiencia PROPIOS de esta API: un token de Discover no sirve aquí ni viceversa.
string secretKey = builder.Configuration["Jwt:SecretKey"] ?? string.Empty;
if (secretKey.Length < 32)
    throw new InvalidOperationException("Jwt:SecretKey debe tener al menos 32 caracteres.");

builder.Services.AddAuthentication(opt =>
{
    opt.DefaultAuthenticateScheme = JwtBearerDefaults.AuthenticationScheme;
    opt.DefaultChallengeScheme = JwtBearerDefaults.AuthenticationScheme;
})
.AddJwtBearer(opt =>
{
    opt.RequireHttpsMetadata = true;
    opt.TokenValidationParameters = new TokenValidationParameters
    {
        ValidateIssuer = true,
        ValidateAudience = true,
        ValidateLifetime = true,
        ValidateIssuerSigningKey = true,
        // Esta misma API emite y valida los tokens, no hay desfase de relojes que tolerar: vence exactamente en exp.
        ClockSkew = TimeSpan.Zero,
        ValidIssuer = builder.Configuration["Jwt:Issuer"],
        ValidAudience = builder.Configuration["Jwt:Audience"],
        IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(secretKey))
    };
});
builder.Services.AddAuthorization();

// Límite de intentos de login por IP (el login de Discover no lo tiene y aquí se expone a internet).
builder.Services.AddRateLimiter(options =>
{
    options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
    options.AddPolicy("login", httpContext => RateLimitPartition.GetFixedWindowLimiter(
        httpContext.Connection.RemoteIpAddress?.ToString() ?? "unknown",
        _ => new FixedWindowRateLimiterOptions { PermitLimit = 10, Window = TimeSpan.FromMinutes(1) }));
});

var app = builder.Build();

// El cliente necesita el Swagger, por eso se publica en todos los ambientes.
app.UseSwagger();
app.UseSwaggerUI();

app.UseHttpsRedirection();

app.UseRateLimiter();
app.UseAuthentication();
app.UseAuthorization();

app.MapControllers();

app.Run();

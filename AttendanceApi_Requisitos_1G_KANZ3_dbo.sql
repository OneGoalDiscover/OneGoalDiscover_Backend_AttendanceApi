/*
    AttendanceApi - Requisitos de BD para 1G_KANZ3 (esquema dbo)
    ---------------------------------------------------------------------------------------------
    Alcance: SOLO lo que necesita OneGoalDiscover_Backend_AttendanceApi (login + GET /api/attendance).

    Origen de los SPs: repo 1G_ATM-Estructura.
    Rollback: al final del archivo (comentado).

    Contenido:
      1. rh_hr_hst: 6 columnas nuevas      | cat_hor: 2 columnas nuevas
      2. dbo.tDSV_VAC_tipos_ausencia       (tabla; la lee el SP de checadas)
      3. dbo.vDSV_VAC_ausencias_autorizadas (VISTA TEMPORAL VACIA - ver nota)
      4. 5 SPs: ObtenerInformacion, InformacionTipoIncidencias, InformacionSucursales,
                SucursalesEmpleado, pDSV_CFG_ConfiguracionSucursalesUsuario
      5. Verificacion (solo lectura)
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

-- Guarda de seguridad: cambia el nombre solo si es intencional.
IF DB_NAME() <> N'1G_KANZ3'
BEGIN
    DECLARE @msg NVARCHAR(200) = N'Base de datos incorrecta: ' + DB_NAME() + N'. Este script es para 1G_KANZ3. No se ejecutara nada.';
    RAISERROR(@msg, 16, 1);
    SET NOEXEC ON;
END
GO
PRINT N'Ejecutando en: ' + DB_NAME();
GO

-- ====================================================================================================
-- 1. Columnas nuevas (rh_hr_hst, cat_hor)
-- ====================================================================================================

IF COL_LENGTH(N'dbo.rh_hr_hst', N'c_permiso') IS NULL
    ALTER TABLE dbo.rh_hr_hst ADD c_permiso TINYINT      NOT NULL CONSTRAINT DF_rh_hr_hst_c_permiso DEFAULT (0);
GO
IF COL_LENGTH(N'dbo.rh_hr_hst', N'he_aut') IS NULL
    ALTER TABLE dbo.rh_hr_hst ADD he_aut BIT          NOT NULL CONSTRAINT DF_rh_hr_hst_he_aut DEFAULT (0);
GO
IF COL_LENGTH(N'dbo.rh_hr_hst', N'id_estatus_incidencia') IS NULL
    ALTER TABLE dbo.rh_hr_hst ADD id_estatus_incidencia INT          NOT NULL CONSTRAINT DF_rh_hr_hst_id_estatus_incidencia DEFAULT (0);
GO
IF COL_LENGTH(N'dbo.rh_hr_hst', N'c_cerrado_manual') IS NULL
    ALTER TABLE dbo.rh_hr_hst ADD c_cerrado_manual BIT          NOT NULL CONSTRAINT DF_rh_hr_hst_c_cerrado_manual DEFAULT (0);
GO
IF COL_LENGTH(N'dbo.rh_hr_hst', N'id_tipo_incidencia_otro') IS NULL
    ALTER TABLE dbo.rh_hr_hst ADD id_tipo_incidencia_otro INT          NULL;
GO
IF COL_LENGTH(N'dbo.rh_hr_hst', N'he_manual') IS NULL
    ALTER TABLE dbo.rh_hr_hst ADD he_manual DECIMAL(5,2) NULL;
GO
IF COL_LENGTH(N'dbo.cat_hor', N'criterio') IS NULL
    ALTER TABLE dbo.cat_hor ADD criterio TINYINT      NOT NULL CONSTRAINT DF_cat_hor_criterio DEFAULT (0);
GO
IF COL_LENGTH(N'dbo.cat_hor', N'sin_checadas') IS NULL
    ALTER TABLE dbo.cat_hor ADD sin_checadas BIT          NOT NULL CONSTRAINT DF_cat_hor_sin_checadas DEFAULT (0);
GO

-- ====================================================================================================
-- 2. dbo.tDSV_VAC_tipos_ausencia
-- ====================================================================================================

IF OBJECT_ID(N'dbo.tDSV_VAC_tipos_ausencia', N'U') IS NULL
BEGIN
CREATE TABLE dbo.tDSV_VAC_tipos_ausencia
(
    id_tipo_ausencia       INT IDENTITY(1,1) NOT NULL,
    nombre                 NVARCHAR(100) NOT NULL,
    unidad                 CHAR(1) NOT NULL CONSTRAINT DF_tDSV_VAC_tipos_ausencia_unidad DEFAULT ('D'),
    consume_saldo          BIT NOT NULL CONSTRAINT DF_tDSV_VAC_tipos_ausencia_consume_saldo DEFAULT (0),
    tratamiento_pago       CHAR(1) NOT NULL CONSTRAINT DF_tDSV_VAC_tipos_ausencia_tratamiento_pago DEFAULT ('P'),
    recuperar              BIT NOT NULL CONSTRAINT DF_tDSV_VAC_tipos_ausencia_recuperar DEFAULT (0),
    tipo_permiso           CHAR(1) NOT NULL CONSTRAINT DF_tDSV_VAC_tipos_ausencia_tipo_permiso DEFAULT ('P'),
    id_tipo_incidencia     INT NULL,
    pide_motivo            BIT NOT NULL CONSTRAINT DF_tDSV_VAC_tipos_ausencia_pide_motivo DEFAULT (0),
    requiere_autorizacion  BIT NOT NULL CONSTRAINT DF_tDSV_VAC_tipos_ausencia_requiere_autorizacion DEFAULT (1),
    autoriza_jefe          BIT NOT NULL CONSTRAINT DF_tDSV_VAC_tipos_ausencia_autoriza_jefe DEFAULT (1),
    autoriza_rh            BIT NOT NULL CONSTRAINT DF_tDSV_VAC_tipos_ausencia_autoriza_rh DEFAULT (0),
    id_usr_autoriza_adic   INT NULL,
    color                  CHAR(7) NULL,
    habilitado             BIT NOT NULL CONSTRAINT DF_tDSV_VAC_tipos_ausencia_habilitado DEFAULT (1),
    created_by             INT NOT NULL,
    created_at             DATETIME NOT NULL CONSTRAINT DF_tDSV_VAC_tipos_ausencia_created_at DEFAULT (GETDATE()),
    updated_by             INT NULL,
    updated_at             DATETIME NULL,
    dias_anticipacion      SMALLINT NOT NULL CONSTRAINT DF_tDSV_VAC_tipos_ausencia_dias_anticipacion DEFAULT (0),
    CONSTRAINT CK_tDSV_VAC_tipos_ausencia_unidad CHECK (unidad IN ('D', 'M', 'H')),
    CONSTRAINT CK_tDSV_VAC_tipos_ausencia_tratamiento_pago CHECK (tratamiento_pago IN ('P', 'N', 'C', 'I')),
    CONSTRAINT CK_tDSV_VAC_tipos_ausencia_tipo_permiso CHECK (tipo_permiso IN ('V', 'P')),
    CONSTRAINT PK_tDSV_VAC_tipos_ausencia PRIMARY KEY (id_tipo_ausencia)
);
END
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_tDSV_VAC_tipos_ausencia_nombre' AND object_id = OBJECT_ID(N'dbo.tDSV_VAC_tipos_ausencia'))
BEGIN
CREATE UNIQUE INDEX UX_tDSV_VAC_tipos_ausencia_nombre ON dbo.tDSV_VAC_tipos_ausencia (nombre) WHERE habilitado = 1;
END
GO
GO

-- ====================================================================================================
-- 3. dbo.vDSV_VAC_ausencias_autorizadas (VISTA TEMPORAL VACIA, ver nota del encabezado)
-- ====================================================================================================

IF OBJECT_ID(N'dbo.vDSV_VAC_ausencias_autorizadas', N'V') IS NULL
    EXEC (N'
CREATE VIEW dbo.vDSV_VAC_ausencias_autorizadas
AS
-- TEMPORAL: vista vacia con las mismas columnas que la real. Reemplazar al desplegar el modulo de Vacaciones.
SELECT
    CAST(NULL AS INT)           AS id_emp,
    CAST(NULL AS DATE)          AS fecha,
    CAST(NULL AS INT)           AS id_ausencia,
    CAST(NULL AS INT)           AS id_tipo_ausencia,
    CAST(NULL AS NVARCHAR(100)) AS tipo_ausencia,
    CAST(NULL AS CHAR(1))       AS unidad,
    CAST(NULL AS DECIMAL(5,2))  AS dias,
    CAST(NULL AS TIME)          AS hr_ini,
    CAST(NULL AS TIME)          AS hr_fin,
    CAST(NULL AS BIT)           AS consume_saldo,
    CAST(NULL AS CHAR(1))       AS tratamiento_pago,
    CAST(NULL AS BIT)           AS recuperar,
    CAST(NULL AS CHAR(1))       AS tipo_permiso,
    CAST(NULL AS INT)           AS id_tipo_incidencia,
    CAST(NULL AS NVARCHAR(200)) AS tipo_incidencia,
    CAST(NULL AS DATE)          AS fec_ini,
    CAST(NULL AS DATE)          AS fec_fin,
    CAST(NULL AS DATE)          AS fec_regreso
WHERE 1 = 0;');
GO

-- ====================================================================================================
-- 4. Stored procedures (dbo)
-- ====================================================================================================

-- Origen: dbo\Stored Procedures\pDSVRRHHauxiliarHorarioSucursalesEmpleado.sql
CREATE OR ALTER PROCEDURE [dbo].[pDSVRRHHauxiliarHorarioSucursalesEmpleado]
AS
BEGIN
    SET NOCOUNT ON;

    SELECT id_emp, id_suc
    FROM dbo.cat_emp WITH (NOLOCK);
END
GO

-- Origen: dbo\Stored Procedures\pDSVRRHHauxiliarHorarioInformacionSucursales.sql
CREATE OR ALTER PROCEDURE [dbo].[pDSVRRHHauxiliarHorarioInformacionSucursales]
    @pIdUsr INT,
    @pIdCmp INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT DISTINCT spa.nIdSucursal AS id_suc
    FROM SIRAdmin.SIRA_12_PRIVILEGIOS_USU_SUC AS permiso
    INNER JOIN SIR.SIR_71_SUCURSAL_PATENTE_ADUANA AS spa
        ON spa.nIdSucPatAdu71 = permiso.nIdSucPatAdu71
    INNER JOIN dbo.mcp_suc AS sucursal
        ON sucursal.id_suc = spa.nIdSucursal
    WHERE permiso.nIdUsuario = @pIdUsr
      AND permiso.bAccesar = 1
      AND sucursal.id_cmp = @pIdCmp
      AND sucursal.status = 1;
END
GO

-- Origen: dbo\Stored Procedures\pDSVRRHHauxiliarHorarioInformacionTipoIncidencias.sql
CREATE OR ALTER PROCEDURE [dbo].[pDSVRRHHauxiliarHorarioInformacionTipoIncidencias]
AS SET NOCOUNT ON
BEGIN TRY

	-- Antes era una lista fija (1-5). Ahora lee del catálogo real que ya usa Valeria para mantener
	-- estos conceptos (confirmado con ella): dbo.sis_tip, tipo=90. Los id_tip que llegan de aquí
	-- (44001, 44002, etc., no 1-5) se mapean a los booleanos reales en el frontend
	-- (SchedulingAssitantMain.razor.cs, onIncidentTypeChanged) -- si se agrega/quita un registro aquí,
	-- ese mapeo hay que revisarlo también.
	SELECT id_tip, des
	FROM dbo.sis_tip WITH (NOLOCK)
	WHERE tipo = 90 AND status = 1
	ORDER BY id_tip

END TRY
BEGIN CATCH
    DECLARE @ErrorMessage AS NVARCHAR(400)
    DECLARE @ErrorNumber AS INT
    DECLARE @ErrorSeverity AS INT
    DECLARE @ErrorState AS INT
    DECLARE @ErrorLine AS INT
    DECLARE @ErrorProcedure AS VARCHAR(100)
    SELECT  @ErrorNumber = ERROR_NUMBER(), @ErrorSeverity = ERROR_SEVERITY(), @ErrorState = 2, @ErrorLine = ERROR_LINE(), @ErrorProcedure = ISNULL(ERROR_PROCEDURE(), '-');
    SELECT @ErrorMessage = ERROR_MESSAGE();
    RAISERROR (@ErrorMessage, 16, 1, @ErrorNumber, @ErrorSeverity, @ErrorState)
END CATCH
GO

-- Origen: dbo\Stored Procedures\pDSVRRHHauxiliarHorarioObtenerInformacion.sql
-- CREATE PROCEDURE [dbo].[pDSVRRHHauxiliarHorarioObtenerInformacion]
CREATE OR ALTER PROCEDURE [dbo].[pDSVRRHHauxiliarHorarioObtenerInformacion]
@pIdUser AS INT = NULL,
@pFechaDe AS DATETIME,
@pFechaA AS DATETIME,
@pTipoNominas AS VARCHAR(MAX) = '',
@pDepartamentos AS VARCHAR(MAX) = '',
@pTurnos AS VARCHAR(MAX) = '',
@pZonas AS VARCHAR(MAX) = '',
@pEmpleados AS VARCHAR(MAX) = '',
@pIncidencias AS VARCHAR(MAX) = '',
@pFaltantes AS VARCHAR(MAX) = '',
@pEstatusIncidencias AS VARCHAR(MAX) = '',
@pIdUsr AS INT = NULL,
@pIdCmp AS INT = NULL,
@pSucursales AS VARCHAR(MAX) = ''
AS SET NOCOUNT ON
BEGIN TRY

	-- id_tip de Vacaciones es autonumérico (varía por ambiente); se resuelve en vivo.
	-- Los demás (44001-44006) son inserts con id fijo. El combo envía id_tip reales; también
	-- se mantiene compatibilidad con los códigos legacy 1-5 por si acaso.
	DECLARE @IdTipVacaciones INT = ISNULL(
		(SELECT TOP 1 id_tip FROM dbo.sis_tip WITH(NOLOCK) WHERE tipo = 90 AND status = 1 AND des LIKE '%VACAC%'),
		0
	)

	DECLARE @SoloAJ  AS INT = CASE WHEN EXISTS(SELECT 1 FROM STRING_SPLIT(@pIncidencias, ',') WHERE TRY_CAST(value AS INT) IN (1, 44001)) THEN 1 ELSE 0 END
	DECLARE @SoloVAC AS INT = CASE WHEN EXISTS(SELECT 1 FROM STRING_SPLIT(@pIncidencias, ',') WHERE TRY_CAST(value AS INT) = @IdTipVacaciones AND @IdTipVacaciones > 0) THEN 1 ELSE 0 END
	DECLARE @SoloAI  AS INT = CASE WHEN EXISTS(SELECT 1 FROM STRING_SPLIT(@pIncidencias, ',') WHERE TRY_CAST(value AS INT) IN (2, 44002)) THEN 1 ELSE 0 END
	DECLARE @SoloRCG AS INT = CASE WHEN EXISTS(SELECT 1 FROM STRING_SPLIT(@pIncidencias, ',') WHERE TRY_CAST(value AS INT) IN (3, 44003)) THEN 1 ELSE 0 END
	DECLARE @SoloRSG AS INT = CASE WHEN EXISTS(SELECT 1 FROM STRING_SPLIT(@pIncidencias, ',') WHERE TRY_CAST(value AS INT) IN (4, 44004)) THEN 1 ELSE 0 END
	DECLARE @SoloHE  AS INT = CASE WHEN EXISTS(SELECT 1 FROM STRING_SPLIT(@pIncidencias, ',') WHERE TRY_CAST(value AS INT) = 5)             THEN 1 ELSE 0 END

	DECLARE @umbral_dobles  INT = ISNULL((SELECT TOP 1 CAST(Valor AS INT) FROM dbo.cfg_global WITH(NOLOCK) WHERE id_cfg_glb = 725), 0)
	DECLARE @umbral_triples INT = ISNULL((SELECT TOP 1 CAST(Valor AS INT) FROM dbo.cfg_global WITH(NOLOCK) WHERE id_cfg_glb = 726), 0)

	DECLARE @SRE  AS INT = (SELECT CASE WHEN ISNULL(value, 0) = 0 THEN 0 ELSE 1 END FROM STRING_SPLIT(@pFaltantes, ',') WHERE value = 1)
	DECLARE @SRS  AS INT = (SELECT CASE WHEN ISNULL(value, 0) = 0 THEN 0 ELSE 1 END FROM STRING_SPLIT(@pFaltantes, ',') WHERE value = 2)
	DECLARE @SRSC AS INT = (SELECT CASE WHEN ISNULL(value, 0) = 0 THEN 0 ELSE 1 END FROM STRING_SPLIT(@pFaltantes, ',') WHERE value = 3)
	DECLARE @SREC AS INT = (SELECT CASE WHEN ISNULL(value, 0) = 0 THEN 0 ELSE 1 END FROM STRING_SPLIT(@pFaltantes, ',') WHERE value = 4)

	;WITH Jerarquia AS (
		SELECT id_emp
		FROM cat_emp WITH (NOLOCK)
		WHERE id_emp = @pIdUser
		UNION ALL
		SELECT e.id_emp
		FROM cat_emp e WITH (NOLOCK)
		INNER JOIN Jerarquia j ON e.id_emp_jefe = j.id_emp
		WHERE e.status = 1
	)

	SELECT rhh.id_hr_hst, rhh.id_emp, ce.cve_emp, rhh.id_usr, rhh.fec_ent, ce.nom_cort, cd.des AS departamento, rhh.c_tur, cz.des_zon AS zona, cp.des AS puesto, ccfd.curp AS registroPatronal, rhh.hel, rhh.hic, rhh.hfc, rhh.hfl, rhh.status,
		ISNULL(cu.nom, '') AS ultimoUsuarioEdicion,
		CASE (DATEPART(dw, rhh.fec_ent) + @@DATEFIRST - 2) % 7 WHEN 0 THEN 'L' WHEN 1 THEN 'M' WHEN 2 THEN 'X' WHEN 3 THEN 'J' WHEN 4 THEN 'V' WHEN 5 THEN 'S' WHEN 6 THEN 'D' END AS diaEntrada, rhh.fec_ent,
		CASE (DATEPART(dw, rhh.fec_sal) + @@DATEFIRST - 2) % 7 WHEN 0 THEN 'L' WHEN 1 THEN 'M' WHEN 2 THEN 'X' WHEN 3 THEN 'J' WHEN 4 THEN 'V' WHEN 5 THEN 'S' WHEN 6 THEN 'D' END AS diaSalida, rhh.fec_sal,
		CASE rhh.id_turno WHEN 1 THEN 'Matutino' WHEN 2 THEN 'Vespertino' WHEN 3 THEN 'Nocturno' WHEN 4 THEN 'Mixto' WHEN 5 THEN 'Rotar' ELSE '-' END AS turno, rhh.hr_ent_lab, rhh.codeV_i, rhh.device_i,
		rhh.hr_ini_com, rhh.codeV_bl, rhh.device_bl, rhh.hr_fin_com, rhh.codeV_el, rhh.device_el, rhh.hr_fin_lab, rhh.codeV_o, rhh.device_o, (rhh.mre/60) AS mre, (rhh.mrc/60) AS mrc, (rhh.mre/60) + (rhh.mrc/60) AS tmr,
		(rhh.mae/60) AS mae, (rhh.mac/60) AS mac, (mds/60) AS mds, (rhh.mae/60) + (rhh.mac/60) + (mds/60) AS tma, ce.tip_nomina, st_nom.des AS periodo_nomina,

		rhh.hrs_real,
		ch.min_ret_lab,
		ch.min_ret_com,

		ISNULL(
			CASE WHEN rhh.hr_fin_lab IS NULL OR CAST(rhh.hr_fin_lab AS TIME) = '00:00:00' THEN 0
			-- Sin checada de salida no se reconocen horas extras calculadas.
			ELSE CASE ch.criterio
				WHEN 2 THEN
					CASE WHEN CAST(rhh.hr_ent_lab AS TIME) <> '00:00:00'
					          AND CAST(rhh.hr_ent_lab AS TIME) < CAST(rhh.hel AS TIME)
					          AND DATEDIFF(MINUTE, CAST(rhh.hr_ent_lab AS TIME), CAST(rhh.hel AS TIME)) >= ISNULL(ch.min_te_lab, 0)
						 THEN DATEDIFF(MINUTE, CAST(rhh.hr_ent_lab AS TIME), CAST(rhh.hel AS TIME)) / 60.0
						 ELSE 0 END
				WHEN 3 THEN
					CASE WHEN CAST(rhh.hr_ent_lab AS TIME) <> '00:00:00' AND CAST(rhh.hr_ent_lab AS TIME) <= CAST(rhh.hel AS TIME)
					          AND CAST(rhh.hr_ini_com AS TIME) <> '00:00:00' AND CAST(rhh.hr_fin_com AS TIME) <> '00:00:00'
					          AND DATEDIFF(MINUTE, CAST(rhh.hr_ini_com AS TIME), CAST(rhh.hr_fin_com AS TIME)) < DATEDIFF(MINUTE, CAST(rhh.hic AS TIME), CAST(rhh.hfc AS TIME))
					          AND (DATEDIFF(MINUTE, CAST(rhh.hic AS TIME), CAST(rhh.hfc AS TIME)) - DATEDIFF(MINUTE, CAST(rhh.hr_ini_com AS TIME), CAST(rhh.hr_fin_com AS TIME))) >= ISNULL(ch.min_te_lab, 0)
						 THEN (DATEDIFF(MINUTE, CAST(rhh.hic AS TIME), CAST(rhh.hfc AS TIME)) - DATEDIFF(MINUTE, CAST(rhh.hr_ini_com AS TIME), CAST(rhh.hr_fin_com AS TIME))) / 60.0
						 ELSE 0 END
				WHEN 4 THEN
					CASE WHEN CAST(rhh.hr_ent_lab AS TIME) <> '00:00:00' AND CAST(rhh.hr_ent_lab AS TIME) <= CAST(rhh.hel AS TIME)
					          AND CAST(rhh.hr_fin_lab AS TIME) <> '00:00:00'
					          AND CAST(rhh.hr_fin_lab AS TIME) > CAST(rhh.hfl AS TIME)
					          AND DATEDIFF(MINUTE, CAST(rhh.hfl AS TIME), CAST(rhh.hr_fin_lab AS TIME)) >= ISNULL(ch.min_te_lab, 0)
						 THEN DATEDIFF(MINUTE, CAST(rhh.hfl AS TIME), CAST(rhh.hr_fin_lab AS TIME)) / 60.0
						 ELSE 0 END
				WHEN 1 THEN
					(CASE WHEN CAST(rhh.hr_ent_lab AS TIME) <> '00:00:00' AND CAST(rhh.hr_ent_lab AS TIME) < CAST(rhh.hel AS TIME) AND DATEDIFF(MINUTE, CAST(rhh.hr_ent_lab AS TIME), CAST(rhh.hel AS TIME)) >= ISNULL(ch.min_te_lab, 0) THEN DATEDIFF(MINUTE, CAST(rhh.hr_ent_lab AS TIME), CAST(rhh.hel AS TIME)) / 60.0 ELSE 0 END) +
					(CASE WHEN CAST(rhh.hr_ent_lab AS TIME) <> '00:00:00' AND CAST(rhh.hr_ent_lab AS TIME) <= CAST(rhh.hel AS TIME) AND CAST(rhh.hr_ini_com AS TIME) <> '00:00:00' AND CAST(rhh.hr_fin_com AS TIME) <> '00:00:00' AND DATEDIFF(MINUTE, CAST(rhh.hr_ini_com AS TIME), CAST(rhh.hr_fin_com AS TIME)) < DATEDIFF(MINUTE, CAST(rhh.hic AS TIME), CAST(rhh.hfc AS TIME)) AND (DATEDIFF(MINUTE, CAST(rhh.hic AS TIME), CAST(rhh.hfc AS TIME)) - DATEDIFF(MINUTE, CAST(rhh.hr_ini_com AS TIME), CAST(rhh.hr_fin_com AS TIME))) >= ISNULL(ch.min_te_lab, 0) THEN (DATEDIFF(MINUTE, CAST(rhh.hic AS TIME), CAST(rhh.hfc AS TIME)) - DATEDIFF(MINUTE, CAST(rhh.hr_ini_com AS TIME), CAST(rhh.hr_fin_com AS TIME))) / 60.0 ELSE 0 END) +
					(CASE WHEN CAST(rhh.hr_ent_lab AS TIME) <> '00:00:00' AND CAST(rhh.hr_ent_lab AS TIME) <= CAST(rhh.hel AS TIME) AND CAST(rhh.hr_fin_lab AS TIME) <> '00:00:00' AND CAST(rhh.hr_fin_lab AS TIME) > CAST(rhh.hfl AS TIME) AND DATEDIFF(MINUTE, CAST(rhh.hfl AS TIME), CAST(rhh.hr_fin_lab AS TIME)) >= ISNULL(ch.min_te_lab, 0) THEN DATEDIFF(MINUTE, CAST(rhh.hfl AS TIME), CAST(rhh.hr_fin_lab AS TIME)) / 60.0 ELSE 0 END)
				ELSE 0
			END END, 0) AS HorasExtra,
        rhh.he_manual,

		CASE
			    -- Las horas dobles/triples reflejan lo autorizado por RH, no los acumulados mae/mac/mds.
			    WHEN ce.ori_hext NOT IN (2, 3) OR ISNULL(rhh.he_manual, 0) <= 0 OR @umbral_dobles <= 0 THEN 0
			    WHEN @umbral_triples > 0 AND @umbral_triples < @umbral_dobles THEN 0
			    WHEN rhh.he_manual <= @umbral_dobles - 1 THEN 0
			    WHEN @umbral_triples > 0 AND rhh.he_manual > @umbral_triples
			        THEN CAST(@umbral_triples - @umbral_dobles + 1 AS DECIMAL(10, 2))
			    ELSE rhh.he_manual - (@umbral_dobles - 1)
			END AS horas_dobles,
		CASE
			    WHEN ce.ori_hext NOT IN (2, 3) OR ISNULL(rhh.he_manual, 0) <= 0 THEN 0
			    WHEN @umbral_triples <= 0 OR @umbral_triples < @umbral_dobles THEN 0
			    WHEN rhh.he_manual > @umbral_triples THEN rhh.he_manual - @umbral_triples
			    ELSE 0
			END AS horas_triples,

		rhh.hrs_prog,
		-- aus_dia provee el id_tipo_incidencia de la ausencia de día/medio-día autorizada (si existe).
		-- Cuando el calcula corrió antes de que se autorizara el permiso (retroactivo), los flags del DB
		-- (fj/fi/rcg/rsg) están en 0; se derivan aquí al leer para que el frontend los muestre correctamente.
		CASE WHEN rhh.fj  = 1 OR aus_dia.id_tipo_incidencia = 44001 THEN 1 ELSE 0 END AS fj,  rhh.mfj,
		CASE WHEN rhh.fi  = 1 OR aus_dia.id_tipo_incidencia = 44002 THEN 1 ELSE 0 END AS fi,  rhh.mfi,
		CASE WHEN rhh.rcg = 1 OR aus_dia.id_tipo_incidencia = 44003 THEN 1 ELSE 0 END AS rcg, rhh.mrcg,
		CASE WHEN rhh.rsg = 1 OR aus_dia.id_tipo_incidencia = 44004 THEN 1 ELSE 0 END AS rsg, rhh.mrsg,
		CONVERT(BIT, rhh.fes) AS fes, CONVERT(BIT, rhh.c_des) AS c_des, CONVERT(BIT, rhh.vac) AS vac, rhh.retc, rhh.rets, CONVERT(BIT, rhh.na) AS na, rhh.Certificado, sn.id_nota, CASE WHEN sn.id_nota <> 0 THEN sn.nota ELSE '' END AS nota, rhh.id_estatus_incidencia,
		-- La autorización puede llegar después del chequeo automático (status=3).
		-- Se consulta la ausencia vigente para mostrar el permiso sin modificar una incidencia ya aprobada.
		CASE
			-- No se usa tratamiento_pago para distinguir permiso de vacación: ese campo es configurable
			-- por empresa y puede tener cualquier valor. Se usa consume_saldo=0 (permisos no consumen
			-- saldo) + unidad para determinar si es permiso completo o parcial de forma universal.
			WHEN EXISTS (
				SELECT 1 FROM dbo.vDSV_VAC_ausencias_autorizadas a
				INNER JOIN dbo.tDSV_VAC_tipos_ausencia ta ON ta.id_tipo_ausencia = a.id_tipo_ausencia
				WHERE a.id_emp = rhh.id_emp AND a.fecha = CONVERT(DATE, rhh.fec_ent)
					AND ta.consume_saldo = 0 AND a.unidad IN ('D', 'M')
			) AND (
				(rhh.codeV_i = 99 AND rhh.codeV_bl = 99 AND rhh.codeV_el = 99 AND rhh.codeV_o = 99)
				OR (CAST(rhh.hr_ent_lab AS TIME) = '00:00:00' AND CAST(rhh.hr_ini_com AS TIME) = '00:00:00'
					AND CAST(rhh.hr_fin_com AS TIME) = '00:00:00' AND CAST(rhh.hr_fin_lab AS TIME) = '00:00:00')
			) THEN 1
			WHEN EXISTS (
				SELECT 1 FROM dbo.vDSV_VAC_ausencias_autorizadas a
				WHERE a.id_emp = rhh.id_emp AND a.fecha = CONVERT(DATE, rhh.fec_ent)
					AND a.unidad = 'H'
			) THEN 2
			-- Permiso de día/medio-día con checadas reales: el empleado asistió pero tiene permiso.
			-- Se devuelve 3 para que el frontend muestre "Permiso" en clasificacionDiaTexto
			-- sin activar permisoParcial (cPermiso=2), que bloquearía el display del Tipo de Incidencia.
			WHEN aus_dia.id_tipo_incidencia IS NOT NULL THEN 3
			ELSE ISNULL(rhh.c_permiso, 0)
		END AS c_permiso,
		CASE
			WHEN rhh.id_tipo_incidencia_otro IS NOT NULL THEN rhh.id_tipo_incidencia_otro
			WHEN aus_dia.id_tipo_incidencia IS NOT NULL
				AND aus_dia.id_tipo_incidencia NOT IN (44001, 44002, 44003, 44004)
			THEN aus_dia.id_tipo_incidencia
			ELSE NULL
		END AS id_tipo_incidencia_otro,
		CONVERT(BIT, rhh.he_aut) AS he_aut,

		CAST(rhh.c_cerrado_manual AS BIT) AS c_nomina_cerrada,
		CONVERT(BIT, ISNULL(ch.sin_checadas, 0)) AS sin_checadas

	FROM [dbo].[rh_hr_hst] rhh WITH(NOLOCK)
	INNER JOIN [dbo].[cat_emp] ce WITH(NOLOCK) ON ce.id_emp = rhh.id_emp
	INNER JOIN [dbo].[cat_depto] cd WITH(NOLOCK) ON cd.id_depto = rhh.id_depto
	INNER JOIN [dbo].[cat_zona] cz WITH(NOLOCK) ON cz.id_zon = ce.id_zona
	INNER JOIN [dbo].[cat_puestos] cp WITH(NOLOCK) ON cp.id_puesto = ce.id_puesto
	LEFT JOIN [dbo].[cat_hor] ch WITH(NOLOCK) ON ch.id_hor = rhh.id_hor
	INNER JOIN [dbo].[sis_notas] sn WITH(NOLOCK) ON sn.id_nota = rhh.id_nota
	LEFT JOIN [dbo].[cat_cli_fa_da] ccfd WITH(NOLOCK) ON ccfd.id_cli_fa_da = ce.id_cli_da
	LEFT JOIN [dbo].[cat_usr] cu WITH(NOLOCK) ON cu.id_usr = rhh.id_usr
	LEFT JOIN [dbo].[sis_tip] st_nom WITH(NOLOCK) ON st_nom.id_tip = ce.tip_nomina AND st_nom.tipo = 13
	-- Obtiene el tipo de incidencia configurado en tDSV_VAC_tipos_ausencia para ausencias de día/medio-día
	-- autorizadas. Se usa para corregir el display cuando el calcula corrió antes de la autorización.
	OUTER APPLY (
		SELECT TOP 1 ta.id_tipo_incidencia
		FROM dbo.vDSV_VAC_ausencias_autorizadas a
		INNER JOIN dbo.tDSV_VAC_tipos_ausencia ta ON ta.id_tipo_ausencia = a.id_tipo_ausencia
		WHERE a.id_emp = rhh.id_emp AND a.fecha = CONVERT(DATE, rhh.fec_ent)
			AND a.unidad IN ('D', 'M') AND ta.consume_saldo = 0
		ORDER BY a.id_ausencia
	) aus_dia
	WHERE CONVERT(DATE, rhh.fec_ent) BETWEEN CONVERT(DATE, @pFechaDe) AND CONVERT(DATE, @pFechaA)

    AND (@pSucursales = '' OR ce.id_suc IN (
        SELECT TRY_CONVERT(INT, value) FROM STRING_SPLIT(@pSucursales, ',')))
    AND (@pIdUsr IS NULL OR EXISTS (
        SELECT 1
        FROM SIRAdmin.SIRA_12_PRIVILEGIOS_USU_SUC AS permiso
        INNER JOIN SIR.SIR_71_SUCURSAL_PATENTE_ADUANA AS spa
            ON spa.nIdSucPatAdu71 = permiso.nIdSucPatAdu71
        INNER JOIN dbo.mcp_suc AS sucursal
            ON sucursal.id_suc = spa.nIdSucursal
        WHERE permiso.nIdUsuario = @pIdUsr
            AND permiso.bAccesar = 1
            AND spa.nIdSucursal = ce.id_suc
            AND sucursal.id_cmp = @pIdCmp
            AND sucursal.status = 1))
	AND (@pIdUser IS NULL OR rhh.id_emp IN (SELECT id_emp FROM Jerarquia))
	AND (@pTipoNominas = '' OR ce.tip_nomina IN(SELECT value FROM STRING_SPLIT(@pTipoNominas, ',')))
	AND (@pDepartamentos = '' OR rhh.id_depto IN(SELECT value FROM STRING_SPLIT(@pDepartamentos, ',')))
	AND (@pTurnos = '' OR rhh.id_turno IN(SELECT value FROM STRING_SPLIT(@pTurnos, ',')))
	AND (@pZonas = '' OR ce.id_zona IN(SELECT value FROM STRING_SPLIT(@pZonas, ',')))
	AND (@pEmpleados = '' OR rhh.id_emp IN(SELECT value FROM STRING_SPLIT(@pEmpleados, ',') ))
	AND (@pEstatusIncidencias IS NULL OR @pEstatusIncidencias = '' OR rhh.id_estatus_incidencia IN (SELECT value FROM STRING_SPLIT(@pEstatusIncidencias, ',')))
	AND (
		@pIncidencias = '' OR (
			(@SoloAJ  = 1 AND (rhh.fj  = 1 OR aus_dia.id_tipo_incidencia = 44001)) OR
			(@SoloVAC = 1 AND rhh.vac = 1) OR
			-- Tipos que se guardan en id_tipo_incidencia_otro: Incapacidades, AJNP, Baja, Días Trabajados, etc.
			-- También cubre ausencias autorizadas cuyo tipo no es uno de los 4 flags estándar.
			((rhh.id_tipo_incidencia_otro IS NOT NULL OR (aus_dia.id_tipo_incidencia IS NOT NULL AND aus_dia.id_tipo_incidencia NOT IN (44001,44002,44003,44004)))
				AND COALESCE(rhh.id_tipo_incidencia_otro, aus_dia.id_tipo_incidencia) IN (SELECT TRY_CAST(value AS INT) FROM STRING_SPLIT(@pIncidencias, ',') WHERE TRY_CAST(value AS INT) IS NOT NULL)) OR
			(@SoloAI  = 1 AND (rhh.fi  = 1 OR aus_dia.id_tipo_incidencia = 44002)) OR
			(@SoloRCG = 1 AND (rhh.rcg = 1 OR aus_dia.id_tipo_incidencia = 44003)) OR
			(@SoloRSG = 1 AND (rhh.rsg = 1 OR aus_dia.id_tipo_incidencia = 44004)) OR
			(@SoloHE  = 1 AND rhh.he_aut = 1)
		)
	)
	AND (
		-- Un día de vacación/permiso/incapacidad (vac=1 o fj=1) o de descanso (c_des=1) siempre tiene
		-- las 4 horas en blanco porque no hubo trabajo ese día - sin esta exclusión, cualquier filtro
		-- "Sin Registro X" los mezclaba con faltas reales de checada que sí ameritan seguimiento.
		@pFaltantes = '' OR (
			-- Excluye días con ausencia autorizada (aus_dia) aunque el calcula no haya seteado fj aún.
			rhh.vac = 0 AND rhh.fj = 0 AND aus_dia.id_tipo_incidencia IS NULL AND rhh.c_des = 0 AND (
				(@SRE  = 1 AND CONVERT(DATE, rhh.hr_ent_lab) BETWEEN CONVERT(DATE, @pFechaDe) AND CONVERT(DATE, @pFechaA) AND CAST(rhh.hr_ent_lab AS TIME) = '00:00:00') OR
				(@SRS  = 1 AND CONVERT(DATE, rhh.hr_fin_lab) BETWEEN CONVERT(DATE, @pFechaDe) AND CONVERT(DATE, @pFechaA) AND CAST(rhh.hr_fin_lab AS TIME) = '00:00:00') OR
				(@SRSC = 1 AND CONVERT(DATE, rhh.hr_ini_com) BETWEEN CONVERT(DATE, @pFechaDe) AND CONVERT(DATE, @pFechaA) AND CAST(rhh.hr_ini_com AS TIME) = '00:00:00') OR
				(@SREC = 1 AND CONVERT(DATE, rhh.hr_fin_com) BETWEEN CONVERT(DATE, @pFechaDe) AND CONVERT(DATE, @pFechaA) AND CAST(rhh.hr_fin_com AS TIME) = '00:00:00')
			)
		)
	)
	ORDER BY ce.nom_cort, rhh.fec_ent

END TRY
BEGIN CATCH
    DECLARE @ErrorMessage AS NVARCHAR(400)
    DECLARE @ErrorNumber AS INT
    DECLARE @ErrorSeverity AS INT
    DECLARE @ErrorState AS INT
    DECLARE @ErrorLine AS INT
    DECLARE @ErrorProcedure AS VARCHAR(100)
    SELECT  @ErrorNumber = ERROR_NUMBER(), @ErrorSeverity = ERROR_SEVERITY(), @ErrorState = 2, @ErrorLine = ERROR_LINE(), @ErrorProcedure = ISNULL(ERROR_PROCEDURE(), '-');
    SELECT @ErrorMessage = ERROR_MESSAGE();
    RAISERROR (@ErrorMessage, 16, 1, @ErrorNumber, @ErrorSeverity, @ErrorState)
END CATCH
GO

-- Origen: dsv\Stored Procedures\pDSV_CFG_ConfiguracionSucursalesUsuario.sql
CREATE OR ALTER PROCEDURE [dbo].[pDSV_CFG_ConfiguracionSucursalesUsuario]
@Usuario AS VARCHAR(80)
AS SET NOCOUNT ON
BEGIN TRY

    DECLARE @IdUsuario  AS INT = (SELECT id_usr FROM cat_usr WITH(NOLOCK) WHERE usr = @Usuario)

    SELECT DISTINCT nIdSucPatAdu71 AS idSucursal, CONCAT(Siglas, ' - ', Sucursal) AS nombre, Sucursal AS sucursal
    FROM SIR.SIR_VT_SucursalPatenteAduana WITH(NOLOCK)
    WHERE nIdSucPatAdu71 IN(SELECT nIdSucPatAdu71 FROM SIR.ObtieneSucPatAduPorUsuario (@IdUsuario))

END TRY
BEGIN CATCH
    DECLARE @ErrorMessage AS NVARCHAR(400)
    DECLARE @ErrorNumber AS INT
    DECLARE @ErrorSeverity AS INT
    DECLARE @ErrorState AS INT
    DECLARE @ErrorLine AS INT
    DECLARE @ErrorProcedure AS VARCHAR(100)
    SELECT  @ErrorNumber = ERROR_NUMBER(), @ErrorSeverity = ERROR_SEVERITY(), @ErrorState = 2, @ErrorLine = ERROR_LINE(), @ErrorProcedure = ISNULL(ERROR_PROCEDURE(), '-');
    SELECT @ErrorMessage = ERROR_MESSAGE();
    RAISERROR (@ErrorMessage, 16, 1, @ErrorNumber, @ErrorSeverity, @ErrorState)
END CATCH
GO


-- ====================================================================================================
-- 5. Verificacion (solo lectura)
-- ====================================================================================================

SELECT o.name AS objeto, o.type_desc, o.modify_date
FROM sys.objects o
WHERE o.schema_id = SCHEMA_ID(N'dbo')
  AND o.name IN (N'pDSVRRHHauxiliarHorarioObtenerInformacion', N'pDSVRRHHauxiliarHorarioInformacionTipoIncidencias',
                 N'pDSVRRHHauxiliarHorarioInformacionSucursales', N'pDSVRRHHauxiliarHorarioSucursalesEmpleado',
                 N'pDSV_CFG_ConfiguracionSucursalesUsuario', N'vDSV_VAC_ausencias_autorizadas', N'tDSV_VAC_tipos_ausencia')
ORDER BY o.name;

SELECT t.name AS tabla, c.name AS columna
FROM sys.columns c JOIN sys.tables t ON t.object_id = c.object_id
WHERE (t.name = N'rh_hr_hst' AND c.name IN (N'c_permiso', N'he_aut', N'id_estatus_incidencia', N'c_cerrado_manual', N'id_tipo_incidencia_otro', N'he_manual'))
   OR (t.name = N'cat_hor'   AND c.name IN (N'criterio', N'sin_checadas'))
ORDER BY t.name, c.name;   -- esperado: 8 filas

-- Prueba funcional (todos los empleados, 1 dia): debe regresar filas sin error.
-- EXEC dbo.pDSVRRHHauxiliarHorarioObtenerInformacion @pIdUser = NULL, @pFechaDe = '20261101', @pFechaA = '20261101';
GO

SET NOEXEC OFF;
GO

/* ROLLBACK (descomentar solo si hace falta revertir; NO borra datos de negocio salvo las columnas nuevas)
DROP PROCEDURE IF EXISTS dbo.pDSVRRHHauxiliarHorarioObtenerInformacion;
DROP PROCEDURE IF EXISTS dbo.pDSVRRHHauxiliarHorarioInformacionTipoIncidencias;
DROP PROCEDURE IF EXISTS dbo.pDSVRRHHauxiliarHorarioInformacionSucursales;
DROP PROCEDURE IF EXISTS dbo.pDSVRRHHauxiliarHorarioSucursalesEmpleado;
DROP PROCEDURE IF EXISTS dbo.pDSV_CFG_ConfiguracionSucursalesUsuario;
DROP VIEW      IF EXISTS dbo.vDSV_VAC_ausencias_autorizadas;
DROP TABLE     IF EXISTS dbo.tDSV_VAC_tipos_ausencia;
-- Columnas (primero su default constraint, luego la columna):
-- ALTER TABLE dbo.rh_hr_hst DROP CONSTRAINT DF_rh_hr_hst_c_permiso, DF_rh_hr_hst_he_aut, DF_rh_hr_hst_id_estatus_incidencia, DF_rh_hr_hst_c_cerrado_manual;
-- ALTER TABLE dbo.rh_hr_hst DROP COLUMN c_permiso, he_aut, id_estatus_incidencia, c_cerrado_manual, id_tipo_incidencia_otro, he_manual;
-- ALTER TABLE dbo.cat_hor DROP CONSTRAINT DF_cat_hor_criterio, DF_cat_hor_sin_checadas;
-- ALTER TABLE dbo.cat_hor DROP COLUMN criterio, sin_checadas;
*/


CREATE OR ALTER PROCEDURE dbo.p_ConverteXMLBPMN
(
    @FusionXml xml,
    @BpmnXml   xml OUTPUT,

    -- -------------------------------------------------------------------------
    -- Layout defaults (BRISK "regra oficial" p/ não cortar texto)
    -- -------------------------------------------------------------------------
    @TaskMinWidth  float = 220,
    @TaskMinHeight float = 80,
    @CallActivityMinWidth  float = 260,
    @CallActivityMinHeight float = 120,

    @GatewaySize float = 50,
    @EventDefaultSize float = 36,

    -- -------------------------------------------------------------------------
    -- Options
    -- -------------------------------------------------------------------------
    @IgnoreTimerIconNode bit = 1,          -- tipoElemento=3 é apenas ícone
    @IgnoreDashed bit = 1,                 -- dashed não afeta BPMN (tudo sólido)
    @InsertMergeBeforeParallelSplitWhenMultiIncoming bit = 1
)
AS
BEGIN
    SET NOCOUNT ON;

    -- -------------------------------------------------------------------------
    -- 0) Canvas width/height (base de escala)
    -- -------------------------------------------------------------------------
    DECLARE @CanvasW float = TRY_CONVERT(float, REPLACE(@FusionXml.value('(/chart/workflows/@width)[1]',  'nvarchar(50)'), ',', '.'));
    DECLARE @CanvasH float = TRY_CONVERT(float, REPLACE(@FusionXml.value('(/chart/workflows/@height)[1]', 'nvarchar(50)'), ',', '.'));

    IF @CanvasW IS NULL OR @CanvasH IS NULL
        THROW 50001, 'FusionCharts XML sem <workflows width/height>.', 1;

    -- -------------------------------------------------------------------------
    -- 1) Staging tables
    -- -------------------------------------------------------------------------
    CREATE TABLE #Warnings (Msg nvarchar(4000) NOT NULL);

    CREATE TABLE #Nodes
    (
        FusionId        nvarchar(100) NOT NULL PRIMARY KEY,
        TipoElemento    int           NOT NULL,
        Shape           nvarchar(50)  NULL,
        Name            nvarchar(400) NULL,
        ToolText        nvarchar(400) NULL,

        XPercent        float         NOT NULL,
        YPercent        float         NOT NULL,

        WidthPx         float         NULL,
        HeightPx        float         NULL,
        RadiusPx        float         NULL,

        CodigoSubfluxo  int           NULL,

        RawSet          xml           NOT NULL
    );

    CREATE TABLE #Edges
    (
        EdgeSeq   int IDENTITY(1,1) NOT NULL PRIMARY KEY,
        FromId    nvarchar(100) NOT NULL,
        ToId      nvarchar(100) NOT NULL,
        Label     nvarchar(400) NULL,
        Dashed    bit NULL,
        RawConn   xml NOT NULL
    );

    -- -------------------------------------------------------------------------
    -- Timer icon map (tipoElemento=3) used only for DI positioning (optional)
    -- -------------------------------------------------------------------------
    CREATE TABLE #TimerIcon
    (
        IconFusionId nvarchar(100) NOT NULL PRIMARY KEY,
        XPercent     float NOT NULL,
        YPercent     float NOT NULL,
        WidthPx      float NULL,
        HeightPx     float NULL,
        RadiusPx     float NULL,
        RawSet       xml NOT NULL
    );

    -- -------------------------------------------------------------------------
    -- 2) Parse Nodes (<set>)
    -- -------------------------------------------------------------------------
    INSERT INTO #Nodes (FusionId, TipoElemento, Shape, Name, ToolText, XPercent, YPercent, WidthPx, HeightPx, RadiusPx, CodigoSubfluxo, RawSet)
    SELECT
        S.N.value('@id','nvarchar(100)')                                 AS FusionId,
        TRY_CONVERT(int, S.N.value('@tipoElemento','nvarchar(20)'))      AS TipoElemento,
        S.N.value('@shape','nvarchar(50)')                               AS Shape,
        NULLIF(S.N.value('@name','nvarchar(400)'), '')                   AS Name,
        NULLIF(S.N.value('@toolText','nvarchar(400)'), '')               AS ToolText,
        TRY_CONVERT(float, REPLACE(S.N.value('@x','nvarchar(50)'),',','.')) AS XPercent,
        TRY_CONVERT(float, REPLACE(S.N.value('@y','nvarchar(50)'),',','.')) AS YPercent,
        TRY_CONVERT(float, REPLACE(S.N.value('@width','nvarchar(50)'),',','.'))  AS WidthPx,
        TRY_CONVERT(float, REPLACE(S.N.value('@height','nvarchar(50)'),',','.')) AS HeightPx,
        TRY_CONVERT(float, REPLACE(S.N.value('@radius','nvarchar(50)'),',','.')) AS RadiusPx,
        TRY_CONVERT(int, NULLIF(S.N.value('@codigoSubfluxo','nvarchar(50)'),'')) AS CodigoSubfluxo,
        S.N.query('.') AS RawSet
    FROM @FusionXml.nodes('/chart/dataSet/set') AS S(N);

    -- -------------------------------------------------------------------------
    -- Separate timer icon nodes (tipoElemento=3) to optionally reuse for DI.
    -- -------------------------------------------------------------------------
    INSERT INTO #TimerIcon (IconFusionId, XPercent, YPercent, WidthPx, HeightPx, RadiusPx, RawSet)
    SELECT FusionId, XPercent, YPercent, WidthPx, HeightPx, RadiusPx, RawSet
    FROM #Nodes
    WHERE TipoElemento = 3;

    IF @IgnoreTimerIconNode = 1
    BEGIN
        DELETE FROM #Nodes WHERE TipoElemento = 3;
    END

    -- -------------------------------------------------------------------------
    -- 3) Parse Edges (<connector>)
    -- -------------------------------------------------------------------------
    INSERT INTO #Edges (FromId, ToId, Label, Dashed, RawConn)
    SELECT
        C.N.value('@from','nvarchar(100)'),
        C.N.value('@to','nvarchar(100)'),
        NULLIF(C.N.value('@label','nvarchar(400)'),'') AS Label,
        CASE WHEN NULLIF(C.N.value('@dashed','nvarchar(10)'),'') IS NULL THEN NULL
             ELSE CASE WHEN C.N.value('@dashed','nvarchar(10)') IN ('1','true','True') THEN 1 ELSE 0 END
        END AS Dashed,
        C.N.query('.')
    FROM @FusionXml.nodes('/chart/connectors/connector') AS C(N);

    -- -------------------------------------------------------------------------
    -- 3.1) Remove connectors that reference missing nodes
    -- -------------------------------------------------------------------------
    ;WITH e AS
    (
        SELECT EdgeSeq, FromId, ToId
        FROM #Edges
    )
    DELETE E
    FROM #Edges E
    LEFT JOIN #Nodes N1 ON N1.FusionId = E.FromId
    LEFT JOIN #Nodes N2 ON N2.FusionId = E.ToId
    WHERE N1.FusionId IS NULL OR N2.FusionId IS NULL;

    -- -------------------------------------------------------------------------
    -- 3.2) If ignoring timer icons, drop all connectors involving icons.
    -- -------------------------------------------------------------------------
    IF @IgnoreTimerIconNode = 1
    BEGIN
        DELETE E
        FROM #Edges E
        WHERE EXISTS (SELECT 1 FROM #TimerIcon TI WHERE TI.IconFusionId = E.FromId)
           OR EXISTS (SELECT 1 FROM #TimerIcon TI WHERE TI.IconFusionId = E.ToId);
    END

    -- -------------------------------------------------------------------------
    -- 4) Build BPMN element mapping (#Map) for nodes
    -- -------------------------------------------------------------------------
    CREATE TABLE #Map
    (
        FusionId     nvarchar(100) NOT NULL PRIMARY KEY,
        TipoElemento int NOT NULL,
        BpmnId       nvarchar(200) NOT NULL,
        BpmnTag      nvarchar(50)  NOT NULL, -- startEvent, endEvent, task, callActivity, exclusiveGateway, parallelGateway
        Name         nvarchar(400) NULL,

        -- Center (px)
        Cx float NOT NULL,
        Cy float NOT NULL,

        -- Bounds
        X float NOT NULL,
        Y float NOT NULL,
        W float NOT NULL,
        H float NOT NULL,

        RawSet xml NOT NULL
    );

    INSERT INTO #Map (FusionId, TipoElemento, BpmnId, BpmnTag, Name, Cx, Cy, X, Y, W, H, RawSet)
    SELECT
        N.FusionId,
        N.TipoElemento,
        CASE
            WHEN N.TipoElemento = 0 THEN CONCAT('Start_', N.FusionId)
            WHEN N.TipoElemento = 6 THEN CONCAT('End_',   N.FusionId)
            WHEN N.TipoElemento = 1 AND ISNULL(N.CodigoSubfluxo,0) <> 0 THEN CONCAT('Call_', N.FusionId)
            WHEN N.TipoElemento = 1 THEN CONCAT('Task_', N.FusionId)
            WHEN N.TipoElemento = 7 THEN CONCAT('Xor_',  N.FusionId)
            WHEN N.TipoElemento = 4 THEN CONCAT('AndSplit_', N.FusionId)
            WHEN N.TipoElemento = 5 THEN CONCAT('AndJoin_',  N.FusionId)
            ELSE CONCAT('Node_', N.FusionId)
        END AS BpmnId,
        CASE
            WHEN N.TipoElemento = 0 THEN 'startEvent'
            WHEN N.TipoElemento = 6 THEN 'endEvent'
            WHEN N.TipoElemento = 1 AND ISNULL(N.CodigoSubfluxo,0) <> 0 THEN 'callActivity'
            WHEN N.TipoElemento = 1 THEN 'task'
            WHEN N.TipoElemento = 7 THEN 'exclusiveGateway'
            WHEN N.TipoElemento IN (4,5) THEN 'parallelGateway'
            ELSE 'task'
        END AS BpmnTag,
        COALESCE(NULLIF(N.Name,''), NULLIF(N.ToolText,'')) AS Name,
        -- center in pixels
        (@CanvasW * (N.XPercent / 100.0)) AS Cx,
        (@CanvasH * (N.YPercent / 100.0)) AS Cy,

        -- X,Y,W,H computed later
        0,0,0,0,
        N.RawSet
    FROM #Nodes N;

    -- -------------------------------------------------------------------------
    -- 4.1) Compute Bounds (DI) according to formal de-para
    -- -------------------------------------------------------------------------
    UPDATE M
    SET
        W = CASE
                WHEN M.TipoElemento IN (0,6) THEN
                    -- events: use radius if present, else default
                    CASE WHEN TRY_CONVERT(float, REPLACE(M.RawSet.value('(/set/@radius)[1]','nvarchar(50)'),',','.')) IS NOT NULL
                         THEN 2.0 * TRY_CONVERT(float, REPLACE(M.RawSet.value('(/set/@radius)[1]','nvarchar(50)'),',','.'))
                         ELSE @EventDefaultSize
                    END
                WHEN M.TipoElemento = 7 THEN @GatewaySize
                WHEN M.TipoElemento IN (4,5) THEN @GatewaySize
                WHEN M.TipoElemento = 1 AND M.BpmnTag = 'callActivity' THEN
                    -- callActivity: max(width, CallActivityMinWidth)
                    CASE
                        WHEN TRY_CONVERT(float, REPLACE(M.RawSet.value('(/set/@width)[1]','nvarchar(50)'),',','.')) IS NULL THEN @CallActivityMinWidth
                        WHEN TRY_CONVERT(float, REPLACE(M.RawSet.value('(/set/@width)[1]','nvarchar(50)'),',','.')) < @CallActivityMinWidth THEN @CallActivityMinWidth
                        ELSE TRY_CONVERT(float, REPLACE(M.RawSet.value('(/set/@width)[1]','nvarchar(50)'),',','.'))
                    END
                ELSE
                    -- task: max(width, TaskMinWidth)
                    CASE
                        WHEN TRY_CONVERT(float, REPLACE(M.RawSet.value('(/set/@width)[1]','nvarchar(50)'),',','.')) IS NULL THEN @TaskMinWidth
                        WHEN TRY_CONVERT(float, REPLACE(M.RawSet.value('(/set/@width)[1]','nvarchar(50)'),',','.')) < @TaskMinWidth THEN @TaskMinWidth
                        ELSE TRY_CONVERT(float, REPLACE(M.RawSet.value('(/set/@width)[1]','nvarchar(50)'),',','.'))
                    END
            END,
        H = CASE
                WHEN M.TipoElemento IN (0,6) THEN
                    CASE WHEN TRY_CONVERT(float, REPLACE(M.RawSet.value('(/set/@radius)[1]','nvarchar(50)'),',','.')) IS NOT NULL
                         THEN 2.0 * TRY_CONVERT(float, REPLACE(M.RawSet.value('(/set/@radius)[1]','nvarchar(50)'),',','.'))
                         ELSE @EventDefaultSize
                    END
                WHEN M.TipoElemento = 7 THEN @GatewaySize
                WHEN M.TipoElemento IN (4,5) THEN @GatewaySize
                WHEN M.TipoElemento = 1 AND M.BpmnTag = 'callActivity' THEN
                    CASE
                        WHEN TRY_CONVERT(float, REPLACE(M.RawSet.value('(/set/@height)[1]','nvarchar(50)'),',','.')) IS NULL THEN @CallActivityMinHeight
                        WHEN TRY_CONVERT(float, REPLACE(M.RawSet.value('(/set/@height)[1]','nvarchar(50)'),',','.')) < @CallActivityMinHeight THEN @CallActivityMinHeight
                        ELSE TRY_CONVERT(float, REPLACE(M.RawSet.value('(/set/@height)[1]','nvarchar(50)'),',','.'))
                    END
                ELSE
                    CASE
                        WHEN TRY_CONVERT(float, REPLACE(M.RawSet.value('(/set/@height)[1]','nvarchar(50)'),',','.')) IS NULL THEN @TaskMinHeight
                        WHEN TRY_CONVERT(float, REPLACE(M.RawSet.value('(/set/@height)[1]','nvarchar(50)'),',','.')) < @TaskMinHeight THEN @TaskMinHeight
                        ELSE TRY_CONVERT(float, REPLACE(M.RawSet.value('(/set/@height)[1]','nvarchar(50)'),',','.'))
                    END
            END
    FROM #Map M;

    UPDATE #Map
    SET
        X = CASE WHEN (Cx - (W/2.0)) < 0 THEN 0 ELSE (Cx - (W/2.0)) END,
        Y = CASE WHEN (Cy - (H/2.0)) < 0 THEN 0 ELSE (Cy - (H/2.0)) END;

    -- -------------------------------------------------------------------------
    -- 5) Parallel split safety: insert merge before AndSplit when multi-incoming
    -- -------------------------------------------------------------------------
    CREATE TABLE #InsertedMerge
    (
        SplitFusionId nvarchar(100) NOT NULL PRIMARY KEY,
        MergeBpmnId   nvarchar(200) NOT NULL
    );

    IF @InsertMergeBeforeParallelSplitWhenMultiIncoming = 1
    BEGIN
        ;WITH Incoming AS
        (
            SELECT E.ToId AS SplitFusionId, COUNT(*) AS Cnt
            FROM #Edges E
            JOIN #Nodes N ON N.FusionId = E.ToId
            WHERE N.TipoElemento = 4
            GROUP BY E.ToId
        )
        INSERT INTO #InsertedMerge (SplitFusionId, MergeBpmnId)
        SELECT I.SplitFusionId, CONCAT('MergeToParallel_', I.SplitFusionId)
        FROM Incoming I
        WHERE I.Cnt > 1;

        -- Rewire: all edges that go into split -> go into merge instead
        UPDATE E
        SET ToId = IM.SplitFusionId + '_MERGE_PROXY' -- placeholder
        FROM #Edges E
        JOIN #InsertedMerge IM ON IM.SplitFusionId = E.ToId;

        -- Create proxy node entries for merge in #Map
        INSERT INTO #Map (FusionId, TipoElemento, BpmnId, BpmnTag, Name, Cx, Cy, X, Y, W, H, RawSet)
        SELECT
            IM.SplitFusionId + '_MERGE_PROXY' AS FusionId,
            7000 AS TipoElemento,
            IM.MergeBpmnId AS BpmnId,
            'exclusiveGateway' AS BpmnTag,
            'Merge' AS Name,
            M.Cx - (@GatewaySize * 0.9) AS Cx,   -- place a bit left of split
            M.Cy AS Cy,
            0,0, @GatewaySize, @GatewaySize,
            (SELECT CAST('<set />' AS xml)) AS RawSet
        FROM #InsertedMerge IM
        JOIN #Map M ON M.FusionId = IM.SplitFusionId;

        UPDATE #Map
        SET
          X = CASE WHEN (Cx - (W/2.0)) < 0 THEN 0 ELSE (Cx - (W/2.0)) END,
          Y = CASE WHEN (Cy - (H/2.0)) < 0 THEN 0 ELSE (Cy - (H/2.0)) END
        WHERE FusionId LIKE '%_MERGE_PROXY';

        -- Add flow from merge -> split
        INSERT INTO #Edges (FromId, ToId, Label, Dashed, RawConn)
        SELECT
            IM.SplitFusionId + '_MERGE_PROXY',
            IM.SplitFusionId,
            NULL,
            0,
            CAST('<connector />' AS xml)
        FROM #InsertedMerge IM;
    END

    -- -------------------------------------------------------------------------
    -- 6) Timers (actionType="T") => Boundary Timer Event (formal BRISK)
    -- -------------------------------------------------------------------------
    CREATE TABLE #BoundaryTimer
    (
        TaskFusionId   nvarchar(100) NOT NULL PRIMARY KEY,
        TaskBpmnId     nvarchar(200) NOT NULL,
        TimerBpmnId    nvarchar(200) NOT NULL,
        TargetFusionId nvarchar(100) NULL,
        TargetBpmnId   nvarchar(200) NULL,
        TimeoutValue   int NULL,
        TimeoutUnit    nvarchar(20) NULL,
        TimeDuration   nvarchar(50) NULL,
        -- DI
        Cx float NOT NULL,
        Cy float NOT NULL,
        X  float NOT NULL,
        Y  float NOT NULL,
        W  float NOT NULL,
        H  float NOT NULL
    );

    ;WITH TimerAction AS
    (
        SELECT
            N.FusionId AS TaskFusionId,
            M.BpmnId   AS TaskBpmnId,
            -- take first timer action if multiple
            N.RawSet.value('(//acoes/acao[@actionType="T"]/@to)[1]', 'nvarchar(100)') AS ToId,
            TRY_CONVERT(int, NULLIF(N.RawSet.value('(//acoes/acao[@actionType="T"]/@timeoutValue)[1]', 'nvarchar(20)'),'')) AS TimeoutValue,
            NULLIF(N.RawSet.value('(//acoes/acao[@actionType="T"]/@timeoutUnit)[1]', 'nvarchar(20)'), '') AS TimeoutUnit
        FROM #Nodes N
        JOIN #Map  M ON M.FusionId = N.FusionId
        WHERE N.TipoElemento = 1 -- task/callActivity
          AND N.RawSet.exist('//acoes/acao[@actionType="T"]') = 1
          AND M.BpmnTag = 'task' -- boundary timer only for task (callActivity could be extended later)
    )
    INSERT INTO #BoundaryTimer (TaskFusionId, TaskBpmnId, TimerBpmnId, TargetFusionId, TargetBpmnId, TimeoutValue, TimeoutUnit, TimeDuration, Cx, Cy, X, Y, W, H)
    SELECT
        TA.TaskFusionId,
        TA.TaskBpmnId,
        CONCAT('Timer_', TA.TaskBpmnId) AS TimerBpmnId,
        NULLIF(TA.ToId,'') AS TargetFusionId,
        MT.BpmnId AS TargetBpmnId,
        TA.TimeoutValue,
        TA.TimeoutUnit,
        CASE
            WHEN TA.TimeoutValue IS NULL OR TA.TimeoutUnit IS NULL THEN NULL
            WHEN LOWER(TA.TimeoutUnit) IN ('hora','horas','h') THEN CONCAT('PT', TA.TimeoutValue, 'H')
            WHEN LOWER(TA.TimeoutUnit) IN ('minuto','minutos','m') THEN CONCAT('PT', TA.TimeoutValue, 'M')
            WHEN LOWER(TA.TimeoutUnit) IN ('dia','dias','d') THEN CONCAT('P',  TA.TimeoutValue, 'D')
            ELSE CONCAT('PT', TA.TimeoutValue, 'H') -- fallback
        END AS TimeDuration,
        -- DI positioning:
        -- Prefer timer icon position if there is a 2-edge path Task->Icon->Target
        COALESCE( (@CanvasW * (TI.XPercent/100.0)), (MTask.X + MTask.W - (@EventDefaultSize/2.0)) ) AS Cx,
        COALESCE( (@CanvasH * (TI.YPercent/100.0)), (MTask.Y + (@EventDefaultSize/2.0)) )          AS Cy,
        0,0,
        @EventDefaultSize, @EventDefaultSize
    FROM TimerAction TA
    JOIN #Map MTask ON MTask.FusionId = TA.TaskFusionId
    LEFT JOIN #Map MT ON MT.FusionId = NULLIF(TA.ToId,'')
    OUTER APPLY
    (
        SELECT TOP 1 I.*
        FROM #TimerIcon I
        JOIN #Edges E1 ON E1.FromId = TA.TaskFusionId AND E1.ToId = I.IconFusionId
        JOIN #Edges E2 ON E2.FromId = I.IconFusionId AND E2.ToId = NULLIF(TA.ToId,'')
        ORDER BY I.IconFusionId
    ) TI;

    UPDATE #BoundaryTimer
    SET
        X = CASE WHEN (Cx - (W/2.0)) < 0 THEN 0 ELSE (Cx - (W/2.0)) END,
        Y = CASE WHEN (Cy - (H/2.0)) < 0 THEN 0 ELSE (Cy - (H/2.0)) END;

    -- Add boundary timer as mappable DI element (not in #Map)
    CREATE TABLE #ExtraMap
    (
        BpmnId    nvarchar(200) NOT NULL PRIMARY KEY,
        BpmnTag   nvarchar(50)  NOT NULL, -- boundaryEvent
        Name      nvarchar(400) NULL,
        AttachedTo nvarchar(200) NULL,
        CancelActivity bit NOT NULL,
        TimeDuration nvarchar(50) NULL,
        Cx float NOT NULL,
        Cy float NOT NULL,
        X  float NOT NULL,
        Y  float NOT NULL,
        W  float NOT NULL,
        H  float NOT NULL
    );

    INSERT INTO #ExtraMap (BpmnId, BpmnTag, Name, AttachedTo, CancelActivity, TimeDuration, Cx, Cy, X, Y, W, H)
    SELECT
        BT.TimerBpmnId,
        'boundaryEvent',
        'Timer' AS Name,
        BT.TaskBpmnId,
        1,
        BT.TimeDuration,
        BT.Cx, BT.Cy, BT.X, BT.Y, BT.W, BT.H
    FROM #BoundaryTimer BT;

    -- -------------------------------------------------------------------------
    -- 7) Flows (sequenceFlow)
    -- -------------------------------------------------------------------------
    CREATE TABLE #Flows
    (
        FlowSeq int IDENTITY(1,1) NOT NULL PRIMARY KEY,
        FlowId  nvarchar(250) NOT NULL,
        SourceFusionId nvarchar(100) NULL,
        TargetFusionId nvarchar(100) NULL,
        SourceBpmnId nvarchar(200) NOT NULL,
        TargetBpmnId nvarchar(200) NOT NULL,
        Label nvarchar(400) NULL,

        ConditionText nvarchar(max) NULL,
        IsDefault bit NOT NULL
    );

    -- 7.1 Flows from connectors
    INSERT INTO #Flows (FlowId, SourceFusionId, TargetFusionId, SourceBpmnId, TargetBpmnId, Label, ConditionText, IsDefault)
    SELECT
        CONCAT('Flow_', E.FromId, '_', E.ToId, '_', ROW_NUMBER() OVER (PARTITION BY E.FromId, E.ToId ORDER BY E.EdgeSeq)) AS FlowId,
        E.FromId, E.ToId,
        MF.BpmnId, MT.BpmnId,
        CASE WHEN E.Label IS NOT NULL THEN E.Label ELSE NULL END,
        NULL,
        0
    FROM #Edges E
    JOIN #Map MF ON MF.FusionId = E.FromId
    JOIN #Map MT ON MT.FusionId = E.ToId
    WHERE (@IgnoreDashed = 0 OR ISNULL(E.Dashed,0) = 0 OR E.Dashed IS NULL);

    -- 7.2 Flow from boundary timer to its target
    INSERT INTO #Flows (FlowId, SourceFusionId, TargetFusionId, SourceBpmnId, TargetBpmnId, Label, ConditionText, IsDefault)
    SELECT
        CONCAT('Flow_', BT.TimerBpmnId, '_', BT.TargetBpmnId) AS FlowId,
        BT.TaskFusionId, BT.TargetFusionId,
        BT.TimerBpmnId, BT.TargetBpmnId,
        NULL, NULL, 0
    FROM #BoundaryTimer BT
    WHERE BT.TargetBpmnId IS NOT NULL;

    -- 7.3 Enrich gateway flows with conditions / default (actionType="D")
    ;WITH Gw AS
    (
        SELECT M.FusionId, M.BpmnId, M.RawSet
        FROM #Map M
        WHERE M.TipoElemento = 7
    ),
    GwActions AS
    (
        SELECT
            G.FusionId AS GwFusionId,
            A.N.value('@to','nvarchar(100)') AS ToId,
            NULLIF(A.N.value('@decodedCondition','nvarchar(max)'),'') AS DecodedCondition,
            NULLIF(A.N.value('@condition','nvarchar(max)'),'') AS Condition,
            A.N.value('@actionType','nvarchar(5)') AS ActionType
        FROM Gw G
        CROSS APPLY G.RawSet.nodes('/set/acoes/acao') AS A(N)
        WHERE A.N.value('@actionType','nvarchar(5)') = 'D'
    )
    UPDATE F
    SET
        ConditionText =
            CASE
                WHEN LOWER(COALESCE(GA.DecodedCondition, GA.Condition, '')) = 'else' THEN NULL
                ELSE COALESCE(GA.DecodedCondition, GA.Condition)
            END,
        IsDefault =
            CASE
                WHEN LOWER(COALESCE(GA.DecodedCondition, GA.Condition, '')) = 'else' THEN 1
                ELSE 0
            END
    FROM #Flows F
    JOIN GwActions GA
      ON GA.GwFusionId = F.SourceFusionId
     AND GA.ToId = F.TargetFusionId;

    -- If there are multiple "else", keep only the first as default
    ;WITH D AS
    (
        SELECT FlowSeq, ROW_NUMBER() OVER (PARTITION BY SourceFusionId ORDER BY FlowSeq) AS rn
        FROM #Flows
        WHERE IsDefault = 1
    )
    UPDATE F SET IsDefault = 0
    FROM #Flows F
    JOIN D ON D.FlowSeq = F.FlowSeq
    WHERE D.rn > 1;

    -- -------------------------------------------------------------------------
    -- 8) Build BPMN XML (Process + DI)
    -- -------------------------------------------------------------------------
    DECLARE @ProcessId nvarchar(200) = 'Process_1';
    DECLARE @CollabId  nvarchar(200) = 'Collaboration_1';
    DECLARE @ParticipantId nvarchar(200) = 'Participant_1';

    -- -------------------------------------------------------------------------
    -- 8.1) BPMN elements (nodes)
    -- -------------------------------------------------------------------------

    -- Start/End/Tasks/CallActivities/Gateways
    DECLARE @ProcessElements xml;
    ;WITH XMLNAMESPACES
    (
        'http://www.omg.org/spec/BPMN/20100524/MODEL' AS bpmn,
        'http://www.omg.org/spec/BPMN/20100524/DI'    AS bpmndi,
        'http://www.omg.org/spec/DD/20100524/DC'      AS dc,
        'http://www.omg.org/spec/DD/20100524/DI'      AS di,
        'http://www.w3.org/2001/XMLSchema-instance'   AS xsi,
        'http://brisk.local/schema/bpmn/ext'          AS brisk
    )
    SELECT @ProcessElements =
    (
        SELECT
            -- StartEvent
            (
                SELECT
                    M.BpmnId AS [@id],
                    COALESCE(M.Name,'') AS [@name],
                    (
                        SELECT
                            -- brisk:actions from RawSet
                            (
                                SELECT
                                    A.N.value('@id','nvarchar(200)') AS [brisk:action/@id],
                                    A.N.value('@actionType','nvarchar(10)') AS [brisk:action/@actionType],
                                    A.N.value('@to','nvarchar(100)') AS [brisk:action/@to],
                                    A.N.value('@nextStageId','nvarchar(100)') AS [brisk:action/@nextStageId],
                                    NULLIF(A.N.value('@decodedCondition','nvarchar(max)'),'') AS [brisk:action/@decodedCondition],
                                    NULLIF(A.N.value('@condition','nvarchar(max)'),'') AS [brisk:action/@condition],
                                    NULLIF(A.N.value('@conditionIndex','nvarchar(50)'),'') AS [brisk:action/@conditionIndex]
                                FROM M.RawSet.nodes('/set/acoes/acao') A(N)
                                FOR XML PATH(''), TYPE
                            )
                        FOR XML PATH('brisk:actions'), TYPE
                    ) AS [bpmn:extensionElements]
                FROM #Map M
                WHERE M.BpmnTag = 'startEvent'
                FOR XML PATH('bpmn:startEvent'), TYPE
            ),
            -- EndEvent
            (
                SELECT
                    M.BpmnId AS [@id],
                    COALESCE(M.Name,'') AS [@name]
                FROM #Map M
                WHERE M.BpmnTag = 'endEvent'
                FOR XML PATH('bpmn:endEvent'), TYPE
            ),
            -- Task
            (
                SELECT
                    M.BpmnId AS [@id],
                    COALESCE(M.Name,'') AS [@name],
                    (
                        SELECT
                            -- descricao
                            NULLIF(M.RawSet.value('(/set/descricao/text())[1]','nvarchar(max)'),'') AS [brisk:descricao],
                            -- prazoPrevisto (attrs)
                            M.RawSet.value('(/set/prazoPrevisto/@timeoutValue)[1]','nvarchar(50)') AS [brisk:prazoPrevisto/@timeoutValue],
                            M.RawSet.value('(/set/prazoPrevisto/@timeoutUnit)[1]','nvarchar(50)') AS [brisk:prazoPrevisto/@timeoutUnit],
                            M.RawSet.value('(/set/prazoPrevisto/@timeoutOffset)[1]','nvarchar(50)') AS [brisk:prazoPrevisto/@timeoutOffset],

                            -- task attrs from <set>
                            M.RawSet.value('(/set/@ocultaBotoesAcao)[1]','nvarchar(10)') AS [brisk:attrs/@ocultaBotoesAcao],
                            M.RawSet.value('(/set/@etapaInicial)[1]','nvarchar(10)') AS [brisk:attrs/@etapaInicial],
                            M.RawSet.value('(/set/@grupoWorkflow)[1]','nvarchar(20)') AS [brisk:attrs/@grupoWorkflow],
                            M.RawSet.value('(/set/@idElementoInicioFluxo)[1]','nvarchar(20)') AS [brisk:attrs/@idElementoInicioFluxo],
                            M.RawSet.value('(/set/@codigoSubfluxo)[1]','nvarchar(20)') AS [brisk:attrs/@codigoSubfluxo],

                            -- formularios
                            (
                                SELECT
                                    F.N.value('@id','nvarchar(50)') AS [brisk:formulario/@id],
                                    F.N.value('@readOnly','nvarchar(10)') AS [brisk:formulario/@readOnly],
                                    F.N.value('@required','nvarchar(10)') AS [brisk:formulario/@required],
                                    F.N.value('@newOnEachOcurrence','nvarchar(10)') AS [brisk:formulario/@newOnEachOcurrence],
                                    F.N.value('@requerAssinaturaDigital','nvarchar(10)') AS [brisk:formulario/@requerAssinaturaDigital],
                                    F.N.value('@originalStageId','nvarchar(20)') AS [brisk:formulario/@originalStageId],
                                    F.N.value('@ordemFormularioEtapa','nvarchar(20)') AS [brisk:formulario/@ordemFormularioEtapa],
                                    F.N.value('@title','nvarchar(400)') AS [brisk:formulario/@title],
                                    F.N.value('@name','nvarchar(400)') AS [brisk:formulario/@name]
                                FROM M.RawSet.nodes('/set/formularios/formulario') F(N)
                                FOR XML PATH(''), TYPE
                            ) AS [brisk:formularios],

                            -- gruposComAcesso
                            (
                                SELECT
                                    G.N.value('@id','nvarchar(50)') AS [brisk:grupo/@id],
                                    G.N.value('@name','nvarchar(400)') AS [brisk:grupo/@name],
                                    G.N.value('@accessType','nvarchar(50)') AS [brisk:grupo/@accessType]
                                FROM M.RawSet.nodes('/set/gruposComAcesso/grupo') G(N)
                                FOR XML PATH(''), TYPE
                            ) AS [brisk:gruposComAcesso],

                            -- actions
                            (
                                SELECT
                                    A.N.value('@id','nvarchar(200)') AS [brisk:action/@id],
                                    A.N.value('@actionType','nvarchar(10)') AS [brisk:action/@actionType],
                                    A.N.value('@to','nvarchar(100)') AS [brisk:action/@to],
                                    A.N.value('@nextStageId','nvarchar(100)') AS [brisk:action/@nextStageId],
                                    NULLIF(A.N.value('@decodedCondition','nvarchar(max)'),'') AS [brisk:action/@decodedCondition],
                                    NULLIF(A.N.value('@condition','nvarchar(max)'),'') AS [brisk:action/@condition],
                                    NULLIF(A.N.value('@conditionIndex','nvarchar(50)'),'') AS [brisk:action/@conditionIndex],
                                    NULLIF(A.N.value('@timeoutValue','nvarchar(50)'),'') AS [brisk:action/@timeoutValue],
                                    NULLIF(A.N.value('@timeoutUnit','nvarchar(50)'),'') AS [brisk:action/@timeoutUnit]
                                FROM M.RawSet.nodes('/set/acoes/acao') A(N)
                                FOR XML PATH(''), TYPE
                            ) AS [brisk:actions]
                        FOR XML PATH(''), TYPE
                    ) AS [bpmn:extensionElements]
                FROM #Map M
                WHERE M.BpmnTag = 'task'
                FOR XML PATH('bpmn:task'), TYPE
            ),
            -- CallActivity
            (
                SELECT
                    M.BpmnId AS [@id],
                    COALESCE(M.Name,'') AS [@name],
                    CONCAT('Process_', M.RawSet.value('(/set/@codigoSubfluxo)[1]','nvarchar(50)')) AS [@calledElement],
                    (
                        SELECT
                            M.RawSet.value('(/set/@codigoSubfluxo)[1]','nvarchar(50)') AS [brisk:codigoSubfluxo],
                            (
                                SELECT
                                    A.N.value('@id','nvarchar(200)') AS [brisk:action/@id],
                                    A.N.value('@actionType','nvarchar(10)') AS [brisk:action/@actionType],
                                    A.N.value('@to','nvarchar(100)') AS [brisk:action/@to],
                                    A.N.value('@nextStageId','nvarchar(100)') AS [brisk:action/@nextStageId]
                                FROM M.RawSet.nodes('/set/acoes/acao') A(N)
                                FOR XML PATH(''), TYPE
                            ) AS [brisk:actions]
                        FOR XML PATH(''), TYPE
                    ) AS [bpmn:extensionElements]
                FROM #Map M
                WHERE M.BpmnTag = 'callActivity'
                FOR XML PATH('bpmn:callActivity'), TYPE
            ),
            -- ExclusiveGateway
            (
                SELECT
                    M.BpmnId AS [@id],
                    COALESCE(M.Name,'') AS [@name],
                    -- default flow reference (if exists)
                    (
                        SELECT TOP 1 F.FlowId
                        FROM #Flows F
                        WHERE F.SourceFusionId = M.FusionId AND F.IsDefault = 1
                        ORDER BY F.FlowSeq
                    ) AS [@default],
                    (
                        SELECT
                            -- expressoes
                            (
                                SELECT
                                    E.N.value('@idEtapaOrigem','nvarchar(50)') AS [brisk:expressoes/@idEtapaOrigem],
                                    E.N.value('@nomeOpcao','nvarchar(200)')    AS [brisk:expressoes/@nomeOpcao],
                                    E.N.value('@idEtapaPadrao','nvarchar(50)') AS [brisk:expressoes/@idEtapaPadrao],
                                    (
                                        SELECT
                                            X.N.value('@id','nvarchar(50)') AS [brisk:expressao/@id],
                                            X.N.value('@extenso','nvarchar(max)') AS [brisk:expressao/@extenso],
                                            X.N.value('@avaliada','nvarchar(max)') AS [brisk:expressao/@avaliada]
                                        FROM E.N.nodes('expressao') X(N)
                                        FOR XML PATH(''), TYPE
                                    )
                                FROM M.RawSet.nodes('/set/expressoes') E(N)
                                FOR XML PATH(''), TYPE
                            ) AS [brisk:expressoes],
                            -- actions
                            (
                                SELECT
                                    A.N.value('@id','nvarchar(200)') AS [brisk:action/@id],
                                    A.N.value('@actionType','nvarchar(10)') AS [brisk:action/@actionType],
                                    A.N.value('@to','nvarchar(100)') AS [brisk:action/@to],
                                    A.N.value('@nextStageId','nvarchar(100)') AS [brisk:action/@nextStageId],
                                    NULLIF(A.N.value('@decodedCondition','nvarchar(max)'),'') AS [brisk:action/@decodedCondition],
                                    NULLIF(A.N.value('@condition','nvarchar(max)'),'') AS [brisk:action/@condition],
                                    NULLIF(A.N.value('@conditionIndex','nvarchar(50)'),'') AS [brisk:action/@conditionIndex]
                                FROM M.RawSet.nodes('/set/acoes/acao') A(N)
                                FOR XML PATH(''), TYPE
                            ) AS [brisk:actions]
                        FOR XML PATH(''), TYPE
                    ) AS [bpmn:extensionElements]
                FROM #Map M
                WHERE M.BpmnTag = 'exclusiveGateway'
                FOR XML PATH('bpmn:exclusiveGateway'), TYPE
            ),
            -- ParallelGateway (split/join)
            (
                SELECT
                    M.BpmnId AS [@id],
                    COALESCE(M.Name,'') AS [@name]
                FROM #Map M
                WHERE M.BpmnTag = 'parallelGateway'
                FOR XML PATH('bpmn:parallelGateway'), TYPE
            ),
            -- Inserted merge gateways (exclusive) already in #Map (tag exclusiveGateway)
            (
                SELECT
                    M.BpmnId AS [@id],
                    COALESCE(M.Name,'') AS [@name]
                FROM #Map M
                WHERE M.TipoElemento = 7000
                FOR XML PATH('bpmn:exclusiveGateway'), TYPE
            ),
            -- Boundary Timer Events
            (
                SELECT
                    EM.BpmnId AS [@id],
                    EM.AttachedTo AS [@attachedToRef],
                    CASE WHEN EM.CancelActivity = 1 THEN 'true' ELSE 'false' END AS [@cancelActivity],
                    (
                        SELECT
                            EM.TimeDuration AS [bpmn:timeDuration]
                        FOR XML PATH('bpmn:timerEventDefinition'), TYPE
                    )
                FROM #ExtraMap EM
                WHERE EM.BpmnTag = 'boundaryEvent'
                FOR XML PATH('bpmn:boundaryEvent'), TYPE
            )
FOR XML PATH(''), TYPE
    );

    -- -------------------------------------------------------------------------
    -- 8.2) Sequence Flows with optional conditionExpression
    -- -------------------------------------------------------------------------
    DECLARE @FlowsXml xml;

    ;WITH XMLNAMESPACES (
        'http://www.omg.org/spec/BPMN/20100524/MODEL' AS bpmn,
        'http://www.w3.org/2001/XMLSchema-instance' AS xsi
    )
    SELECT @FlowsXml =
    (
        SELECT
            F.FlowId AS [@id],
            F.SourceBpmnId AS [@sourceRef],
            F.TargetBpmnId AS [@targetRef],
            F.Label AS [@name],
            CASE 
                WHEN F.ConditionText IS NULL THEN NULL
                ELSE
                    (
                        SELECT
                            'bpmn:tFormalExpression' AS [bpmn:conditionExpression/@xsi:type],
                            F.ConditionText          AS [bpmn:conditionExpression]
                        FOR XML PATH(''), TYPE
                    )
            END
        FROM #Flows F
        ORDER BY F.FlowSeq
        FOR XML PATH('bpmn:sequenceFlow'), TYPE
    );

    -- -------------------------------------------------------------------------
    -- -------------------------------------------------------------------------
    -- 8.3) BPMN DI (Shapes)
    -- -------------------------------------------------------------------------
    DECLARE @ShapesXml xml;

    ;WITH XMLNAMESPACES
    (
        'http://www.omg.org/spec/BPMN/20100524/DI'    AS bpmndi,
        'http://www.omg.org/spec/DD/20100524/DC'      AS dc,
        'http://www.omg.org/spec/DD/20100524/DI'      AS di,
        'http://www.omg.org/spec/BPMN/20100524/MODEL' AS bpmn
    )
    SELECT @ShapesXml =
    (
        SELECT
            S.ShapeId     AS [@id],
            S.BpmnElement AS [@bpmnElement],
            (
                SELECT
                    S.Bx  AS [@x],
                    S.BY_ AS [@y],
                    S.Bw  AS [@width],
                    S.Bh  AS [@height]
                FOR XML PATH('dc:Bounds'), TYPE
            ) AS [*]
        FROM
        (
            SELECT
                CONCAT('Shape_', M.BpmnId) AS ShapeId,
                M.BpmnId                  AS BpmnElement,
                M.X                       AS Bx,
                M.Y                       AS BY_,
                M.W                       AS Bw,
                M.H                       AS Bh
            FROM #Map M

            UNION ALL

            SELECT
                CONCAT('Shape_', EM.BpmnId) AS ShapeId,
                EM.BpmnId                   AS BpmnElement,
                EM.X                        AS Bx,
                EM.Y                        AS BY_,
                EM.W                        AS Bw,
                EM.H                        AS Bh
            FROM #ExtraMap EM
        ) S
        FOR XML PATH('bpmndi:BPMNShape'), TYPE
    );

-- -------------------------------------------------------------------------
    -- -------------------------------------------------------------------------
    -- 8.4) BPMN DI (Edges with 2 waypoints: center -> center)
    -- -------------------------------------------------------------------------
    DECLARE @EdgesXml xml;

    ;WITH XMLNAMESPACES
    (
        'http://www.omg.org/spec/BPMN/20100524/DI'    AS bpmndi,
        'http://www.omg.org/spec/DD/20100524/DI'      AS di,
        'http://www.omg.org/spec/BPMN/20100524/MODEL' AS bpmn
    )
    SELECT @EdgesXml =
    (
        SELECT
            CONCAT('Edge_', F.FlowId) AS [@id],
            F.FlowId                  AS [@bpmnElement],
            (
    SELECT
        WP.[x] AS [@x],
        WP.[y] AS [@y]
    FROM
    (
        SELECT
            1 AS Seq,
            CASE
                WHEN EXISTS (SELECT 1 FROM #ExtraMap EM WHERE EM.BpmnId = F.SourceBpmnId)
                    THEN (SELECT EM.Cx FROM #ExtraMap EM WHERE EM.BpmnId = F.SourceBpmnId)
                ELSE (SELECT (M.X + (M.W / 2.0)) FROM #Map M WHERE M.BpmnId = F.SourceBpmnId)
            END AS [x],
            CASE
                WHEN EXISTS (SELECT 1 FROM #ExtraMap EM WHERE EM.BpmnId = F.SourceBpmnId)
                    THEN (SELECT EM.Cy FROM #ExtraMap EM WHERE EM.BpmnId = F.SourceBpmnId)
                ELSE (SELECT (M.Y + (M.H / 2.0)) FROM #Map M WHERE M.BpmnId = F.SourceBpmnId)
            END AS [y]

        UNION ALL

        SELECT
            2 AS Seq,
            CASE
                WHEN EXISTS (SELECT 1 FROM #ExtraMap EM WHERE EM.BpmnId = F.TargetBpmnId)
                    THEN (SELECT EM.Cx FROM #ExtraMap EM WHERE EM.BpmnId = F.TargetBpmnId)
                ELSE (SELECT (M.X + (M.W / 2.0)) FROM #Map M WHERE M.BpmnId = F.TargetBpmnId)
            END AS [x],
            CASE
                WHEN EXISTS (SELECT 1 FROM #ExtraMap EM WHERE EM.BpmnId = F.TargetBpmnId)
                    THEN (SELECT EM.Cy FROM #ExtraMap EM WHERE EM.BpmnId = F.TargetBpmnId)
                ELSE (SELECT (M.Y + (M.H / 2.0)) FROM #Map M WHERE M.BpmnId = F.TargetBpmnId)
            END AS [y]
    ) WP
    ORDER BY WP.Seq
    FOR XML PATH('di:waypoint'), TYPE
) AS [*]
        FROM #Flows F
        ORDER BY F.FlowSeq
        FOR XML PATH('bpmndi:BPMNEdge'), TYPE
    );

-- -------------------------------------------------------------------------
    -- 9) Final BPMN document with namespaces (BPMN 2.0 + DI + brisk)
    -- -------------------------------------------------------------------------
    ;WITH XMLNAMESPACES
    (
        'http://www.omg.org/spec/BPMN/20100524/MODEL' AS bpmn,
        'http://www.omg.org/spec/BPMN/20100524/DI'    AS bpmndi,
        'http://www.omg.org/spec/DD/20100524/DC'      AS dc,
        'http://www.omg.org/spec/DD/20100524/DI'      AS di,
        'http://www.w3.org/2001/XMLSchema-instance'   AS xsi,
        'http://brisk.local/schema/bpmn/ext'          AS brisk
    )
    SELECT @BpmnXml =
    (
        SELECT
            'Definitions_1' AS [@id],
            'http://bpmn.io/schema/bpmn' AS [@targetNamespace],

            -- collaboration with a single participant
            (
                SELECT
                    @CollabId AS [@id],
                    (
                        SELECT
                            @ParticipantId AS [@id],
                            'Process Participant' AS [@name],
                            @ProcessId AS [@processRef]
                        FOR XML PATH('bpmn:participant'), TYPE
                    )
                FOR XML PATH('bpmn:collaboration'), TYPE
            ),

            -- process
            (
                SELECT
                    @ProcessId AS [@id],
                    'false' AS [@isExecutable],
                    @ProcessElements AS [*],
                    @FlowsXml AS [*]
                FOR XML PATH('bpmn:process'), TYPE
            ),

            -- diagram
            (
                SELECT
                    'BPMNDiagram_1' AS [@id],
                    (
                        SELECT
                            'BPMNPlane_1' AS [@id],
                            @ProcessId AS [@bpmnElement],
                            @ShapesXml AS [*],
                            @EdgesXml AS [*]
                        FOR XML PATH('bpmndi:BPMNPlane'), TYPE
                    )
                FOR XML PATH('bpmndi:BPMNDiagram'), TYPE
            )
        FOR XML PATH('bpmn:definitions'), TYPE
    );

END
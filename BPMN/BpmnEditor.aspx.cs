using CDIS;
using System;
using System.Collections.Generic;
using System.Collections.Specialized;
using System.Configuration;
using System.Data;
using System.IO;
using System.Linq;
using System.Net;
using System.Text;
using System.Text.RegularExpressions;
using System.Web;
using System.Web.Script.Serialization;
using System.Web.Services;
using System.Xml.Linq;

public partial class BpmnEditor : System.Web.UI.Page
{
    protected int ModelId = 0;
    protected bool HasOpenAiKey = false;
    protected bool IsReadOnly = false;

    protected void Page_Load(object sender, EventArgs e)
    {
        int id;
        ModelId = int.TryParse(Request.QueryString["id"], out id) ? id : 0;
        HasOpenAiKey = !string.IsNullOrWhiteSpace(GetOpenAiApiKey());

        var mode = (Request.QueryString["mode"] ?? "").ToLowerInvariant();
        var requestedReadOnly = mode == "view" || mode == "readonly";
        IsReadOnly = requestedReadOnly || !CanEditWorkflow(ModelId);
    }

    public class BpmnModelDto
    {
        public int Id { get; set; }
        public string Name { get; set; }
        public string ModelXml { get; set; }
        public string Description { get; set; }
        public bool IsAutomation { get; set; }
        public bool HasPublication { get; set; }
        public bool HasRevocation { get; set; }
    }

    public class AiResultDto
    {
        public string ModelXml { get; set; }
        public string RawText { get; set; }
    }

    private static string EscapeSql(string s)
    {
        return (s ?? "").Replace("'", "''");
    }

    private static bool HasDateValue(object value)
    {
        return value != null && value != DBNull.Value;
    }

    private class WorkflowMeta
    {
        public int CodigoWorkflow { get; set; }
        public int CodigoFluxo { get; set; }
        public bool IsAutomation { get; set; }
        public bool HasPublication { get; set; }
        public bool HasRevocation { get; set; }
    }

    private static WorkflowMeta GetWorkflowMeta(int codigoWorkflow)
    {
        if (codigoWorkflow <= 0) return null;

        OrderedDictionary listaParametrosDados = new OrderedDictionary();
        listaParametrosDados["RemoteIPUsuario"] = HttpContext.Current.Session["RemoteIPUsuario"] + "";
        listaParametrosDados["NomeUsuario"] = HttpContext.Current.Session["NomeUsuario"] + "";
        var cd = CdadosUtil.GetCdados(listaParametrosDados);
        var db = cd.getDbName();
        var own = cd.getDbOwner();

        string sql = string.Format(@"
            SELECT w.CodigoWorkflow,
                   w.CodigoFluxo,
                   w.DataPublicacao,
                   w.DataRevogacao,
                   f.IndicaAutomacao
              FROM [{0}].[{1}].Workflows w INNER JOIN
                   [{0}].[{1}].Fluxos f ON f.CodigoFluxo = w.CodigoFluxo
             WHERE w.CodigoWorkflow = {2};
        ", db, own, codigoWorkflow);

        DataSet ds = cd.getDataSet(sql);
        if (ds == null || ds.Tables.Count == 0 || ds.Tables[0].Rows.Count == 0)
            return null;

        var row = ds.Tables[0].Rows[0];
        return new WorkflowMeta
        {
            CodigoWorkflow = Convert.ToInt32(row["CodigoWorkflow"]),
            CodigoFluxo = Convert.ToInt32(row["CodigoFluxo"]),
            IsAutomation = Convert.ToString(row["IndicaAutomacao"]) == "S",
            HasPublication = HasDateValue(row["DataPublicacao"]),
            HasRevocation = HasDateValue(row["DataRevogacao"])
        };
    }

    private static void UpdateFluxoDetails(CdadosUtil cd, int codigoWorkflow, string name, string description)
    {
        var db = cd.getDbName();
        var own = cd.getDbOwner();
        string sqlFluxo = string.Format(@"
            UPDATE f
               SET f.NomeFluxo = '{2}',
                   f.DescricaoBPMN = '{3}'
              FROM [{0}].[{1}].Fluxos f INNER JOIN
                   [{0}].[{1}].Workflows w ON w.CodigoFluxo = f.CodigoFluxo
             WHERE w.CodigoWorkflow = {4};
        ", db, own, EscapeSql(name), EscapeSql(description), codigoWorkflow);

        int afetadosFluxo = 0;
        cd.execSQL(sqlFluxo, ref afetadosFluxo);
    }

    private static void UpdateWorkflowXml(CdadosUtil cd, int codigoWorkflow, string modelXml)
    {
        var db = cd.getDbName();
        var own = cd.getDbOwner();

        string sqlWorkflow = string.Format(@"
            UPDATE [{0}].[{1}].Workflows
               SET TextoXMLBPMN = '{2}'
             WHERE CodigoWorkflow = {3};
        ", db, own, EscapeSql(modelXml), codigoWorkflow);

        int afetadosWorkflow = 0;
        cd.execSQL(sqlWorkflow, ref afetadosWorkflow);

        if (afetadosWorkflow <= 0)
            throw new Exception("Nenhum registro foi atualizado.");
    }

    private static bool CanEditWorkflow(int codigoWorkflow)
    {
        if (codigoWorkflow <= 0) return true;

        OrderedDictionary listaParametrosDados = new OrderedDictionary();
        listaParametrosDados["RemoteIPUsuario"] = HttpContext.Current.Session["RemoteIPUsuario"] + "";
        listaParametrosDados["NomeUsuario"] = HttpContext.Current.Session["NomeUsuario"] + "";
        var cd = CdadosUtil.GetCdados(listaParametrosDados);
        var db = cd.getDbName();
        var own = cd.getDbOwner();

        string sql = string.Format(@"
            SELECT f.IndicaAutomacao,
                   w.DataPublicacao,
                   w.DataRevogacao
              FROM Workflows w INNER JOIN
                   Fluxos f ON f.CodigoFluxo = w.CodigoFluxo
             WHERE w.CodigoWorkflow = {2};
        ", db, own, codigoWorkflow);

        DataSet ds = cd.getDataSet(sql);
        if (ds == null || ds.Tables.Count == 0 || ds.Tables[0].Rows.Count == 0)
            return false;

        var row = ds.Tables[0].Rows[0];
        var isAutomation = Convert.ToString(row["IndicaAutomacao"]) == "S";
        if (!isAutomation) return true;

        var hasPublication = HasDateValue(row["DataPublicacao"]);
        var hasRevocation = HasDateValue(row["DataRevogacao"]);
        return hasPublication && !hasRevocation;
    }

    [WebMethod(EnableSession = true)]
    public static BpmnModelDto GetModel(int id)
    {
        OrderedDictionary listaParametrosDados = new OrderedDictionary();
        listaParametrosDados["RemoteIPUsuario"] = HttpContext.Current.Session["RemoteIPUsuario"] + "";
        listaParametrosDados["NomeUsuario"] = HttpContext.Current.Session["NomeUsuario"] + "";
        var cd = CdadosUtil.GetCdados(listaParametrosDados);

        var db = cd.getDbName();
        var own = cd.getDbOwner();

        string sql = string.Format(@"
            SELECT w.CodigoWorkflow,
                   f.NomeFluxo,
                   w.TextoXMLBPMN,
                   f.DescricaoBPMN,
                   f.IndicaAutomacao,
                   w.DataPublicacao,
                   w.DataRevogacao
              FROM [{0}].[{1}].Workflows w INNER JOIN
                   [{0}].[{1}].Fluxos f ON f.CodigoFluxo = w.CodigoFluxo
             WHERE w.CodigoWorkflow = {2};
        ", db, own, id);

        DataSet ds = cd.getDataSet(sql);

        if (ds == null || ds.Tables.Count == 0 || ds.Tables[0].Rows.Count == 0)
            throw new Exception("Modelo não encontrado.");

        var r = ds.Tables[0].Rows[0];

        return new BpmnModelDto
        {
            Id = Convert.ToInt32(r["CodigoWorkflow"]),
            Name = Convert.ToString(r["NomeFluxo"]),
            ModelXml = Convert.ToString(r["TextoXMLBPMN"]),
            Description = Convert.ToString(r["DescricaoBPMN"]),
            IsAutomation = Convert.ToString(r["IndicaAutomacao"]) == "S",
            HasPublication = HasDateValue(r["DataPublicacao"]),
            HasRevocation = HasDateValue(r["DataRevogacao"])
        };
    }

    [WebMethod(EnableSession = true)]
    public static int SaveModel(int id, string name, string modelXml, string description)
    {
        if (id <= 0) throw new Exception("Id inválido.");
        name = (name ?? "").Trim();
        if (string.IsNullOrWhiteSpace(name)) throw new Exception("Nome inválido.");
        if (string.IsNullOrWhiteSpace(modelXml)) throw new Exception("XML inválido.");
        description = (description ?? "").Trim();

        var meta = GetWorkflowMeta(id);
        if (meta == null) throw new Exception("Workflow não encontrado.");

        if (meta.IsAutomation && (!meta.HasPublication || meta.HasRevocation))
            throw new Exception("Fluxo somente leitura.");

        OrderedDictionary listaParametrosDados = new OrderedDictionary();
        listaParametrosDados["RemoteIPUsuario"] = HttpContext.Current.Session["RemoteIPUsuario"] + "";
        listaParametrosDados["NomeUsuario"] = HttpContext.Current.Session["NomeUsuario"] + "";
        var cd = CdadosUtil.GetCdados(listaParametrosDados);

        UpdateFluxoDetails(cd, id, name, description);

        if (meta.IsAutomation && meta.HasPublication && !meta.HasRevocation)
        {
            UpdateWorkflowXml(cd, id, modelXml);
            return id;
        }

        if (!meta.IsAutomation && meta.HasPublication)
        {
            var db = cd.getDbName();
            var own = cd.getDbOwner();
            string sqlCreateDraft = string.Format(@"
                INSERT INTO [{0}].[{1}].Workflows (CodigoFluxo, TextoXMLBPMN, DataPublicacao, DataRevogacao, UsuarioPublicacao)
                SELECT CodigoFluxo, TextoXMLBPMN, NULL, NULL, NULL
                  FROM [{0}].[{1}].Workflows
                 WHERE CodigoWorkflow = {2};
                SELECT CAST(SCOPE_IDENTITY() AS INT) AS NewId;
            ", db, own, id);

            DataSet dsNew = cd.getDataSet(sqlCreateDraft);
            if (dsNew == null || dsNew.Tables.Count == 0 || dsNew.Tables[0].Rows.Count == 0)
                throw new Exception("Falha ao criar nova versão.");

            int newId = Convert.ToInt32(dsNew.Tables[0].Rows[0]["NewId"]);
            if (newId <= 0) throw new Exception("Falha ao criar nova versão.");

            UpdateWorkflowXml(cd, newId, modelXml);
            return newId;
        }

        UpdateWorkflowXml(cd, id, modelXml);
        return id;
    }

    [WebMethod(EnableSession = true)]
    public static void PublishModel(int id, string name, string modelXml, string description)
    {
        if (id <= 0) throw new Exception("Id inválido.");
        name = (name ?? "").Trim();
        if (string.IsNullOrWhiteSpace(name)) throw new Exception("Nome inválido.");
        if (string.IsNullOrWhiteSpace(modelXml)) throw new Exception("XML inválido.");
        description = (description ?? "").Trim();

        var meta = GetWorkflowMeta(id);
        if (meta == null) throw new Exception("Workflow não encontrado.");

        if (meta.IsAutomation || meta.HasPublication)
            throw new Exception("Publicação não disponível para este fluxo.");

        ValidateBpmnXml(modelXml);

        OrderedDictionary listaParametrosDados = new OrderedDictionary();
        listaParametrosDados["RemoteIPUsuario"] = HttpContext.Current.Session["RemoteIPUsuario"] + "";
        listaParametrosDados["NomeUsuario"] = HttpContext.Current.Session["NomeUsuario"] + "";
        var cd = CdadosUtil.GetCdados(listaParametrosDados);

        UpdateFluxoDetails(cd, id, name, description);

        var db = cd.getDbName();
        var own = cd.getDbOwner();

        string sqlRevokePrevious = string.Format(@"
            UPDATE [{0}].[{1}].Workflows
               SET DataRevogacao = GETDATE()
             WHERE CodigoFluxo = {2}
               AND DataPublicacao IS NOT NULL
               AND DataRevogacao IS NULL
               AND CodigoWorkflow <> {3};
        ", db, own, meta.CodigoFluxo, id);

        int afetadosRevogacao = 0;
        cd.execSQL(sqlRevokePrevious, ref afetadosRevogacao);

        string usuario = (HttpContext.Current.Session["NomeUsuario"] ?? "").ToString();
        string sqlPublish = string.Format(@"
            UPDATE [{0}].[{1}].Workflows
               SET TextoXMLBPMN = '{2}',
                   DataPublicacao = GETDATE(),
                   UsuarioPublicacao = '{3}'
             WHERE CodigoWorkflow = {4};
        ", db, own, EscapeSql(modelXml), EscapeSql(usuario), id);

        int afetadosPublish = 0;
        cd.execSQL(sqlPublish, ref afetadosPublish);

        if (afetadosPublish <= 0)
            throw new Exception("Nenhum registro foi atualizado.");
    }

    private static void ValidateBpmnXml(string modelXml)
    {
        try
        {
            var doc = XDocument.Parse(modelXml);
            XNamespace bpmn = "http://www.omg.org/spec/BPMN/20100524/MODEL";

            var process = doc.Descendants(bpmn + "process").FirstOrDefault();
            if (process == null)
                throw new Exception("XML não contém um processo BPMN válido.");

            var flowNodes = process.Elements()
                .Where(el => el.Name.Namespace == bpmn)
                .Where(el => el.Name.LocalName.EndsWith("Event") ||
                             el.Name.LocalName.EndsWith("Task") ||
                             el.Name.LocalName.EndsWith("Gateway") ||
                             el.Name.LocalName == "subProcess" ||
                             el.Name.LocalName == "callActivity")
                .ToList();

            var flowNodeIds = flowNodes
                .Select(el => (string)el.Attribute("id"))
                .Where(id => !string.IsNullOrWhiteSpace(id))
                .ToHashSet(StringComparer.OrdinalIgnoreCase);

            var startEvents = process.Elements(bpmn + "startEvent").ToList();
            if (startEvents.Count != 1)
                throw new Exception("O processo deve conter exatamente um evento de início.");

            var endEvents = process.Elements(bpmn + "endEvent").ToList();
            if (endEvents.Count < 1)
                throw new Exception("O processo deve conter pelo menos um evento de fim.");

            var sequenceFlows = process.Elements(bpmn + "sequenceFlow").ToList();
            if (sequenceFlows.Count == 0)
                throw new Exception("O processo deve conter ao menos um fluxo de sequência.");

            var edges = sequenceFlows
                .Select(flow => new
                {
                    Source = (string)flow.Attribute("sourceRef"),
                    Target = (string)flow.Attribute("targetRef")
                })
                .ToList();

            foreach (var edge in edges)
            {
                if (string.IsNullOrWhiteSpace(edge.Source) || string.IsNullOrWhiteSpace(edge.Target))
                    throw new Exception("Há um fluxo de sequência com origem ou destino vazio.");
                if (!flowNodeIds.Contains(edge.Source) || !flowNodeIds.Contains(edge.Target))
                    throw new Exception("Há um fluxo de sequência com origem ou destino inexistente.");
            }

            var startId = (string)startEvents[0].Attribute("id");
            if (string.IsNullOrWhiteSpace(startId))
                throw new Exception("Evento de início sem identificador.");

            var endIds = endEvents
                .Select(end => (string)end.Attribute("id"))
                .Where(id => !string.IsNullOrWhiteSpace(id))
                .ToHashSet(StringComparer.OrdinalIgnoreCase);
            if (endIds.Count == 0)
                throw new Exception("Evento de fim sem identificador.");

            var adjacency = edges
                .GroupBy(edge => edge.Source)
                .ToDictionary(group => group.Key, group => group.Select(edge => edge.Target).ToList(), StringComparer.OrdinalIgnoreCase);

            var visited = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            var queue = new Queue<string>();
            queue.Enqueue(startId);
            visited.Add(startId);

            while (queue.Count > 0)
            {
                var current = queue.Dequeue();
                if (!adjacency.TryGetValue(current, out var targets)) continue;
                foreach (var target in targets)
                {
                    if (visited.Add(target))
                        queue.Enqueue(target);
                }
            }

            if (!visited.Overlaps(endIds))
                throw new Exception("O fluxo deve terminar em um evento de fim.");

            var outgoingBySource = edges
                .GroupBy(edge => edge.Source)
                .ToDictionary(group => group.Key, group => group.Count(), StringComparer.OrdinalIgnoreCase);

            foreach (var gateway in process.Elements(bpmn + "exclusiveGateway"))
            {
                var gatewayId = (string)gateway.Attribute("id");
                if (string.IsNullOrWhiteSpace(gatewayId)) continue;
                if (!outgoingBySource.TryGetValue(gatewayId, out var count) || count < 2)
                    throw new Exception("Gateway exclusivo deve ter no mínimo duas saídas.");
            }

            var disconnected = flowNodeIds.Where(id => !visited.Contains(id)).ToList();
            if (disconnected.Count > 0)
                throw new Exception("Existem elementos desconectados no fluxo.");
        }
        catch (Exception ex)
        {
            throw new Exception("Fluxo inválido: " + ex.Message);
        }
    }

    // ============================================================
    //  OPENAI KEY (web.config + fallback WebCDIS.Config)
    // ============================================================
    private static string GetOpenAiApiKey()
    {
        // 1) tenta appSettings normal (web.config já mesclado)
        var k = ConfigurationManager.AppSettings["OpenAI_ApiKey"];
        if (!string.IsNullOrWhiteSpace(k)) return k.Trim();

        // 2) fallback: lê diretamente o arquivo apontado pelo <appSettings file="...">
        try
        {
            var path = HttpContext.Current.Server.MapPath("~/WebCDIS.Config");
            if (!File.Exists(path)) return null;

            var txt = File.ReadAllText(path);

            var m = Regex.Match(
                txt,
                "<add\\s+key\\s*=\\s*\"OpenAI_ApiKey\"\\s+value\\s*=\\s*\"(?<v>[^\"]*)\"\\s*/?>",
                RegexOptions.IgnoreCase
            );

            if (m.Success)
                return (m.Groups["v"].Value ?? "").Trim();
        }
        catch { }

        return null;
    }

    // ============================================================
    //  PROMPT PADRÃO (regras) + chamada OpenAI
    // ============================================================

    private static string BuildSystemPrompt_Step1_ProcessOnly()
    {
        return
    @"Você é um gerador de BPMN 2.0 para BPMN.io.

OBJETIVO (ETAPA 1):
- Gerar/aplicar alterações SOMENTE na parte de PROCESSO (bpmn:process) do BPMN.
- Retornar um XML BPMN 2.0 VÁLIDO, porém SEM BPMNDI (sem layout).

REGRAS OBRIGATÓRIAS:
- Responda SOMENTE com XML BPMN 2.0 válido.
- NÃO use markdown.
- NÃO escreva explicações, comentários ou texto fora do XML.
- NÃO inclua <bpmndi:BPMNDiagram>, <bpmndi:BPMNPlane>, <bpmndi:BPMNShape>, <bpmndi:BPMNEdge>.

REQUISITOS DO XML:
- Deve conter <bpmn:definitions> com namespace BPMN.
- Deve conter <bpmn:process>.
- IDs devem ser únicos e estáveis.
- Não pode haver elementos desconectados.
- Exatamente UM startEvent.
- Pelo menos UM endEvent.
- Todo exclusiveGateway com no mínimo DUAS saídas.
- O fluxo deve começar no startEvent e terminar em um endEvent.

COMPORTAMENTO:
- Se existir um XML atual fornecido, ajuste o diagrama existente ao invés de criar um novo, sempre que possível.
";
    }

    private static string BuildSystemPrompt_Step2_AddLayout()
    {
        return
    @"Você é um gerador de layout BPMNDI para BPMN.io.

OBJETIVO (ETAPA 2):
- Receber um BPMN 2.0 com <bpmn:process> pronto e adicionar SOMENTE o layout BPMNDI.
- Retornar um XML BPMN 2.0 VÁLIDO para BPMN.io, contendo BPMNDI/DC/DI.

REGRAS OBRIGATÓRIAS:
- Responda SOMENTE com XML BPMN 2.0 válido.
- NÃO use markdown.
- NÃO escreva explicações, comentários ou texto fora do XML.
- NÃO altere o processo: NÃO mude nomes, NÃO mude IDs, NÃO adicione/remova tarefas, gateways, eventos ou flows.
- Somente adicione/complete:
  - namespaces di/dc/bpmndi (se faltarem)
  - <bpmn:collaboration> e <bpmn:participant> (se necessário)
  - <bpmndi:BPMNDiagram>, <bpmndi:BPMNPlane>, shapes/edges e Bounds/Waypoints

REQUISITOS DO LAYOUT:
- Cada elemento do process deve ter um BPMNShape com dc:Bounds.
- Cada sequenceFlow deve ter um BPMNEdge com di:waypoint.
- Posicione em fluxo da esquerda para direita, evitando sobreposição.
- Mantenha isHorizontal=true no Participant quando usar Collaboration.

RESULTADO:
- O XML final deve conter <bpmn:definitions>, <bpmn:process> e <bpmndi:BPMNDiagram>.
";
    }


    private static string BuildUserPrompt(string userPrompt, string currentModelXml)
    {
        // normalização simples para reduzir ruído
        userPrompt = (userPrompt ?? "").Trim();
        currentModelXml = currentModelXml ?? "";

        // Limita tamanho para evitar explodir tokens (ajuste como quiser)
        if (userPrompt.Length > 1500) userPrompt = userPrompt.Substring(0, 1500);

        // Não mexo no XML atual, só anexo
        return
            "DESCRIÇÃO DO PROCESSO PELO USUÁRIO:\n" + userPrompt + "\n\n" +
            "XML ATUAL (se existir, pode estar vazio):\n" + currentModelXml;
    }

    private static string BuildUserPrompt_Step1(string userPrompt, string currentModelXml)
    {
        userPrompt = (userPrompt ?? "").Trim();
        currentModelXml = currentModelXml ?? "";

        if (userPrompt.Length > 1500) userPrompt = userPrompt.Substring(0, 1500);

        return
            "ETAPA 1 - GERAR PROCESSO (SEM BPMNDI)\n" +
            "DESCRIÇÃO DO PROCESSO PELO USUÁRIO:\n" + userPrompt + "\n\n" +
            "XML ATUAL (pode estar vazio):\n" + currentModelXml;
    }

    private static string BuildUserPrompt_Step2(string processOnlyXml)
    {
        processOnlyXml = (processOnlyXml ?? "").Trim();

        return
            "ETAPA 2 - ADICIONAR BPMNDI (LAYOUT)\n" +
            "A seguir está o BPMN com o processo pronto. " +
            "Adicione SOMENTE o BPMNDI/DC/DI e o necessário para o BPMN.io renderizar. " +
            "NÃO altere o processo nem IDs.\n\n" +
            "BPMN (PROCESSO SEM LAYOUT):\n" + processOnlyXml;
    }


    [WebMethod(EnableSession = true)]
    public static AiResultDto GenerateFromAi(string prompt, string currentModelXml)
    {
        prompt = (prompt ?? "").Trim();
        if (string.IsNullOrWhiteSpace(prompt))
            throw new Exception("Prompt vazio.");

        var apiKey = GetOpenAiApiKey();
        if (string.IsNullOrWhiteSpace(apiKey))
            throw new Exception("OpenAI_ApiKey não configurada no WebCDIS.Config/web.config.");

        // ============================================================
        // ETAPA 1: gerar processo SEM BPMNDI
        // ============================================================
        var system1 = BuildSystemPrompt_Step1_ProcessOnly();
        var user1 = BuildUserPrompt_Step1(prompt, currentModelXml);

        var payload1 = "{"
            + "\"model\":\"gpt-5-mini\","
            + "\"input\":["
            + "{\"role\":\"system\",\"content\":[{\"type\":\"input_text\",\"text\":" + EscapeForJson(system1) + "}]},"
            + "{\"role\":\"user\",\"content\":[{\"type\":\"input_text\",\"text\":" + EscapeForJson(user1) + "}]}]"
            + ",\"reasoning\":{\"effort\":\"minimal\"}"
            + ",\"text\":{\"verbosity\":\"low\",\"format\":{\"type\":\"text\"}}"
            + ",\"max_output_tokens\":12000"
            + "}";

        var resp1 = PostJson("https://api.openai.com/v1/responses", apiKey, payload1);
        var processXml = ExtractDiagramXmlFromResponsesApi(resp1);

        // validação mínima da etapa 1
        if (string.IsNullOrWhiteSpace(processXml) ||
            processXml.IndexOf("<bpmn:definitions", StringComparison.OrdinalIgnoreCase) < 0 ||
            processXml.IndexOf("<bpmn:process", StringComparison.OrdinalIgnoreCase) < 0 ||
            processXml.IndexOf("</bpmn:definitions>", StringComparison.OrdinalIgnoreCase) < 0)
        {
            throw new Exception("ETAPA 1: A IA não retornou um XML BPMN válido (processo).");
        }

        // garantir que NÃO veio BPMNDI (para manter a proposta)
        // (se vier, ainda funciona, mas a ideia é evitar blow-up de tokens)
        // então não falho, só limpo o risco: se detectar BPMNDI, seguimos mesmo assim.
        // if (processXml.IndexOf("bpmndi:BPMNDiagram", StringComparison.OrdinalIgnoreCase) >= 0) { ... }

        // ============================================================
        // ETAPA 2: adicionar layout BPMNDI (sem alterar processo)
        // ============================================================
        var system2 = BuildSystemPrompt_Step2_AddLayout();
        var user2 = BuildUserPrompt_Step2(processXml);

        var payload2 = "{"
            + "\"model\":\"gpt-5-mini\","
            + "\"input\":["
            + "{\"role\":\"system\",\"content\":[{\"type\":\"input_text\",\"text\":" + EscapeForJson(system2) + "}]},"
            + "{\"role\":\"user\",\"content\":[{\"type\":\"input_text\",\"text\":" + EscapeForJson(user2) + "}]}]"
            + ",\"reasoning\":{\"effort\":\"minimal\"}"
            + ",\"text\":{\"verbosity\":\"low\",\"format\":{\"type\":\"text\"}}"
            + ",\"max_output_tokens\":12000"
            + "}";

        var resp2 = PostJson("https://api.openai.com/v1/responses", apiKey, payload2);
        var finalXml = ExtractDiagramXmlFromResponsesApi(resp2);

        // validação mínima da etapa 2
        if (string.IsNullOrWhiteSpace(finalXml) ||
            finalXml.IndexOf("<bpmn:definitions", StringComparison.OrdinalIgnoreCase) < 0 ||
            finalXml.IndexOf("<bpmn:process", StringComparison.OrdinalIgnoreCase) < 0 ||
            finalXml.IndexOf("bpmndi:BPMNDiagram", StringComparison.OrdinalIgnoreCase) < 0 ||
            finalXml.IndexOf("</bpmn:definitions>", StringComparison.OrdinalIgnoreCase) < 0)
        {
            throw new Exception("ETAPA 2: A IA não retornou um XML BPMN válido com BPMNDI (layout).");
        }

        // Você pode devolver o RawText concatenando as duas respostas para debug
        return new AiResultDto
        {
            ModelXml = finalXml,
            RawText = "=== STEP1 ===\n" + resp1 + "\n\n=== STEP2 ===\n" + resp2
        };
    }


    private static string PostJson(string url, string apiKey, string jsonBody)
    {
        ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12;

        var req = (HttpWebRequest)WebRequest.Create(url);
        req.Method = "POST";
        req.ContentType = "application/json";
        req.Headers.Add("Authorization", "Bearer " + apiKey);

        var bytes = Encoding.UTF8.GetBytes(jsonBody ?? "{}");
        using (var s = req.GetRequestStream())
        {
            s.Write(bytes, 0, bytes.Length);
        }

        try
        {
            using (var resp = (HttpWebResponse)req.GetResponse())
            using (var sr = new StreamReader(resp.GetResponseStream()))
            {
                return sr.ReadToEnd();
            }
        }
        catch (WebException ex)
        {
            string body = "";
            try
            {
                if (ex.Response != null)
                    using (var sr = new StreamReader(ex.Response.GetResponseStream()))
                        body = sr.ReadToEnd();
            }
            catch { }

            throw new Exception("Falha ao chamar OpenAI: " + ex.Message +
                (string.IsNullOrWhiteSpace(body) ? "" : " | " + body));
        }
    }

    // Escapa string para JSON (sem depender de Newtonsoft)
    private static string EscapeForJson(string s)
    {
        s = s ?? "";
        s = s.Replace("\\", "\\\\")
             .Replace("\"", "\\\"")
             .Replace("\r", "\\r")
             .Replace("\n", "\\n")
             .Replace("\t", "\\t");
        return "\"" + s + "\"";
    }

    // Extrai o texto do output_text (Responses API), desescapa e retorna o XML BPMN
    private static string ExtractDiagramXmlFromResponsesApi(string responseBody)
    {
        if (string.IsNullOrWhiteSpace(responseBody)) return "";

        // Pega: "type":"output_text" ... "text":"{ ... }"
        var m = Regex.Match(
            responseBody,
            "\"type\"\\s*:\\s*\"output_text\"[\\s\\S]*?\"text\"\\s*:\\s*\"(?<t>(?:\\\\.|[^\"\\\\])*)\"",
            RegexOptions.IgnoreCase
        );

        if (m.Success)
        {
            var t = m.Groups["t"].Value;
            t = UnescapeResponseText(t);
            return t.Trim();
        }

        // fallback: último recurso (pode pegar envelope)
        int a = responseBody.IndexOf("<bpmn:definitions", StringComparison.OrdinalIgnoreCase);
        int b = responseBody.LastIndexOf("</bpmn:definitions>", StringComparison.OrdinalIgnoreCase);
        if (a >= 0 && b > a)
            return responseBody.Substring(a, b - a + "</bpmn:definitions>".Length);

        return "";
    }

    private static string UnescapeResponseText(string s)
    {
        if (s == null) return "";
        try
        {
            var serializer = new JavaScriptSerializer();
            return serializer.Deserialize<string>("\"" + s + "\"");
        }
        catch
        {
            s = Regex.Replace(s, @"(?:\\\\u|\\u)([0-9a-fA-F]{4})", m =>
            {
                var code = Convert.ToInt32(m.Groups[1].Value, 16);
                return ((char)code).ToString();
            });

            return s
                .Replace("\\\\", "\\")
                .Replace("\\\"", "\"")
                .Replace("\\n", "\n")
                .Replace("\\r", "\r")
                .Replace("\\t", "\t")
                .Replace("\\/", "/")
                .Replace("\\b", "\b")
                .Replace("\\f", "\f");
        }
    }
}

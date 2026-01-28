using CDIS;
using System;
using System.Collections.Specialized;
using System.Configuration;
using System.Data;
using System.IO;
using System.Net;
using System.Text;
using System.Text.RegularExpressions;
using System.Web;
using System.Web.Services;

public partial class BpmnEditor : System.Web.UI.Page
{
    protected int ModelId = 0;

    protected void Page_Load(object sender, EventArgs e)
    {
        int id;
        ModelId = int.TryParse(Request.QueryString["id"], out id) ? id : 0;
    }

    public class BpmnModelDto
    {
        public int Id { get; set; }
        public string Name { get; set; }
        public string ModelXml { get; set; }
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
            SELECT Id, Name, ModelJson AS ModelXml
              FROM [{0}].[{1}].BpmnModel
             WHERE Id = {2};
        ", db, own, id);

        DataSet ds = cd.getDataSet(sql);

        if (ds == null || ds.Tables.Count == 0 || ds.Tables[0].Rows.Count == 0)
            throw new Exception("Modelo não encontrado.");

        var r = ds.Tables[0].Rows[0];

        return new BpmnModelDto
        {
            Id = Convert.ToInt32(r["Id"]),
            Name = Convert.ToString(r["Name"]),
            ModelXml = Convert.ToString(r["ModelXml"])
        };
    }

    [WebMethod(EnableSession = true)]
    public static void SaveModel(int id, string name, string modelXml)
    {
        if (id <= 0) throw new Exception("Id inválido.");
        name = (name ?? "").Trim();
        if (string.IsNullOrWhiteSpace(name)) throw new Exception("Nome inválido.");
        if (string.IsNullOrWhiteSpace(modelXml)) throw new Exception("XML inválido.");

        OrderedDictionary listaParametrosDados = new OrderedDictionary();
        listaParametrosDados["RemoteIPUsuario"] = HttpContext.Current.Session["RemoteIPUsuario"] + "";
        listaParametrosDados["NomeUsuario"] = HttpContext.Current.Session["NomeUsuario"] + "";
        var cd = CdadosUtil.GetCdados(listaParametrosDados);

        var db = cd.getDbName();
        var own = cd.getDbOwner();

        string sql = string.Format(@"
            UPDATE [{0}].[{1}].BpmnModel
               SET Name = '{2}',
                   ModelJson = '{3}',
                   UpdatedAt = SYSUTCDATETIME()
             WHERE Id = {4};
        ", db, own, EscapeSql(name), EscapeSql(modelXml), id);

        int afetados = 0;
        cd.execSQL(sql, ref afetados);

        if (afetados <= 0)
            throw new Exception("Nenhum registro foi atualizado.");
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

    private static string BuildSystemPromptWithRules()
    {
        // Instruções fixas com regras (como você pediu)
        return
@"Você é um gerador de diagramas BPMN para o modelador BPMN.io.

REGRAS OBRIGATÓRIAS:
- Responda SOMENTE com um XML BPMN 2.0 válido (BPMN.io).
- NÃO use markdown.
- NÃO escreva explicações, comentários ou texto fora do XML.
- NÃO envolva o XML em blocos ``` ou qualquer outro delimitador.
- O XML retornado deve ser completamente auto-suficiente.

REQUISITOS DO XML:
- Deve conter <bpmn:definitions> com namespaces BPMN, BPMNDI e DC.
- Deve conter <bpmn:process> e <bpmndi:BPMNDiagram> com <bpmndi:BPMNPlane>.
- Inclua informações de layout no BPMNDI para manter o posicionamento.
- IDs devem ser únicos e estáveis.

REGRAS DE MODELAGEM:
- Deve existir exatamente UM startEvent.
- Deve existir pelo menos UM endEvent.
- O fluxo deve começar no startEvent e terminar em um endEvent.
- Todo exclusiveGateway deve possuir no mínimo DUAS saídas.
- Nenhum elemento pode ficar desconectado.

COMPORTAMENTO:
- Se o texto do usuário for vago, crie um fluxo simples e coerente.
- Se o texto indicar decisão (ex: ""se"", ""caso"", ""aprovado/reprovado"", ""sim/não""), use exclusiveGateway.
- Se existir um XML atual fornecido, ajuste o diagrama existente ao invés de criar um novo, sempre que possível.
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

    [WebMethod(EnableSession = true)]
    public static AiResultDto GenerateFromAi(string prompt, string currentModelXml)
    {
        prompt = (prompt ?? "").Trim();
        if (string.IsNullOrWhiteSpace(prompt))
            throw new Exception("Prompt vazio.");

        var apiKey = GetOpenAiApiKey();
        if (string.IsNullOrWhiteSpace(apiKey))
            throw new Exception("OpenAI_ApiKey não configurada no WebCDIS.Config/web.config.");

        var system = BuildSystemPromptWithRules();
        var user = BuildUserPrompt(prompt, currentModelXml);

        // Responses API
        var payload = "{"
            + "\"model\":\"gpt-4o-mini\","
            + "\"input\":["
            + "{\"role\":\"system\",\"content\":[{\"type\":\"input_text\",\"text\":" + EscapeForJson(system) + "}]},"
            + "{\"role\":\"user\",\"content\":[{\"type\":\"input_text\",\"text\":" + EscapeForJson(user) + "}]}]"
            + ",\"temperature\":0.2"
            + ",\"max_output_tokens\":1200"
            + "}";

        var resp = PostJson("https://api.openai.com/v1/responses", apiKey, payload);

        // Extrai o XML BPMN (não o envelope do Responses API)
        var extracted = ExtractDiagramXmlFromResponsesApi(resp);

        // validação mínima
        if (string.IsNullOrWhiteSpace(extracted) ||
            extracted.IndexOf("<bpmn:definitions", StringComparison.OrdinalIgnoreCase) < 0 ||
            extracted.IndexOf("</bpmn:definitions>", StringComparison.OrdinalIgnoreCase) < 0)
        {
            throw new Exception("A IA não retornou um XML BPMN válido.");
        }

        return new AiResultDto { ModelXml = extracted, RawText = resp };
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

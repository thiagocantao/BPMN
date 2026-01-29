using CDIS;
using System;
using System.Collections.Generic;
using System.Collections.Specialized;
using System.Data;
using System.Web;
using System.Web.Services;

public partial class BpmnModels : System.Web.UI.Page
{
    public class BpmnModelListItem
    {
        public int Id { get; set; }
        public string Name { get; set; }
        public string UpdatedAt { get; set; } // ISO
    }

    private static string EscapeSql(string s)
    {
        return (s ?? "").Replace("'", "''");
    }

    private static string EscapeXml(string s)
    {
        if (string.IsNullOrEmpty(s)) return "";
        return s.Replace("&", "&amp;")
                .Replace("<", "&lt;")
                .Replace(">", "&gt;")
                .Replace("\"", "&quot;")
                .Replace("'", "&apos;");
    }

    private static string BuildDefaultXml(string name)
    {
        // MVP: start -> task -> end
        // XML BPMN para teste (sem depender de libs)
        var safeName = EscapeXml(name ?? "Processo");
        var startEventNameEncoded = "In&#237;cio";
        var taskNameEncoded = "Nova tarefa";
        var endEventNameEncoded = "Fim";

        return @"<?xml version=""1.0"" encoding=""UTF-8""?>
<bpmn:definitions xmlns:xsi=""http://www.w3.org/2001/XMLSchema-instance""
  xmlns:bpmn=""http://www.omg.org/spec/BPMN/20100524/MODEL""
  xmlns:bpmndi=""http://www.omg.org/spec/BPMN/20100524/DI""
  xmlns:dc=""http://www.omg.org/spec/DD/20100524/DC""
  xmlns:di=""http://www.omg.org/spec/DD/20100524/DI""
  id=""Definitions_1"" targetNamespace=""http://bpmn.io/schema/bpmn"">
  <bpmn:process id=""Process_1"" name=""" + safeName + @""" isExecutable=""false"">
    <bpmn:startEvent id=""StartEvent_1"" name=""" + startEventNameEncoded + @""" />
    <bpmn:task id=""Task_1"" name=""" + taskNameEncoded + @""" />
    <bpmn:endEvent id=""EndEvent_1"" name=""" + endEventNameEncoded + @""" />
    <bpmn:sequenceFlow id=""Flow_1"" sourceRef=""StartEvent_1"" targetRef=""Task_1"" />
    <bpmn:sequenceFlow id=""Flow_2"" sourceRef=""Task_1"" targetRef=""EndEvent_1"" />
  </bpmn:process>
  <bpmndi:BPMNDiagram id=""BPMNDiagram_1"">
    <bpmndi:BPMNPlane id=""BPMNPlane_1"" bpmnElement=""Process_1"">
      <bpmndi:BPMNShape id=""StartEvent_1_di"" bpmnElement=""StartEvent_1"">
        <dc:Bounds x=""120"" y=""120"" width=""36"" height=""36"" />
      </bpmndi:BPMNShape>
      <bpmndi:BPMNShape id=""Task_1_di"" bpmnElement=""Task_1"">
        <dc:Bounds x=""240"" y=""105"" width=""160"" height=""70"" />
      </bpmndi:BPMNShape>
      <bpmndi:BPMNShape id=""EndEvent_1_di"" bpmnElement=""EndEvent_1"">
        <dc:Bounds x=""440"" y=""120"" width=""36"" height=""36"" />
      </bpmndi:BPMNShape>
      <bpmndi:BPMNEdge id=""Flow_1_di"" bpmnElement=""Flow_1"">
        <di:waypoint x=""156"" y=""138"" />
        <di:waypoint x=""240"" y=""138"" />
      </bpmndi:BPMNEdge>
      <bpmndi:BPMNEdge id=""Flow_2_di"" bpmnElement=""Flow_2"">
        <di:waypoint x=""400"" y=""140"" />
        <di:waypoint x=""440"" y=""138"" />
      </bpmndi:BPMNEdge>
    </bpmndi:BPMNPlane>
  </bpmndi:BPMNDiagram>
</bpmn:definitions>";
    }

    [WebMethod(EnableSession = true)]
    public static List<BpmnModelListItem> ListModels()
    {
        OrderedDictionary listaParametrosDados = new OrderedDictionary();

        // Corrigido: acessar Session via HttpContext.Current em métodos estáticos
        listaParametrosDados["RemoteIPUsuario"] = HttpContext.Current.Session["RemoteIPUsuario"] + "";
        listaParametrosDados["NomeUsuario"] = HttpContext.Current.Session["NomeUsuario"] + "";
        var cd = CdadosUtil.GetCdados(listaParametrosDados);

        var db = cd.getDbName();
        var own = cd.getDbOwner();

        string sql = string.Format(@"
                SELECT Id, Name, UpdatedAt
                FROM [{0}].[{1}].BpmnModel
                ORDER BY UpdatedAt DESC, Id DESC", db, own);

        DataSet ds = cd.getDataSet(sql);
        var list = new List<BpmnModelListItem>();

        if (ds != null && ds.Tables.Count > 0)
        {
            foreach (DataRow r in ds.Tables[0].Rows)
            {
                // UpdatedAt em UTC ISO
                var dt = Convert.ToDateTime(r["UpdatedAt"]).ToUniversalTime().ToString("o");

                list.Add(new BpmnModelListItem
                {
                    Id = Convert.ToInt32(r["Id"]),
                    Name = Convert.ToString(r["Name"]),
                    UpdatedAt = dt
                });
            }
        }

        return list;
    }

    [WebMethod(EnableSession = true)]
    public static int CreateModel(string name)
    {
        OrderedDictionary listaParametrosDados = new OrderedDictionary();

        // Corrigido: acessar Session via HttpContext.Current em métodos estáticos
        listaParametrosDados["RemoteIPUsuario"] = HttpContext.Current.Session["RemoteIPUsuario"] + "";
        listaParametrosDados["NomeUsuario"] = HttpContext.Current.Session["NomeUsuario"] + "";
        var cd = CdadosUtil.GetCdados(listaParametrosDados);

        var db = cd.getDbName();
        var own = cd.getDbOwner();

        name = (name ?? "").Trim();
        if (string.IsNullOrWhiteSpace(name))
            throw new Exception("Nome inválido.");

        string xml = BuildDefaultXml(name);

        string sql = string.Format(@"
                SET NOCOUNT ON;
                INSERT INTO [{0}].[{1}].BpmnModel (Name, ModelJson)
                VALUES (N'{2}', N'{3}');

                SELECT CAST(SCOPE_IDENTITY() AS INT) AS NewId;
            ", db, own, EscapeSql(name), EscapeSql(xml));

        DataSet ds = cd.getDataSet(sql);
        if (ds == null || ds.Tables.Count == 0 || ds.Tables[0].Rows.Count == 0)
            throw new Exception("Falha ao criar modelo (sem retorno do ID).");

        return Convert.ToInt32(ds.Tables[0].Rows[0]["NewId"]);
    }

    [WebMethod(EnableSession = true)]
    public static void DeleteModel(int id)
    {
        OrderedDictionary listaParametrosDados = new OrderedDictionary();

        // Corrigido: acessar Session via HttpContext.Current em métodos estáticos
        listaParametrosDados["RemoteIPUsuario"] = HttpContext.Current.Session["RemoteIPUsuario"] + "";
        listaParametrosDados["NomeUsuario"] = HttpContext.Current.Session["NomeUsuario"] + "";
        var cd = CdadosUtil.GetCdados(listaParametrosDados);

        var db = cd.getDbName();
        var own = cd.getDbOwner();

        string sql = string.Format(@"
                DELETE FROM [{0}].[{1}].BpmnModel
                WHERE Id = {2};
            ", db, own, id);

        int afetados = 0;
        cd.execSQL(sql, ref afetados);
    }
}

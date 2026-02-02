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
        public int CodigoFluxo { get; set; }
        public string NomeFluxo { get; set; }
        public bool IndicaAutomacao { get; set; }
    }

    public class BpmnWorkflowVersionItem
    {
        public int CodigoWorkflow { get; set; }
        public string NomeFluxo { get; set; }
        public string VersaoWorkflow { get; set; }
        public string DataCriacao { get; set; }
        public string DataPublicacao { get; set; }
        public string DataRevogacao { get; set; }
        public string IndicaAutomacao { get; set; }
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
            SELECT f.CodigoFluxo,
                   f.NomeFluxo,
                   f.IndicaAutomacao
              FROM Fluxos AS f
             WHERE CodigoEntidade = {2}
               AND DataDesativacao IS NULL", db, own, cd.getInfoSistema("CodigoEntidade").ToString());

        DataSet ds = cd.getDataSet(sql);
        var list = new List<BpmnModelListItem>();

        if (ds != null && ds.Tables.Count > 0)
        {
            foreach (DataRow r in ds.Tables[0].Rows)
            {
                list.Add(new BpmnModelListItem
                {
                    CodigoFluxo = Convert.ToInt32(r["CodigoFluxo"]),
                    NomeFluxo = Convert.ToString(r["NomeFluxo"]),
                    IndicaAutomacao = Convert.ToString(r["IndicaAutomacao"]) == "S"
                });
            }
        }

        return list;
    }

    [WebMethod(EnableSession = true)]
    public static List<BpmnWorkflowVersionItem> ListWorkflowVersions(int codigoFluxo)
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
                   w.VersaoWorkflow,
                   w.DataCriacao,
                   w.DataPublicacao,
                   w.DataRevogacao,
                   f.IndicaAutomacao
              FROM Workflows w INNER JOIN
                   Fluxos f ON f.CodigoFluxo = w.CodigoFluxo
             WHERE w.CodigoFluxo = {2}
             ORDER BY w.DataCriacao DESC
        ", db, own, codigoFluxo);

        DataSet ds = cd.getDataSet(sql);
        var list = new List<BpmnWorkflowVersionItem>();

        if (ds != null && ds.Tables.Count > 0)
        {
            foreach (DataRow r in ds.Tables[0].Rows)
            {
                list.Add(new BpmnWorkflowVersionItem
                {
                    CodigoWorkflow = Convert.ToInt32(r["CodigoWorkflow"]),
                    NomeFluxo = Convert.ToString(r["NomeFluxo"]),
                    VersaoWorkflow = Convert.ToString(r["VersaoWorkflow"]),
                    DataCriacao = FormatDate(r["DataCriacao"]),
                    DataPublicacao = FormatDate(r["DataPublicacao"]),
                    DataRevogacao = FormatDate(r["DataRevogacao"]),
                    IndicaAutomacao = Convert.ToString(r["IndicaAutomacao"])
                });
            }
        }

        return list;
    }

    private static string FormatDate(object value)
    {
        if (value == null || value == DBNull.Value) return "";
        return Convert.ToDateTime(value).ToString("dd/MM/yyyy");
    }
}

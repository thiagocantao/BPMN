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
}

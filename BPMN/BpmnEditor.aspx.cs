using CDIS;
using System;
using System.Collections.Specialized;
using System.Data;
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
            public string ModelJson { get; set; }
        }

        private static string EscapeSql(string s)
        {
            return (s ?? "").Replace("'", "''");
        }

        [WebMethod(EnableSession = true)]
        public static BpmnModelDto GetModel(int id)
        {
            OrderedDictionary listaParametrosDados = new OrderedDictionary();

            // Corrigido: acessar Session via HttpContext.Current em métodos estáticos
            listaParametrosDados["RemoteIPUsuario"] = HttpContext.Current.Session["RemoteIPUsuario"] + "";
            listaParametrosDados["NomeUsuario"] = HttpContext.Current.Session["NomeUsuario"] + "";
            var cd = CdadosUtil.GetCdados(listaParametrosDados);

            var db = cd.getDbName();
            var own = cd.getDbOwner();

            string sql = string.Format(@"
                SELECT Id, Name, ModelJson
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
                ModelJson = Convert.ToString(r["ModelJson"])
            };
        }

        [WebMethod(EnableSession = true)]
        public static void SaveModel(int id, string name, string modelJson)
        {
            if (id <= 0) throw new Exception("Id inválido.");
            name = (name ?? "").Trim();
            if (string.IsNullOrWhiteSpace(name)) throw new Exception("Nome inválido.");
            if (string.IsNullOrWhiteSpace(modelJson)) throw new Exception("JSON inválido.");

            OrderedDictionary listaParametrosDados = new OrderedDictionary();

            // Corrigido: acessar Session via HttpContext.Current em métodos estáticos
            listaParametrosDados["RemoteIPUsuario"] = HttpContext.Current.Session["RemoteIPUsuario"] + "";
            listaParametrosDados["NomeUsuario"] = HttpContext.Current.Session["NomeUsuario"] + "";
            var cd = CdadosUtil.GetCdados(listaParametrosDados);

            var db = cd.getDbName();
            var own = cd.getDbOwner();

            // JSON pode ter aspas, então precisa escapar simples ' para SQL dinâmico
            string sql = string.Format(@"
                UPDATE [{0}].[{1}].BpmnModel
                   SET Name = '{2}',
                       ModelJson = '{3}',
                       UpdatedAt = SYSUTCDATETIME()
                 WHERE Id = {4};
            ", db, own, EscapeSql(name), EscapeSql(modelJson), id);

            int afetados = 0;
            cd.execSQL(sql, ref afetados);

            if (afetados <= 0)
                throw new Exception("Nenhum registro foi atualizado.");
        }
    }


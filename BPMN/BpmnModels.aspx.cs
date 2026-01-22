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

        private static string BuildDefaultJson(string name)
        {
            // MVP: start -> task -> end
            // Json “cru” para teste (sem depender de libs)
            name = EscapeSql(name);

            return @"{
  ""schemaVersion"": 1,
  ""diagram"": { ""id"": ""D1"", ""name"": """ + name.Replace("\"", "\\\"") + @""" },
  ""nodes"": [
    { ""id"": ""N_START_1"", ""type"": ""startEvent"", ""name"": ""Início"", ""x"": 120, ""y"": 120, ""w"": 36, ""h"": 36, ""meta"": {} },
    { ""id"": ""N_TASK_1"",  ""type"": ""task"",       ""name"": ""Nova tarefa"", ""x"": 240, ""y"": 105, ""w"": 160, ""h"": 70, ""meta"": {} },
    { ""id"": ""N_END_1"",   ""type"": ""endEvent"",   ""name"": ""Fim"", ""x"": 440, ""y"": 120, ""w"": 36, ""h"": 36, ""meta"": {} }
  ],
  ""edges"": [
    { ""id"": ""E_1"", ""type"": ""sequenceFlow"", ""from"": ""N_START_1"", ""to"": ""N_TASK_1"", ""waypoints"": [], ""meta"": {} },
    { ""id"": ""E_2"", ""type"": ""sequenceFlow"", ""from"": ""N_TASK_1"", ""to"": ""N_END_1"",  ""waypoints"": [], ""meta"": {} }
  ]
}";
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

            string json = BuildDefaultJson(name);

            string sql = string.Format(@"
                SET NOCOUNT ON;
                INSERT INTO [{0}].[{1}].BpmnModel (Name, ModelJson)
                VALUES ('{2}', '{3}');

                SELECT CAST(SCOPE_IDENTITY() AS INT) AS NewId;
            ", db, own, EscapeSql(name), EscapeSql(json));

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


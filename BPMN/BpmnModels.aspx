<%@ Page Language="C#" AutoEventWireup="true" CodeFile="BpmnModels.aspx.cs" Inherits="BpmnModels" %>
<!DOCTYPE html>
<html>
<head runat="server">
  <meta charset="utf-8" />
  <title>BPMN - Modelos</title>
  <link rel="stylesheet" href="/Bpmn/bpmn-editor.css" />
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.1/css/all.min.css" />
</head>
<body>
  <form id="form1" runat="server">
    <asp:ScriptManager ID="sm" runat="server" EnablePageMethods="true" />

    <div id="app" class="page">
      <header class="topbar">
        <div>
          <h1 class="title">Modelos BPMN</h1>
          <p class="subtitle">Selecione um modelo para editar ou crie um novo</p>
        </div>
        <div class="actions">
          <button type="button" class="btn btn--primary" @click="createNew">+ Novo modelo</button>
          <button type="button" class="btn btn--ghost" @click="refresh">Atualizar</button>
        </div>
      </header>

      <section class="card">
        <div class="table">
          <div class="tr th">
            <div>ID</div>
            <div>Nome</div>
            <div>Atualizado</div>
            <div>Ações</div>
          </div>

          <div v-if="loading" class="tr">
            <div class="muted" style="grid-column: 1 / -1;">Carregando...</div>
          </div>

          <div v-for="m in models" :key="m.Id" class="tr">
            <div><strong>{{ m.Id }}</strong></div>
            <div>{{ m.Name }}</div>
            <div class="muted">{{ formatDate(m.UpdatedAt) }}</div>
            <div class="row-actions">
              <button type="button" class="icon-button" @click="edit(m.Id)" aria-label="Editar">
                <i class="fa-solid fa-link"></i>
              </button>
              <button type="button" class="icon-button icon-button--danger" @click="remove(m.Id)" aria-label="Excluir">
                <i class="fa-regular fa-trash-can"></i>
              </button>
            </div>
          </div>

          <div v-if="!loading && models.length === 0" class="tr">
            <div class="muted" style="grid-column: 1 / -1;">Nenhum modelo encontrado.</div>
          </div>
        </div>
      </section>
    </div>

    <script src="https://unpkg.com/vue@3/dist/vue.global.prod.js"></script>
    <script>
        const { createApp, ref } = Vue;

        createApp({
            setup() {
                const loading = ref(false);
                const models = ref([]);

                const refresh = () => {
                    loading.value = true;
                    PageMethods.ListModels(
                        (result) => { models.value = result || []; loading.value = false; },
                        (err) => { console.error(err); alert("Erro ao listar modelos."); loading.value = false; }
                    );
                };

                const createNew = () => {
                    const name = prompt("Nome do novo modelo:", "Novo processo");
                    if (!name) return;

                    PageMethods.CreateModel(
                        name,
                        (newId) => { window.location.href = "/Bpmn/BpmnEditor.aspx?id=" + newId; },
                        (err) => { console.error(err); alert("Erro ao criar modelo."); }
                    );
                };

                const edit = (id) => window.location.href = "/Bpmn/BpmnEditor.aspx?id=" + id;

                const remove = (id) => {
                    if (!confirm("Excluir este modelo?")) return;
                    PageMethods.DeleteModel(
                        id,
                        () => refresh(),
                        (err) => { console.error(err); alert("Erro ao excluir."); }
                    );
                };

                const formatDate = (iso) => {
                    try { return new Date(iso).toLocaleString("pt-BR"); }
                    catch { return iso; }
                };

                refresh();

                return { loading, models, refresh, createNew, edit, remove, formatDate };
            }
        }).mount("#app");
    </script>
  </form>
</body>
</html>

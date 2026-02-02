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
          <p class="subtitle">Selecione um fluxo para editar ou visualizar</p>
        </div>
        <div class="actions">
          <button type="button" class="btn btn--primary" @click="createNew">+ Novo fluxo</button>
          <button type="button" class="btn btn--ghost" @click="refresh">Atualizar</button>
        </div>
      </header>

      <section class="card">
        <div class="table models-table">
          <div class="tr th">
            <div class="cell-name">Nome</div>
            <div class="cell-automation">Automação</div>
            <div>Ações</div>
          </div>

          <div class="table-body">
            <div v-if="loading" class="tr">
              <div class="muted" style="grid-column: 1 / -1;">Carregando...</div>
            </div>

            <div v-for="m in models" :key="m.CodigoFluxo" class="tr">
              <div class="cell-name">{{ m.NomeFluxo }}</div>
              <div class="cell-automation">
                <input type="checkbox" class="checkbox" :checked="m.IndicaAutomacao" disabled />
              </div>
              <div class="row-actions">
                <button type="button" class="icon-button" @click="view(m.CodigoFluxo)" aria-label="Visualizar">
                  <i class="fa-regular fa-eye"></i>
                </button>
                <button type="button" class="icon-button" @click="edit(m.CodigoFluxo)" aria-label="Editar">
                  <i class="fa-solid fa-pencil"></i>
                </button>
              </div>
            </div>

            <div v-if="!loading && models.length === 0" class="tr">
              <div class="muted" style="grid-column: 1 / -1;">Nenhum modelo encontrado.</div>
            </div>
          </div>
        </div>
      </section>
    </div>

    <script src="https://unpkg.com/vue@3/dist/vue.global.prod.js"></script>
    <script>
        const createToastManager = () => {
            let toastEl = null;
            let messageEl = null;
            let closeButton = null;
            let overlayEl = null;
            let hideTimer = null;
            let currentType = "success";

            const hideToast = () => {
                if (hideTimer) {
                    clearTimeout(hideTimer);
                    hideTimer = null;
                }
                if (toastEl) toastEl.classList.remove("is-active");
                if (overlayEl) overlayEl.classList.remove("is-active");
            };

            const ensureElements = () => {
                if (toastEl) return;

                overlayEl = document.createElement("div");
                overlayEl.className = "toast-overlay";

                toastEl = document.createElement("div");
                toastEl.className = "toast-container";

                messageEl = document.createElement("span");
                messageEl.className = "toast-message";

                closeButton = document.createElement("button");
                closeButton.type = "button";
                closeButton.className = "toast-close";
                closeButton.setAttribute("aria-label", "Fechar");
                closeButton.innerHTML = "&times;";
                closeButton.addEventListener("click", (event) => {
                    event.stopPropagation();
                    hideToast();
                });

                toastEl.addEventListener("click", () => {
                    if (currentType !== "error") {
                        hideToast();
                    }
                });

                toastEl.appendChild(messageEl);
                toastEl.appendChild(closeButton);
                document.body.appendChild(overlayEl);
                document.body.appendChild(toastEl);
            };

            const showToast = (message, type = "success") => {
                ensureElements();
                currentType = type;
                messageEl.textContent = message;
                toastEl.classList.remove("toast--success", "toast--error");
                toastEl.classList.add(`toast--${type}`);
                toastEl.classList.add("is-active");
                overlayEl.classList.add("is-active");

                if (hideTimer) {
                    clearTimeout(hideTimer);
                }

                if (type !== "error") {
                    hideTimer = setTimeout(hideToast, 2000);
                } else {
                    hideTimer = null;
                }
            };

            return { showToast, hideToast };
        };

        const toast = createToastManager();

        const { createApp, ref } = Vue;

        createApp({
            setup() {
                const loading = ref(false);
                const models = ref([]);

                const refresh = () => {
                    loading.value = true;
                    PageMethods.ListModels(
                        (result) => { models.value = result || []; loading.value = false; },
                        (err) => { console.error(err); toast.showToast("Erro ao listar modelos.", "error"); loading.value = false; }
                    );
                };

                const createNew = () => {
                    window.location.href = "/Bpmn/BpmnEditor.aspx?id=-1&mode=edit";
                };

                const view = (id) => window.location.href = "/Bpmn/BpmnEditor.aspx?id=" + id + "&mode=view";
                const edit = (id) => window.location.href = "/Bpmn/BpmnEditor.aspx?id=" + id + "&mode=edit";

                refresh();

                return { loading, models, refresh, createNew, view, edit };
            }
        }).mount("#app");
    </script>
  </form>
</body>
</html>

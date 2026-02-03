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
          <h1 class="title">Fluxos</h1>
          <p class="subtitle">Selecione um fluxo para editar ou visualizar</p>
        </div>
        <div class="actions">
          <div class="search-field">
            <i class="fa-solid fa-magnifying-glass search-icon" aria-hidden="true"></i>
            <input type="text" class="search-input" placeholder="Pesquisar fluxo..." v-model="searchTerm" />
          </div>
        </div>
      </header>

      <section class="models-layout" :class="{ 'models-layout--with-sheet': versionsSheet.open }">
        <div class="card">
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

              <div v-for="m in filteredModels" :key="m.CodigoFluxo" class="tr">
                <div class="cell-name">{{ m.NomeFluxo }}</div>
                <div class="cell-automation">
                  <input type="checkbox" class="checkbox" :checked="m.IndicaAutomacao" disabled />
                </div>
                <div class="row-actions row-actions--wide">
                  <button type="button" class="row-action-button" @click="openVersionsSheet(m)" aria-label="Ver versões">
                    <i class="fa-solid fa-list" aria-hidden="true"></i>
                  </button>
                  <button type="button" class="row-action-button" @click="createVersion(m.CodigoFluxo)" aria-label="Nova versão">
                    <i class="fa-solid fa-plus" aria-hidden="true"></i>
                  </button>
                </div>
              </div>

              <div v-if="!loading && filteredModels.length === 0" class="tr">
                <div class="muted" style="grid-column: 1 / -1;">Nenhum modelo encontrado.</div>
              </div>
            </div>
          </div>
        </div>

        <aside v-if="versionsSheet.open" class="info-sheet card versions-sheet">
          <div class="versions-sheet-header">
            <button type="button" class="sheet-close-button" @click="closeVersionsSheet" aria-label="Fechar">
              <i class="fa-solid fa-xmark" aria-hidden="true"></i>
            </button>
            <div>
              <h3>{{ versionsSheet.title }}</h3>
              <p class="sheet-subtitle">Gerencie versões e edite metadados.</p>
            </div>
          </div>
          <div class="versions-sheet-divider"></div>

          <div class="versions-sheet-toolbar">
            <div class="info-sheet-name">
              Automação: {{ versionsSheet.automationLabel }}
            </div>
            <button type="button" class="btn btn--primary" @click="createVersion(versionsSheet.flowId)" :disabled="!versionsSheet.flowId">
              Nova versão
              <i class="fa fa-plus btn__icon" aria-hidden="true"></i>
            </button>
          </div>

          <div class="table versions-table">
            <div class="tr th">
              <div>Versão</div>
              <div>Criação</div>
              <div>Publicação</div>
              <div>Revogação</div>
              <div>Ações</div>
            </div>

            <div class="table-body">
              <div v-if="versionsSheet.loading" class="tr">
                <div class="muted" style="grid-column: 1 / -1;">Carregando...</div>
              </div>

              <div v-for="item in versionsSheet.items" :key="item.CodigoWorkflow" class="tr">
                <div>{{ item.VersaoWorkflow }}</div>
                <div>{{ item.DataCriacao }}</div>
                <div>{{ item.DataPublicacao }}</div>
                <div>{{ item.DataRevogacao }}</div>
                <div class="row-actions">
                  <button v-if="canEditWorkflow(item)" type="button" class="icon-button" @click="editWorkflow(item.CodigoWorkflow)" aria-label="Editar">
                    <i class="fa-solid fa-pencil"></i>
                  </button>
                  <button v-else type="button" class="icon-button" @click="viewWorkflow(item.CodigoWorkflow)" aria-label="Somente consulta">
                    <i class="fa-solid fa-eye"></i>
                  </button>
                </div>
              </div>

              <div v-if="!versionsSheet.loading && versionsSheet.items.length === 0" class="tr">
                <div class="muted" style="grid-column: 1 / -1;">Nenhuma versão encontrada.</div>
              </div>
            </div>
          </div>

          <div class="info-sheet-actions info-sheet-actions--bottom">
            <button type="button" class="btn btn--ghost" @click="closeVersionsSheet">
              Fechar
              <i class="fa fa-close btn__icon" aria-hidden="true"></i>
            </button>
          </div>
        </aside>
      </section>

      <button type="button" class="fab-button" @click="createNewFlow" aria-label="Criar novo fluxo">
        <i class="fa-solid fa-plus" aria-hidden="true"></i>
      </button>
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

        const { createApp, ref, computed } = Vue;

        const setScrollbarWidth = () => {
            const scrollbarWidth = window.innerWidth - document.documentElement.clientWidth;
            document.documentElement.style.setProperty("--scrollbar-width", `${scrollbarWidth}px`);
        };

        setScrollbarWidth();
        window.addEventListener("resize", setScrollbarWidth);

        createApp({
            setup() {
                const loading = ref(false);
                const models = ref([]);
                const searchTerm = ref("");

                const refresh = () => {
                    loading.value = true;
                    PageMethods.ListModels(
                        (result) => { models.value = result || []; loading.value = false; },
                        (err) => { console.error(err); toast.showToast("Erro ao listar modelos.", "error"); loading.value = false; }
                    );
                };

                const view = (id) => window.location.href = "/Bpmn/BpmnEditor.aspx?id=" + id + "&mode=view";
                const edit = (id) => window.location.href = "/Bpmn/BpmnEditor.aspx?id=" + id + "&mode=edit";

                const versionsSheet = ref({
                    open: false,
                    loading: false,
                    flowId: null,
                    title: "",
                    automationLabel: "Não",
                    items: []
                });

                const openVersionsSheet = (model) => {
                    versionsSheet.value.open = true;
                    versionsSheet.value.loading = true;
                    versionsSheet.value.flowId = model.CodigoFluxo;
                    versionsSheet.value.title = `Versões • ${model.NomeFluxo || ""}`;
                    versionsSheet.value.automationLabel = model.IndicaAutomacao ? "Sim" : "Não";
                    versionsSheet.value.items = [];

                    PageMethods.ListWorkflowVersions(
                        model.CodigoFluxo,
                        (result) => {
                            const items = result || [];
                            versionsSheet.value.items = items;
                            if (items.length > 0 && items[0].NomeFluxo) {
                                versionsSheet.value.title = `Versões • ${items[0].NomeFluxo}`;
                            }
                            if (items.length > 0 && items[0].IndicaAutomacao) {
                                versionsSheet.value.automationLabel = items[0].IndicaAutomacao === "S" ? "Sim" : "Não";
                            }
                            versionsSheet.value.loading = false;
                        },
                        (err) => {
                            console.error(err);
                            toast.showToast("Erro ao carregar versões.", "error");
                            versionsSheet.value.loading = false;
                        }
                    );
                };

                const closeVersionsSheet = () => {
                    versionsSheet.value.open = false;
                };

                const createVersion = (id) => {
                    if (!id) return;
                    edit(id);
                };

                const editWorkflow = (codigoWorkflow) => {
                    window.location.href = "/Bpmn/BpmnEditor.aspx?id=" + codigoWorkflow + "&mode=edit";
                };

                const viewWorkflow = (codigoWorkflow) => {
                    window.location.href = "/Bpmn/BpmnEditor.aspx?id=" + codigoWorkflow + "&mode=view";
                };

                const createNewFlow = () => {
                    window.location.href = "/Bpmn/BpmnEditor.aspx";
                };

                const hasValue = (value) => value !== null && value !== undefined && String(value).trim() !== "";

                const isAutomationFlow = (item) => {
                    if (item && typeof item.IndicaAutomacao !== "undefined") {
                        return item.IndicaAutomacao === "S" || item.IndicaAutomacao === true;
                    }
                    return versionsSheet.value.automationLabel === "Sim";
                };

                const canEditWorkflow = (item) => {
                    if (!isAutomationFlow(item)) {
                        return true;
                    }
                    return hasValue(item.DataPublicacao) && !hasValue(item.DataRevogacao);
                };

                const filteredModels = computed(() => {
                    const term = searchTerm.value.trim().toLowerCase();
                    if (!term) return models.value;
                    return models.value.filter((model) =>
                        (model.NomeFluxo || "").toLowerCase().includes(term)
                    );
                });

                refresh();

                return {
                    loading,
                    models,
                    searchTerm,
                    filteredModels,
                    refresh,
                    view,
                    edit,
                    versionsSheet,
                    openVersionsSheet,
                    closeVersionsSheet,
                    createVersion,
                    editWorkflow,
                    viewWorkflow,
                    canEditWorkflow,
                    createNewFlow
                };
            }
        }).mount("#app");
    </script>
  </form>
</body>
</html>

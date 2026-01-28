<%@ Page Language="C#" AutoEventWireup="true"  CodeFile="BpmnEditor.aspx.cs" Inherits="BpmnEditor" %>
<!DOCTYPE html>
<html>
<head runat="server">
  <meta charset="utf-8" />
  <title>BPMN - Editor</title>
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.1/css/all.min.css" />
  <link rel="stylesheet" href="https://unpkg.com/bpmn-js@17.0.2/dist/assets/diagram-js.css" />
  <link rel="stylesheet" href="https://unpkg.com/bpmn-js@17.0.2/dist/assets/bpmn-js.css" />
  <link rel="stylesheet" href="https://unpkg.com/bpmn-js@17.0.2/dist/assets/bpmn-font/css/bpmn.css" />
  <link rel="stylesheet" href="/Bpmn/bpmn-editor.css" />
</head>
<body>
<form id="form1" runat="server">
  <asp:ScriptManager ID="sm" runat="server" EnablePageMethods="true" />

  <script>
      // Id vem do QueryString
      window.__BPMN_MODEL_ID__ = <%= ModelId %>;
  </script>

  <div id="bpmnApp" class="page">
    <header class="topbar">
      <div class="left">
        <a class="link" href="/Bpmn/BpmnModels.aspx">← Voltar</a>
        <div class="titlewrap">
          <h1 class="title">Editor BPMN</h1>
          <p class="subtitle">Arraste, conecte e salve</p>
        </div>
      </div>

      <div class="actions">
        <button type="button" class="btn btn--ghost" @click="setMode('select')" :class="{ active: mode==='select' }">Selecionar</button>
        <button type="button" class="btn btn--ghost" @click="setMode('connect')" :class="{ active: mode==='connect' }">Conectar</button>

        <span class="divider"></span>

        <button type="button" class="btn btn--ghost" @click="save" :disabled="saving">{{ saving ? 'Salvando...' : 'Salvar' }}</button>
      </div>
    </header>

    <section class="layout">
      <aside class="sidebar card">
        <div class="sidebar-toggle" role="group" aria-label="Modo do painel">
          <button type="button" :class="{ active: sidebarMode === 'edit' }" @click="sidebarMode = 'edit'">Editar</button>
          <button type="button" :class="{ active: sidebarMode === 'ai' }" @click="sidebarMode = 'ai'">IA</button>
        </div>

        <div v-if="sidebarMode === 'edit'" class="sidebar-edit">
          <h3>Paleta</h3>
          <div class="palette">
            <button type="button" class="pill palette-item" @click="beginAdd('startEvent')">
              <span class="palette-shape palette-shape--start"></span>
              Início
            </button>
            <button type="button" class="pill palette-item" @click="beginAdd('task')">
              <span class="palette-shape palette-shape--task"></span>
              Tarefa
            </button>
            <button type="button" class="pill palette-item" @click="beginAdd('exclusiveGateway')">
              <span class="palette-shape palette-shape--gateway"></span>
              Decisão
            </button>
            <button type="button" class="pill palette-item" @click="beginAdd('endEvent')">
              <span class="palette-shape palette-shape--end"></span>
              Fim
            </button>
          </div>

          <h3 style="margin-top:16px;">Modelo</h3>
          <label class="field">
            <span>Nome</span>
            <input class="input" v-model="modelName" />
          </label>

          <div class="toolbar">
            <button type="button" class="btn btn--danger" @click="deleteSelected" :disabled="selectedIds.length === 0">Excluir selecionado</button>
            <button type="button" class="btn btn--ghost" @click="openInfoEditorFromSelection" :disabled="!canEditSelectedInfo">Editar informações</button>
            <button type="button" class="btn btn--ghost" @click="openInfoViewerFromSelection" :disabled="!canEditSelectedInfo">Visualizar informações</button>
          </div>

          <div class="hint">
            <div><strong>Adicionar:</strong> use a paleta acima ou a paleta BPMN do canvas.</div>
            <div><strong>Conectar:</strong> use o botão de conexão do BPMN.io ou a opção Conectar.</div>
            <div><strong>Editar:</strong> dê duplo clique no nome do elemento.</div>
          </div>
        </div>

        <div v-else class="sidebar-ai">
          <div class="sidebar-ai-spacer"></div>
          <div class="sidebar-ai-input">
            <textarea
              ref="aiPromptRef"
              class="input"
              v-model="aiPrompt"
              placeholder="Descreva o que deseja automatizar"
              rows="1"
              @input="resizeAiPrompt"
            ></textarea>
            <button type="button" class="icon-button" @click="sendAiPrompt" :disabled="aiGenerating" aria-label="Enviar prompt de IA">
              <i class="fa-solid fa-paper-plane"></i>
            </button>
          </div>
        </div>
      </aside>

      <main class="canvas card">
        <div ref="bpmnCanvasRef" class="bpmn-canvas"></div>
      </main>
    </section>

    <div v-if="infoEditor.show" class="modal">
      <div class="modal-backdrop" @click="closeInfoEditor"></div>
      <div class="modal-card">
        <header class="modal-header">
          <h3>Editar informações</h3>
          <div class="modal-actions">
            <button type="button" class="btn btn--ghost" @click="closeInfoEditor">Cancelar</button>
            <button type="button" class="btn btn--primary" @click="saveInfoEditor">Salvar</button>
          </div>
        </header>
        <div class="modal-body">
          <div class="rich-toolbar" @mousedown.prevent>
            <button type="button" class="toolbar-btn" title="Negrito" @click="formatInfoEditor('bold')">
              <i class="fa-solid fa-bold"></i>
            </button>
            <button type="button" class="toolbar-btn" title="Itálico" @click="formatInfoEditor('italic')">
              <i class="fa-solid fa-italic"></i>
            </button>
            <button type="button" class="toolbar-btn" title="Sublinhado" @click="formatInfoEditor('underline')">
              <i class="fa-solid fa-underline"></i>
            </button>
            <span class="toolbar-divider"></span>
            <button type="button" class="toolbar-btn" title="Lista" @click="formatInfoEditor('insertUnorderedList')">
              <i class="fa-solid fa-list-ul"></i>
            </button>
            <button type="button" class="toolbar-btn" title="Lista numerada" @click="formatInfoEditor('insertOrderedList')">
              <i class="fa-solid fa-list-ol"></i>
            </button>
            <span class="toolbar-divider"></span>
            <button type="button" class="toolbar-btn" title="Link" @click="formatInfoEditor('createLink')">
              <i class="fa-solid fa-link"></i>
            </button>
            <button type="button" class="toolbar-btn" title="Limpar formatação" @click="formatInfoEditor('removeFormat')">
              <i class="fa-solid fa-eraser"></i>
            </button>
          </div>
          <div class="rich-editor" contenteditable="true" ref="infoEditorRef" @input="onEditorInput"></div>
        </div>
      </div>
    </div>

    <div v-if="infoViewer.show" class="modal">
      <div class="modal-backdrop" @click="closeInfoViewer"></div>
      <div class="modal-card">
        <header class="modal-header">
          <h3>Visualizar informações</h3>
          <div class="modal-actions">
            <button type="button" class="btn btn--ghost" @click="closeInfoViewer">Fechar</button>
          </div>
        </header>
        <div class="modal-body">
          <div v-if="infoViewer.content" class="rich-viewer" v-html="infoViewer.content"></div>
          <p v-else class="empty-info">Nenhuma informação cadastrada.</p>
        </div>
      </div>
    </div>

    <div v-if="aiGenerating" class="ai-modal" role="dialog" aria-live="polite" aria-label="Processando instrução da IA">
      <div class="ai-modal-card">
        <div class="ai-modal-title">{{ aiStepMessage }}</div>
      </div>
    </div>
  </div>

  <script src="https://unpkg.com/bpmn-js@17.0.2/dist/bpmn-modeler.production.min.js"></script>
  <script src="./vue.global.prod.js"></script>
  <script src="/Bpmn/bpmn-editor.js"></script>
</form>
</body>
</html>

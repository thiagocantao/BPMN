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
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Roboto:wght@300;400;500;700&family=Source+Sans+Pro:wght@400;600;700&display=swap" rel="stylesheet">

  <link rel="stylesheet" href="/Bpmn/bpmn-editor.css" />
</head>
<body>
<form id="form1" runat="server">
  <asp:ScriptManager ID="sm" runat="server" EnablePageMethods="true" />

  <script>
      // Id vem do QueryString
      window.__BPMN_MODEL_ID__ = <%= ModelId %>;
      window.__BPMN_AI_ENABLED__ = <%= HasOpenAiKey.ToString().ToLowerInvariant() %>;
  </script>

  <div id="bpmnApp" class="page">
    <header class="topbar">
      <div class="left">
        <div class="titlewrap">
          <h1 class="title">Editor BPMN</h1>
          <p class="subtitle">{{ subtitleText }}</p>
        </div>
      </div>

      <div class="actions">
        <button type="button" class="btn btn--ghost" @click="handleBack">
          Voltar
          <i class="fa fa-arrow-left btn__icon" aria-hidden="true"></i>
        </button>
        <button type="button" class="btn btn--primary" @click="exportAsImage">
          Exportar como imagem
          <i class="fa fa-file-export btn__icon" aria-hidden="true"></i>
        </button>
        <button type="button" class="btn btn--primary" @click="save" :disabled="saving || isReadOnly" v-if="!isReadOnly">
          {{ saving ? 'Salvando...' : 'Salvar' }}
          <i class="fa fa-check btn__icon" aria-hidden="true"></i>
        </button>
      </div>
    </header>

    <section class="layout" :class="{ 'layout--with-sheet': infoEditor.show || infoViewer.show }">
      <aside class="sidebar card">
        <div v-if="aiEnabled" class="sidebar-toggle" role="group" aria-label="Modo do painel">
          <button type="button" :class="{ active: sidebarMode === 'edit' }" @click="sidebarMode = 'edit'">
            Editar
            <i class="fa fa-pen btn__icon" aria-hidden="true"></i>
          </button>
          <button type="button" :class="{ active: sidebarMode === 'ai' }" @click="sidebarMode = 'ai'">
            IA
            <i class="fa fa-robot btn__icon" aria-hidden="true"></i>
          </button>
        </div>

        <div v-if="sidebarMode === 'edit' || !aiEnabled" class="sidebar-edit">
          <h3>Processo</h3>
          <label class="field">
            <span>Nome</span>
            <input class="input" v-model="modelName" :disabled="isReadOnly" />
          </label>

          <div class="field">
            <span>Descrição</span>
            <div class="rich-toolbar rich-toolbar--compact" v-if="!isReadOnly" @mousedown.prevent>
              <button type="button" class="toolbar-btn" title="Negrito" @click="formatProcessDescription('bold')">
                <i class="fa-solid fa-bold"></i>
              </button>
              <button type="button" class="toolbar-btn" title="Itálico" @click="formatProcessDescription('italic')">
                <i class="fa-solid fa-italic"></i>
              </button>
              <button type="button" class="toolbar-btn" title="Sublinhado" @click="formatProcessDescription('underline')">
                <i class="fa-solid fa-underline"></i>
              </button>
              <span class="toolbar-divider"></span>
              <button type="button" class="toolbar-btn" title="Lista" @click="formatProcessDescription('insertUnorderedList')">
                <i class="fa-solid fa-list-ul"></i>
              </button>
              <button type="button" class="toolbar-btn" title="Lista numerada" @click="formatProcessDescription('insertOrderedList')">
                <i class="fa-solid fa-list-ol"></i>
              </button>
              <span class="toolbar-divider"></span>
              <button type="button" class="toolbar-btn" title="Link" @click="formatProcessDescription('createLink')">
                <i class="fa-solid fa-link"></i>
              </button>
              <button type="button" class="toolbar-btn" title="Limpar formatação" @click="formatProcessDescription('removeFormat')">
                <i class="fa-solid fa-eraser"></i>
              </button>
              <input
                type="color"
                class="toolbar-color"
                title="Cor do texto"
                @input="formatProcessDescription('foreColor', $event.target.value)"
              />
            </div>
            <div
              class="rich-editor rich-editor--compact"
              :contenteditable="!isReadOnly"
              ref="processDescriptionRef"
              @input="onProcessDescriptionInput"
            ></div>
          </div>

          <div class="toolbar">
            <button type="button" class="btn btn--primary is-hidden" @click="exportAsPdf">
              Exportar para PDF
              <i class="fa fa-file-pdf btn__icon" aria-hidden="true"></i>
            </button>
          </div>

          <div class="hint is-hidden">
            <div><strong>Adicionar:</strong> use a paleta padrão do BPMN.io no canvas.</div>
            <div><strong>Conectar:</strong> use o botão de conexão do BPMN.io ou a opção Conectar.</div>
            <div><strong>Editar:</strong> dê duplo clique no nome do elemento.</div>
          </div>
        </div>

        <div v-else-if="aiEnabled" class="sidebar-ai">
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
        <div class="canvas-controls" role="group" aria-label="Controles de zoom">
          <button type="button" class="icon-button" title="Aumentar zoom" aria-label="Zoom in" @click="zoomIn">
            <i class="fa-solid fa-magnifying-glass-plus" aria-hidden="true"></i>
          </button>
          <button type="button" class="icon-button" title="Diminuir zoom" aria-label="Zoom out" @click="zoomOut">
            <i class="fa-solid fa-magnifying-glass-minus" aria-hidden="true"></i>
          </button>
          <button type="button" class="icon-button" title="Centralizar" aria-label="Re-centralizar" @click="recenterCanvas">
            <i class="fa-solid fa-bullseye" aria-hidden="true"></i>
          </button>
        </div>
      </main>

      <aside v-if="infoEditor.show || infoViewer.show" class="info-sheet card">
        <div class="info-sheet-header">
          <div>
            <h3>{{ infoEditor.show ? 'Editar informações' : 'Visualizar informações' }}</h3>
            <label v-if="infoPanelName" class="field">
              <span>Nome</span>
              <div class="info-sheet-name">{{ infoPanelName }}</div>
            </label>
          </div>
        </div>

        <div v-if="infoEditor.show">
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
            <input
              type="color"
              class="toolbar-color"
              title="Cor do texto"
              @input="formatInfoEditor('foreColor', $event.target.value)"
            />
          </div>
          <div class="rich-editor" contenteditable="true" ref="infoEditorRef" @input="onEditorInput"></div>
          <div class="info-sheet-actions info-sheet-actions--bottom">
            <button type="button" class="btn btn--ghost" @click="requestCloseInfoEditor">
              Cancelar
              <i class="fa fa-close btn__icon" aria-hidden="true"></i>
            </button>
            <button type="button" class="btn btn--primary" @click="saveInfoEditor">
              Confirmar
              <i class="fa fa-check btn__icon" aria-hidden="true"></i>
            </button>
          </div>
        </div>

        <div v-else>
          <div v-if="infoViewer.content" class="rich-viewer rich-viewer--boxed" v-html="infoViewer.content"></div>
          <p v-else class="empty-info">Nenhuma informação cadastrada.</p>
          <div class="info-sheet-actions info-sheet-actions--bottom">
            <button type="button" class="btn btn--ghost" @click="closeInfoViewer">
              Fechar
              <i class="fa fa-close btn__icon" aria-hidden="true"></i>
            </button>
          </div>
        </div>
      </aside>
    </section>

    <!-- Debug i18n: aparece somente com ?debugTranslate=1 -->
    <div id="bpmnI18nStatus" style="display:none; position: fixed; right: 12px; bottom: 12px; z-index: 9999; background: #fff; border: 1px solid #ddd; padding: 8px 10px; border-radius: 8px; font: 12px/1.3 Arial; box-shadow: 0 2px 10px rgba(0,0,0,.08)">
      i18n...
    </div>

    <div v-if="aiGenerating" class="ai-modal" role="dialog" aria-live="polite" aria-label="Processando instrução da IA">
      <div class="ai-modal-card">
        <div class="ai-modal-title">{{ aiStepMessage }}</div>
      </div>
    </div>
  </div>

  <script src="https://unpkg.com/bpmn-js@17.0.2/dist/bpmn-modeler.production.min.js"></script>
  <script src="./vue.global.prod.js"></script>
  <!-- Cache-buster para garantir que o browser carregue a última versão do JS -->
  <script src="/Bpmn/bpmn-editor.js?v=<%= DateTime.UtcNow.Ticks %>"></script>
</form>
</body>
</html>

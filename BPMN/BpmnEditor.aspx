<%@ Page Language="C#" AutoEventWireup="true"  CodeFile="BpmnEditor.aspx.cs" Inherits="BpmnEditor" %>
<!DOCTYPE html>
<html>
<head runat="server">
  <meta charset="utf-8" />
  <title>BPMN - Editor</title>
  <link rel="stylesheet" href="/Bpmn/bpmn-editor.css" />
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.1/css/all.min.css" />
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
            <button type="button" class="btn btn--danger" @click="deleteSelected" :disabled="!selectedId">Excluir selecionado</button>
          </div>

          <div class="hint">
            <div><strong>Modo adicionar:</strong> clique no canvas para inserir.</div>
            <div><strong>Conectar:</strong> clique no nó origem e depois no destino.</div>
            <div><strong>Mover:</strong> arraste o nó.</div>
          </div>
        </div>

        <div v-else class="sidebar-ai">
          <div class="sidebar-ai-spacer"></div>
          <div class="sidebar-ai-input">
            <input class="input" v-model="aiPrompt" placeholder="Descreva o que deseja automatizar" />
            <button type="button" class="icon-button" @click="sendAiPrompt" aria-label="Enviar prompt de IA">
              <i class="fa-solid fa-paper-plane"></i>
            </button>
          </div>
        </div>
      </aside>

      <main class="canvas card">
        <svg
          ref="svgRef"
          class="svg"
          :viewBox="viewBox"
          @mousedown="onCanvasMouseDown"
        >
          <defs>
            <marker id="arrow" markerWidth="10" markerHeight="10" refX="9" refY="3" orient="auto" markerUnits="strokeWidth">
              <path d="M0,0 L10,3 L0,6 Z"></path>
            </marker>
          </defs>

          <!-- edges -->
          <g class="edges">
            <g v-for="e in edges" :key="e.id" class="edge-group">
              <polyline
                :points="edgePoints(e)"
                class="edge"
                :class="{ selected: selectedId===e.id }"
                marker-end="url(#arrow)"
                @mousedown.stop="selectEdge(e.id)"
              />
              <g
                v-if="selectedId===e.id && edgeMidpoint(e).valid"
                class="edge-delete"
                :transform="`translate(${edgeMidpoint(e).x},${edgeMidpoint(e).y})`"
                @mousedown.stop
                @click.stop="deleteSelected"
              >
                <title>Excluir conector</title>
                <rect class="edge-delete-bg" x="-12" y="-12" width="34" height="30" rx="8" ry="8" />
                <foreignObject class="edge-delete-icon" x="-3" y="-9" width="24" height="24">
                  <div class="menu-icon" xmlns="http://www.w3.org/1999/xhtml">
                    <i class="fa-regular fa-trash-can"></i>
                  </div>
                </foreignObject>
              </g>
            </g>
          </g>

          <!-- nodes -->
          <g class="nodes">
            <template v-for="n in nodes" :key="n.id">
              <!-- task -->
              <g v-if="n.type==='task'" class="node" :class="{ selected: selectedId===n.id }"
                 :transform="`translate(${n.x},${n.y})`"
                 @mousedown.stop="onNodeDown($event, n)"
                 @mouseup.stop="onNodeConnectDrop(n)"
                 @click.stop="onNodeClick(n)">
                <rect :width="n.w" :height="n.h" rx="10" ry="10" />
                <text v-if="!isEditingName(n)" class="node-title" x="10" y="24" @mousedown.stop @click.stop="beginNameEdit(n)">{{ n.name }}</text>
                <foreignObject v-else x="6" y="6" :width="n.w - 12" height="24" @mousedown.stop @click.stop>
                  <div class="node-name-input-wrap" xmlns="http://www.w3.org/1999/xhtml">
                    <input
                      ref="nameInputRef"
                      v-model="nameEditor.value"
                      class="node-name-input"
                      @keydown.enter.prevent="saveNameEdit"
                      @keydown.esc.prevent="cancelNameEdit"
                      @blur="saveNameEdit"
                    />
                  </div>
                </foreignObject>
                <circle class="connector" :cx="n.w + connectorOffset" :cy="n.h / 2" r="6"
                        @mousedown.stop.prevent="startConnectorDrag(n)" />
                <g class="node-menu" :transform="`translate(${n.w + 16},${-6})`">
                  <rect class="menu-shell" width="80" height="68" rx="8" ry="8" />
                  <g class="menu-item" @mousedown.stop @click.stop="openInfoEditor(n)">
                    <title>Editar informações</title>
                    <rect class="menu-item-bg" x="8" y="8" width="28" height="22" rx="6" ry="6" />
                    <foreignObject class="menu-icon-wrapper" x="8" y="8" width="28" height="22">
                      <div class="menu-icon" xmlns="http://www.w3.org/1999/xhtml">
                        <i class="fa-solid fa-pencil"></i>
                      </div>
                    </foreignObject>
                  </g>
                  <g class="menu-item" @mousedown.stop @click.stop="openInfoViewer(n)">
                    <title>Visualizar informações</title>
                    <rect class="menu-item-bg" x="44" y="8" width="28" height="22" rx="6" ry="6" />
                    <foreignObject class="menu-icon-wrapper" x="44" y="8" width="28" height="22">
                      <div class="menu-icon" xmlns="http://www.w3.org/1999/xhtml">
                        <i class="fa-solid fa-magnifying-glass"></i>
                      </div>
                    </foreignObject>
                  </g>
                  <g class="menu-item" @mousedown.stop @click.stop="startConnectFromMenu(n)">
                    <title>Conectar</title>
                    <rect class="menu-item-bg" x="8" y="38" width="28" height="22" rx="6" ry="6" />
                    <foreignObject class="menu-icon-wrapper" x="8" y="38" width="28" height="22">
                      <div class="menu-icon" xmlns="http://www.w3.org/1999/xhtml">
                        <i class="fa-solid fa-link"></i>
                      </div>
                    </foreignObject>
                  </g>
                  <g class="menu-item" @mousedown.stop @click.stop="deleteSelected">
                    <title>Excluir</title>
                    <rect class="menu-item-bg" x="44" y="38" width="28" height="22" rx="6" ry="6" />
                    <foreignObject class="menu-icon-wrapper" x="44" y="38" width="28" height="22">
                      <div class="menu-icon" xmlns="http://www.w3.org/1999/xhtml">
                        <i class="fa-regular fa-trash-can"></i>
                      </div>
                    </foreignObject>
                  </g>
                </g>
              </g>

              <!-- start/end -->
              <g v-else-if="n.type==='startEvent' || n.type==='endEvent'" class="node" :class="{ selected: selectedId===n.id }"
                 :transform="`translate(${n.x},${n.y})`"
                 @mousedown.stop="onNodeDown($event, n)"
                 @mouseup.stop="onNodeConnectDrop(n)"
                 @click.stop="onNodeClick(n)">
                <circle :cx="n.w/2" :cy="n.h/2" :r="n.w/2 - 2" :class="n.type" />
                <text v-if="!isEditingName(n)" class="node-title" :x="n.w/2" :y="n.h + 16" text-anchor="middle" @mousedown.stop @click.stop="beginNameEdit(n)">{{ n.name }}</text>
                <foreignObject v-else :x="0" :y="n.h + 4" :width="n.w" height="24" @mousedown.stop @click.stop>
                  <div class="node-name-input-wrap centered" xmlns="http://www.w3.org/1999/xhtml">
                    <input
                      ref="nameInputRef"
                      v-model="nameEditor.value"
                      class="node-name-input centered"
                      @keydown.enter.prevent="saveNameEdit"
                      @keydown.esc.prevent="cancelNameEdit"
                      @blur="saveNameEdit"
                    />
                  </div>
                </foreignObject>
                <circle class="connector" :cx="n.w + connectorOffset" :cy="n.h / 2" r="6"
                        @mousedown.stop.prevent="startConnectorDrag(n)" />
                <g class="node-menu" :transform="`translate(${n.w + 16},${-6})`">
                  <rect class="menu-shell" width="80" height="68" rx="8" ry="8" />
                  <g class="menu-item" @mousedown.stop @click.stop="openInfoEditor(n)">
                    <title>Editar informações</title>
                    <rect class="menu-item-bg" x="8" y="8" width="28" height="22" rx="6" ry="6" />
                    <foreignObject class="menu-icon-wrapper" x="8" y="8" width="28" height="22">
                      <div class="menu-icon" xmlns="http://www.w3.org/1999/xhtml">
                        <i class="fa-solid fa-pencil"></i>
                      </div>
                    </foreignObject>
                  </g>
                  <g class="menu-item" @mousedown.stop @click.stop="openInfoViewer(n)">
                    <title>Visualizar informações</title>
                    <rect class="menu-item-bg" x="44" y="8" width="28" height="22" rx="6" ry="6" />
                    <foreignObject class="menu-icon-wrapper" x="44" y="8" width="28" height="22">
                      <div class="menu-icon" xmlns="http://www.w3.org/1999/xhtml">
                        <i class="fa-solid fa-magnifying-glass"></i>
                      </div>
                    </foreignObject>
                  </g>
                  <g class="menu-item" @mousedown.stop @click.stop="startConnectFromMenu(n)">
                    <title>Conectar</title>
                    <rect class="menu-item-bg" x="8" y="38" width="28" height="22" rx="6" ry="6" />
                    <foreignObject class="menu-icon-wrapper" x="8" y="38" width="28" height="22">
                      <div class="menu-icon" xmlns="http://www.w3.org/1999/xhtml">
                        <i class="fa-solid fa-link"></i>
                      </div>
                    </foreignObject>
                  </g>
                  <g class="menu-item" @mousedown.stop @click.stop="deleteSelected">
                    <title>Excluir</title>
                    <rect class="menu-item-bg" x="44" y="38" width="28" height="22" rx="6" ry="6" />
                    <foreignObject class="menu-icon-wrapper" x="44" y="38" width="28" height="22">
                      <div class="menu-icon" xmlns="http://www.w3.org/1999/xhtml">
                        <i class="fa-regular fa-trash-can"></i>
                      </div>
                    </foreignObject>
                  </g>
                </g>
              </g>

              <!-- gateway -->
              <g v-else-if="n.type==='exclusiveGateway'" class="node" :class="{ selected: selectedId===n.id }"
                 :transform="`translate(${n.x},${n.y})`"
                 @mousedown.stop="onNodeDown($event, n)"
                 @mouseup.stop="onNodeConnectDrop(n)"
                 @click.stop="onNodeClick(n)">
                <polygon :points="diamondPoints(n.w, n.h)" />
                <text v-if="!isEditingName(n)" class="node-title" :x="n.w/2" :y="n.h + 16" text-anchor="middle" @mousedown.stop @click.stop="beginNameEdit(n)">{{ n.name }}</text>
                <foreignObject v-else :x="0" :y="n.h + 4" :width="n.w" height="24" @mousedown.stop @click.stop>
                  <div class="node-name-input-wrap centered" xmlns="http://www.w3.org/1999/xhtml">
                    <input
                      ref="nameInputRef"
                      v-model="nameEditor.value"
                      class="node-name-input centered"
                      @keydown.enter.prevent="saveNameEdit"
                      @keydown.esc.prevent="cancelNameEdit"
                      @blur="saveNameEdit"
                    />
                  </div>
                </foreignObject>
                <circle class="connector" :cx="n.w + connectorOffset" :cy="n.h / 2" r="6"
                        @mousedown.stop.prevent="startConnectorDrag(n)" />
                <g class="node-menu" :transform="`translate(${n.w + 16},${-6})`">
                  <rect class="menu-shell" width="80" height="68" rx="8" ry="8" />
                  <g class="menu-item" @mousedown.stop @click.stop="openInfoEditor(n)">
                    <title>Editar informações</title>
                    <rect class="menu-item-bg" x="8" y="8" width="28" height="22" rx="6" ry="6" />
                    <foreignObject class="menu-icon-wrapper" x="8" y="8" width="28" height="22">
                      <div class="menu-icon" xmlns="http://www.w3.org/1999/xhtml">
                        <i class="fa-solid fa-pencil"></i>
                      </div>
                    </foreignObject>
                  </g>
                  <g class="menu-item" @mousedown.stop @click.stop="openInfoViewer(n)">
                    <title>Visualizar informações</title>
                    <rect class="menu-item-bg" x="44" y="8" width="28" height="22" rx="6" ry="6" />
                    <foreignObject class="menu-icon-wrapper" x="44" y="8" width="28" height="22">
                      <div class="menu-icon" xmlns="http://www.w3.org/1999/xhtml">
                        <i class="fa-solid fa-magnifying-glass"></i>
                      </div>
                    </foreignObject>
                  </g>
                  <g class="menu-item" @mousedown.stop @click.stop="startConnectFromMenu(n)">
                    <title>Conectar</title>
                    <rect class="menu-item-bg" x="8" y="38" width="28" height="22" rx="6" ry="6" />
                    <foreignObject class="menu-icon-wrapper" x="8" y="38" width="28" height="22">
                      <div class="menu-icon" xmlns="http://www.w3.org/1999/xhtml">
                        <i class="fa-solid fa-link"></i>
                      </div>
                    </foreignObject>
                  </g>
                  <g class="menu-item" @mousedown.stop @click.stop="deleteSelected">
                    <title>Excluir</title>
                    <rect class="menu-item-bg" x="44" y="38" width="28" height="22" rx="6" ry="6" />
                    <foreignObject class="menu-icon-wrapper" x="44" y="38" width="28" height="22">
                      <div class="menu-icon" xmlns="http://www.w3.org/1999/xhtml">
                        <i class="fa-regular fa-trash-can"></i>
                      </div>
                    </foreignObject>
                  </g>
                </g>
              </g>
            </template>
          </g>

          <!-- connection preview -->
          <line v-if="connectPreview.show" class="edge preview"
                :x1="connectPreview.x1" :y1="connectPreview.y1"
                :x2="connectPreview.x2" :y2="connectPreview.y2"
                marker-end="url(#arrow)" />
        </svg>
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
  </div>

  <script src="https://unpkg.com/vue@3/dist/vue.global.prod.js"></script>
  <script src="/Bpmn/bpmn-editor.js"></script>
</form>
</body>
</html>
